import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
    
const __dirname = dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
if (!(args.length === 3 || args.length === 4)) {
  console.error(
    `usage: generate_release.js <package> <branch> <npm tag> <optional silk asset group>`,
  );
  process.exit(1);
}

const [npmPackage, branch, tag, assetGroup] = args;

const isNative =
  npmPackage === "kerberos" || npmPackage === "mongodb-client-encryption";
const template = readFileSync(
  join(__dirname, "./release_template.yml"),
  "utf-8",
);

const EVERGREEN_PROJECTS = {
  mongodb: "mongo-node-driver-next",
  bson: "js-bson",
};

const generated = template
  .replaceAll("RELEASE_BRANCH", branch)
  .replaceAll("RELEASE_PACKAGE", npmPackage)
  .replaceAll("RELEASE_TAG", tag)
  .replaceAll("EVERGREEN_PROJECT", EVERGREEN_PROJECTS[npmPackage] ?? "")
  .replaceAll("IGNORE_INSTALL_SCRIPTS", isNative)
  .replaceAll("SILK_ASSET_GROUP", assetGroup ?? "''");

const project = EVERGREEN_PROJECTS[npmPackage];
if (!project) {
  const final = generated
    .split("\n")
    .filter((line) => !line.includes("evergreen"))
    .join("\n");
  process.stdout.write(final);
  process.exit();
}

process.stdout.write(generated);
