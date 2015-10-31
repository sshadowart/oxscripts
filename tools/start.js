import path from 'path';
import debounce from 'debounce';
import colors from 'colors';
import del from 'del';
import task from './lib/task';
import watch from './lib/watch';
import cfs from './lib/fs';

try {
  const zmq = require('zmq');
} catch(e) {
  console.error(colors.red.underline('ZMQ not found, live reloading disabled. Run npm install zmq.'));
}

const luaOutputPath = 'build/ox.lua';
const reloadPort = 3000;
const watchDebounce = 2000;
const spawnName = process.env.npm_config_script;
const homePath = cfs.getUserHome();
const scriptpath = `${homePath}/Documents/XenoBot/Settings/${spawnName}.xbst`;

let runTimeout;

function rebuild(event, filepath) {
  // Show what file changed
  console.log(filepath + ' was ' + event);

  // Delete existing generated scripts
  del(['.ox.*.lua', '.sync.*.lua'], {dot: true, cwd: `${homePath}/Documents/XenoBot/Scripts/`});

  // Build script 
  require('./bundle')();

  // Dependency check
  if (typeof zmq === 'undefined')
    return;

  // Create a suscriber that listens to Tibia clients' responses,
  // and a publisher that sends reload flags when new scripts are built
  let subscriber = zmq.socket('sub');
  let publisher = zmq.socket('pub');

  // Clients publish 1 port above the reload port (eg: port 3001 for reload port 3000)
  subscriber.connect(`tcp://127.0.0.1:${reloadPort+1}`);

  // The only channel we're interested in is live-reload
  subscriber.subscribe('live-reload');

  // Listen to responses from Tibia clients
  subscriber.on('message', function(topic, message) {
    // We were waiting for a response from the reloaded client
    if (runTimeout) {
      // Clear the timeout that would start the reload script
      clearTimeout(runTimeout);
      console.log(`Reloaded ${message}'s client.`);
      // Close listener
      subscriber.close();
    }
  });

  publisher.bind(`tcp://127.0.0.1:${reloadPort}`, function(err) {
    if (err) throw err;
    setTimeout(function() {
      publisher.send(['live-reload', Date.now()]);

      // Wait for response from the client
      runTimeout = setTimeout(() => {
        // Timed out, launch the XBST file
        open(scriptpath);
        // Success message
        console.log('Starting the reload script in the client.');
        // Close listener
        if (subscriber)
          subscriber.close();
      }, 3000);

      // Close the publish socket
      publisher.close();
    }, 1000);
  });
};

/**
 * Monitor Lua source file for changes.
 */
export default task('start', async () => {
  // Watch source files
  watch('./src/*.lua').then(watcher => {
    // Build on change
    watcher.on('all', debounce(rebuild, watchDebounce));
  });
});