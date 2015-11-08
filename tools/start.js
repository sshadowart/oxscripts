import debounce from 'debounce';
import colors from 'colors';
import del from 'del';
import task from './lib/task';
import watch from './lib/watch';
import cfs from './lib/fs';
import bundle from './bundle';

const luaOutputPath = 'build/ox.lua';
const reloadPort = 3000;
const watchDebounce = 2000;
const spawnName = process.env.npm_config_script;
const homePath = cfs.getUserHome();
const scriptpath = `${homePath}/Documents/XenoBot/Settings/${spawnName}.xbst`;

let runTimeout;

process.env.LIVE_RELOAD = true;


function rebuild(event, filepath) {
  // Show what file changed
  console.log(filepath + ' was ' + event);

  // Build script 
  bundle();
};

/**
 * Monitor Lua source file for changes.
 */
export default task('start', async () => {
  // Script required for start task
  if (!spawnName) {
    console.log(colors.red.underline('You must specify a script name with npm start.'));
    return;
  }

  // Build script immediately
  bundle();

  // Build on source change
  watch('./src/*.lua').then(watcher => {
    watcher.on('all', debounce(rebuild, watchDebounce));
  });
});