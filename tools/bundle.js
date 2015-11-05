import fs from 'fs';
import path from 'path';
import child_process from 'child_process';
import replace from 'replace';
import colors from 'colors';
import concat from 'concat-files';
import glob from 'glob-all';
import del from 'del';
import open from 'open';
import readm from 'read-multiple-files';
import crypto from 'crypto';
import fse from 'fs-extra';
import archiver from 'archiver';
import task from './lib/task';
import copy from './lib/copy';
import watch from './lib/watch';
import cfs from './lib/fs';

let zmq;
try { zmq = require('zmq') } catch(e) {}

const luaOutputPath = './build/lib.lua';
const packagePath = './build/scripts.zip';
const reloadPort = 3000;
const vocationsMap = {
  '(MS)': 'Sorcerer',
  '(ED)': 'Druid',
  '(EK)': 'Knight',
  '(RP)': 'Paladin'
};

const vocationTags = Object.keys(vocationsMap);
const homePath = cfs.getUserHome();

function buildFile(spawnName, luaOutputData, outputPath, outputName, buildCallback) {
  // Generate sync script
  let timestamp = Date.now();
  let reloadScript = `
    do
      local pub = IpcPublisherSocket.New("pub", ${reloadPort+1})
      local sub = IpcSubscriberSocket.New("sub", ${reloadPort})
      sub:AddTopic("live-reload")
      while (true) do
          local message, topic, data = sub:Recv()
          if message then
            print('Reloading library...')
            print("${outputName}")
            loadSettings("${outputName.replace('.xbst', '')}", "Scripter")
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
      for (let i = 0; i < vocationTags.length; i++) {
        let tag = vocationTags[i];
        if (spawnName.indexOf(tag) !== -1) {
          vocationName = vocationsMap[tag];
          break;
        }
      }

      // Build script version
      let version;
      if (process.env.TRAVIS_TAG)
        version = process.env.TRAVIS_TAG;
      else if(process.env.TRAVIS_BRANCH)
        version = `${process.env.TRAVIS_BRANCH}#${process.env.TRAVIS_BUILD_NUMBER}`;
      else
        version = 'local';

      // Replace tokens
      const configHash = crypto.createHash('md5').update(configData).digest('hex');
      let data = luaOutputData.toString('utf8');

      data = data.replace('{{VERSION}}', version);
      data = data.replace('{{SCRIPT_TOWN}}', townName);
      data = data.replace('{{SCRIPT_NAME}}', spawnName);
      data = data.replace('{{SCRIPT_SLUG}}', outputName);
      data = data.replace('{{SCRIPT_VOCATION}}', vocationName);
      data = data.replace('{{SCRIPT_CONFIG_HASH}}', configHash);

      // Insert config
      data = data.replace('{{CONFIG}}', configData.toString('utf8').replace(':::::::::::::::', `::${configHash}`));

      // Base 64 encode lua
      let encodedLua = new Buffer(data).toString('base64');
      let encodedReload = new Buffer(reloadScript).toString('base64');
      let combinedWaypoints;
      
      // Write to XBST
      console.log(timestamp);
      let scripterPanelXML = `
        <panel name="Scripter">
          <control name="RunningScriptList">
          <script name=".ox.${timestamp}.lua"><![CDATA[${encodedLua}]]></script>
          <script name=".sync.${timestamp}.lua"><![CDATA[${encodedReload}]]></script>
          </control>
        </panel>`;

      // Get all the town waypoints
      let townPaths = glob.sync('./waypoints/towns/*.json'),
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
        fs.writeFile(outputPath, xbstCombinedData, function (err) {
          console.log(colors.green(spawnName), outputPath);
          if (buildCallback)
            buildCallback(xbstCombinedData, timestamp);
        });
      });
    });
  });
}

/**
 * Concatenate and modify the final build script
 */
export default task('bundle', () => {

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
      console.log(colors.red.underline('Linting failed or luac depedency is missing.'), e.stderr);
    }

    // Spawn name provided from CLI
    const spawnName = process.env.npm_config_script;

    // Modify concatenated library
    fs.readFile(luaOutputPath, (err, luaOutputData) => {

      // Read error
      if (err) throw err;

      // Build single script
      if (spawnName) {
        const scriptInfo = require(`../info/${spawnName}.json`);
        const outputName = `[${scriptInfo.vocshort}] ${scriptInfo.name}.xbst`;
        const outputPath = `${homePath}/Documents/XenoBot/Settings/${outputName}`;
        buildFile(spawnName, luaOutputData, outputPath, outputName, (contents, timestamp) => {

          // User doesn't want live reload
          if (!process.env.LIVE_RELOAD)
            return;

          // ZMQ installed
          if (typeof zmq === 'undefined') {
            console.error(colors.red.underline('ZMQ not found, live reloading disabled. Run npm install zmq.'));
            return;
          }

          // Send update flag to Tibia Clients
          let subscriber = zmq.socket('sub');
          let publisher = zmq.socket('pub');
          subscriber.connect(`tcp://127.0.0.1:${reloadPort+1}`);
          subscriber.subscribe('live-reload');

          let runTimeout;

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
                open(outputPath);
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

      // Build all scripts
      } else {
        const stream = fs.createWriteStream(packagePath);
        const archive = archiver.create('zip', {});

        stream.on('close', function() {
          console.log(colors.green(`Successfully packaged ${spawnFiles.length} scripts.`), packagePath, archive.pointer() + ' bytes');
        });

        archive.on('error', function(err) {
          throw err;
        });

        archive.pipe(stream);

        const spawnFiles = glob.sync('./waypoints/*.xbst');
        let i = 0;
        spawnFiles.forEach((spawnPath) => {
          const fileName = path.basename(spawnPath, '.xbst');
          const scriptInfo = require(`../info/${fileName}.json`);
          const outputName = `[${scriptInfo.vocshort}] ${scriptInfo.name}.xbst`;
          const outputPath = `./build/${outputName}`;
          buildFile(fileName, luaOutputData, outputPath, outputName, (contents) => {
            i++;
            archive.append(new Buffer(contents), {name: outputName});
            if (i === spawnFiles.length) {
              console.log('Packaging scripts...');
              archive.finalize();
            }
          });
        });
      }
    });
  });

});
