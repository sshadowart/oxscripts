import task from './lib/task';
import glob from 'glob-all';
import readm from 'read-multiple-files';
import fs from 'fs-extra';

/**
 * Combines script JSON info files into a single files
 */
export default task('api', async () => {
  const paths = glob.sync('./info/*.json');
  await readm(paths, (err, scripts) => {
    if (err) throw err;
    const output = scripts.map(script => {
    	const contents = JSON.parse(script);
    	const name = encodeURIComponent(contents.name).split('%20').join('+');
    	contents.slug = `${name}+(${contents.vocshort}).xbst`;
    	return contents;
    });
    fs.writeJson('./build/list.json', output, function (err) {
      if (err) throw err;
    });
  });
});
