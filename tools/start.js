import path from 'path';
import task from './lib/task';
import watch from './lib/watch';

/**
 * Monitor Lua source file for changes.
 */
export default task('start', () => new Promise((resolve, reject) => {
  // Build immediately
  require('./build')()
  // Watch source files
  watch('./src/*.lua').then(watcher => {
    // Build on change
    watcher.on('all', (event, filepath) => {
      console.log(filepath + ' was ' + event)
      require('./build')()
    });
  });
}));
