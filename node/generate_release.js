const { readFileSync } = require('fs');
const { join } = require('path');

const args = process.argv.slice(2);
if (args.length != 3) {
	console.error(`usage: generate_release.js <package> <branch> <npm tag>`);
	process.exitCode = 1;
	process.exit();
}

const [package, branch, tag] = args;

const template = readFileSync(join(__dirname, './release_template.yml'), 'utf-8');

const EVERGREEN_PROJECTS = {
	'mongodb': 'mongo-node-driver-next',
	'bson': 'js-bson'
};

const generated = template.replaceAll('RELEASE_BRANCH', branch)
	.replaceAll('RELEASE_PACKAGE', package)
	.replaceAll('RELEASE_TAG', tag)
	.replaceAll('EVERGREEN_PROJECT', EVERGREEN_PROJECTS[package] ?? '');

const project = EVERGREEN_PROJECTS[package];
if (!project) {
	const final = generated.split('\n').filter(line => !line.includes("evergreen")).join('\n');
	process.stdout.write(final);
	process.exit();
}

process.stdout.write(generated);