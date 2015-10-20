import task from './lib/task';
import glob from 'glob-all';
import child_process from 'child_process';

/**
 * Run simple lint test on libary.
 */
export default task('test', () => {
  let paths = glob.sync('./src/*.lua');
  paths.forEach(function(path) {
      let output = child_process.execSync('luac -p ' + path, {
        timeout: 3000,
        encoding: 'utf8'
      });
      console.log(`Linting ${path}...`);
  });
});

