import path from 'path';
import task from './lib/task';
import watch from './lib/watch';

/**
 * Monitor Lua source file for changes.
 */
export default task('start', async () => {
  // Build immediately
  await require('./build')();
  // Run the XBST
  await require('./run')();
  // Watch source files
  watch('./src/*.lua').then(watcher => {
    // Build on change
    watcher.on('all', (event, filepath) => {
      console.log(filepath + ' was ' + event)
      require('./build')()
    });
  });
});