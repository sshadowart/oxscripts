import fs from 'fs';
import path from 'path';
import process from 'child_process';
import replace from 'replace';
import colors from 'colors';
import concat from 'concat-files';
import glob from 'glob-all';
import zmq from 'zmq';
import del from 'del';
import task from './lib/task';
import copy from './lib/copy';
import watch from './lib/watch';
import cfs from './lib/fs';

const output = 'build/ox.lua';
const reloadPort = 3000;

/**
 * Concatenate and modify the final build script
 */
export default task('bundle', async () => {
  // Combine all lua together
  let sock = zmq.socket('pub');
  concat(glob.sync('./src/*.lua'), output, function() {
    // Lint source
    let lint;
    try {
      // TODO: check for luac depedency
      lint = process.execSync('luac -p ' + output, {
        timeout: 3000,
        encoding: 'utf8'
      });

      // Modify concatenated library
      fs.readFile(output, function (err, data) {
        if (err) throw err;

        // Generate sync script
        let timestamp = Date.now();
        let homePath = cfs.getUserHome();
        let reloadScript = `do
          local sub = IpcSubscriberSocket.New("sub", ${reloadPort})
          sub:AddTopic("live-reload")
          while (true) do
              local message, topic, data = sub:Recv()
              if message then
                print('Reloading library...')
                loadSettings("ox", "Scripter")
              end
              wait(200)
          end
        end`;

        // Base 64 encode lua
        let encodedLua = data.toString('base64');
        let encodedReload = new Buffer(reloadScript).toString('base64');
        
        // Write to XBST
        let template = `<panel name="Scripter">
          <control name="RunningScriptList">
          <script name=".ox.${timestamp}.lua"><![CDATA[${encodedLua}]]></script>
          <script name=".sync.${timestamp}.lua"><![CDATA[${encodedReload}]]></script>
          </control>
        </panel>`;

        // Save XBST
        let scriptpath = homePath + '\\Documents\\XenoBot\\Settings\\ox.xbst';
        fs.writeFile(scriptpath, template, function (err) {
          // Send update flag to Tibia Clients
          let sock = zmq.socket('pub');
          sock.bind('tcp://127.0.0.1:' + reloadPort, function(err) {
            if (err) throw err;
            setTimeout(function() {
              sock.send(['live-reload', Date.now()]);
              sock.close();
              console.log(colors.green('Successfully built the ox library.'));

              // Delete old generated scripts
              del([
                `!.ox.${timestamp}.lua`, // Ignore new library
                `!.sync.${timestamp}.lua`, // Ignore new sync script
                '.ox.*.lua',
                '.sync.*.lua',
              ], {dot: true, cwd: homePath + '/Documents/XenoBot/Scripts/'});
            }, 1000);
          });
        });
      });

    } catch (e) {
      console.log(colors.red.underline('Failed to build library due to syntax errors.'));
    }
  });
});
