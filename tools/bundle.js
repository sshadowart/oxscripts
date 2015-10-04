import fs from 'fs';
import path from 'path';
import child_process from 'child_process';
import replace from 'replace';
import colors from 'colors';
import concat from 'concat-files';
import glob from 'glob-all';
import zmq from 'zmq';
import del from 'del';
import open from 'open';
import readm from 'read-multiple-files';
import fse from 'fs-extra';
import task from './lib/task';
import copy from './lib/copy';
import watch from './lib/watch';
import cfs from './lib/fs';

const luaOutputPath = 'build/ox.lua';
const reloadPort = 3000;
const vocationsMap = {
  '(MS)': 'Sorcerer',
  '(ED)': 'Druid',
  '(EK)': 'Knight',
  '(RP)': 'Paladin'
};

let vocationTags = Object.keys(vocationsMap);
let spawnName = process.env.npm_config_script;

/**
 * Concatenate and modify the final build script
 */
export default task('bundle', async () => {
  // Clean build folder
  await require('./clean')();
  // Combine all lua together
  concat(glob.sync('./src/*.lua'), luaOutputPath, function() {
    // Lint source
    let lint;
    try {
      // TODO: check for luac depedency
      lint = child_process.execSync('luac -p ' + luaOutputPath, {
        timeout: 3000,
        encoding: 'utf8'
      });
    } catch (e) {
      console.log(colors.red.underline('Failed to build library due to syntax errors.'));
    }

    // Modify concatenated library
    fs.readFile(luaOutputPath, function (err, luaOutputData) {
      if (err) throw err;

      // Generate sync script
      let timestamp = Date.now();
      let homePath = cfs.getUserHome();
      let reloadScript = `
        do
          local pub = IpcPublisherSocket.New("pub", ${reloadPort+1})
          local sub = IpcSubscriberSocket.New("sub", ${reloadPort})
          sub:AddTopic("live-reload")
          while (true) do
              local message, topic, data = sub:Recv()
              if message then
                print('Reloading library...')
                loadSettings('${spawnName}', "Scripter")
                pub:PublishMessage("live-reload", Self.Name());
              end
              wait(200)
          end
        end`;

      // Load spawn XBST
      fs.readFile(`./waypoints/${spawnName}.xbst`, function (err, xbstData) {
        if (err) throw err;

        // Detect town from waypoints
        xbstData = xbstData.toString('utf8');
        let townMatches = xbstData.match(/text="(.+)\|.+~spawn/);
        let townName = townMatches ? townMatches[1] : undefined;

        // Unable to detect town
        if (!townName) {
          console.log(colors.red.underline('Failed to detect town from spawn. Check XBST.'));
          return;
        }

        // Load spawn config
        fs.readFile(`./configs/${spawnName}.ini`, function (err, configData) {
          if (err) throw err;

          // Determine vocation from spawnName
          let vocationName = 'unknown';
          for (var i = 0; i < vocationTags.length; i++) {
            let tag = vocationTags[i];
            if (spawnName.indexOf(tag) !== -1) {
              vocationName = vocationsMap[tag];
              break;
            }
          }

          // Replace tokens
          let data = luaOutputData.toString('utf8');
          data = data.replace('{{VERSION}}', 'local');
          data = data.replace('{{SCRIPT_TOWN}}', townName);
          data = data.replace('{{SCRIPT_NAME}}', spawnName);
          data = data.replace('{{SCRIPT_VOCATION}}', vocationName);

          // Insert config
          data = data.replace('{{CONFIG}}', configData.toString('utf8'));

          // Base 64 encode lua
          let encodedLua = new Buffer(data).toString('base64');
          let encodedReload = new Buffer(reloadScript).toString('base64');
          let combinedWaypoints;
          
          // Write to XBST
          let scripterPanelXML = `
            <panel name="Scripter">
              <control name="RunningScriptList">
              <script name=".ox.${timestamp}.lua"><![CDATA[${encodedLua}]]></script>
              <script name=".sync.${timestamp}.lua"><![CDATA[${encodedReload}]]></script>
              </control>
            </panel>`;

          // Get all the town waypoints
          var townPaths = glob.sync('./waypoints/towns/*.json'),
            townWaypoints = [];
          readm(townPaths, (err, towns) => {
            if (err) {
              throw err;
            }

            // Iterate through towns
            towns.forEach((waypoints) => {
              let townData = JSON.parse(waypoints);
              // Iterate through waypoints in each town
              townData.forEach((item) => {
                // Add waypoint string to array
                townWaypoints.push(`\n\t\t<item text="${item.label}" tag="${item.tag}"/>`);
              });
            });

            // Combine waypoints
            townWaypoints.push('\n');
            combinedWaypoints = townWaypoints.join('');

            // Combine spawn file with town waypoints
            let insertPoint = '<control name="WaypointList">\r\n';
            let xbstCombinedData = xbstData.toString('utf8');
            xbstCombinedData = xbstCombinedData.replace(insertPoint, insertPoint + combinedWaypoints);
            
            // Combine spawn file with other xml data
            xbstCombinedData += '\n' + scripterPanelXML;

            // Save XBST
            let scriptpath = `${homePath}\\Documents\\XenoBot\\Settings\\${spawnName}.xbst`;
            fs.writeFile(scriptpath, xbstCombinedData, function (err) {
              // Send update flag to Tibia Clients
              let subscriber = zmq.socket('sub');
              let publisher = zmq.socket('pub');
              subscriber.connect(`tcp://127.0.0.1:${reloadPort+1}`);
              subscriber.subscribe('live-reload');

              let runTimeout;

              // Success message
              console.log(colors.green(`Successfully built ${spawnName}.`));

              // Listen to responses from Xenobot
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
                    // Timed out, start the reload script
                    open(scriptpath);
                    // Success message
                    console.log('Starting the reload script in the client.');
                    // Close listener
                    if (subscriber)
                      subscriber.close();
                  }, 3000);

                  // Close the publish socket
                  publisher.close();

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
        });
      });
    });
  });
});
