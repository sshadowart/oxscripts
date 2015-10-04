import task from './lib/task';

/**
 * Compiles the project from source files into a distributable
 * format and copies it to the output (build) folder.
 */
export default task('build', async () => {
  let spawnName = process.env.npm_config_script;
  await require('./clean')();
  await require('./bundle')(spawnName);
});

