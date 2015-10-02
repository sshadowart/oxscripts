import process from 'child_process';
import open from 'open';
import task from './lib/task';
import fs from './lib/fs';

/**
 * Runs the compiled XBST file
 */
let homePath = fs.getUserHome();
let path = homePath + '\\Documents\\XenoBot\\Settings\\ox.xbst';
export default task('run', async () => {
  open(path); 
});
