const { readFileSync } = require("fs");
const { join } = require("path");

const args = process.argv.slice(2);
if (!(args.length === 3 || args.length === 4)) {
  console.error(
    `usage: generate_release.js <package> <branch> <npm tag> <optional silk asset group>`,
  );
  process.exit(1);
}

const [package, branch, tag, assetGroup] = args;

const isNative =
  package === "kerberos" || package === "mongodb-client-encryption";
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
  .replaceAll("RELEASE_PACKAGE", package)
  .replaceAll("RELEASE_TAG", tag)
  .replaceAll("EVERGREEN_PROJECT", EVERGREEN_PROJECTS[package] ?? "")
  .replaceAll("IGNORE_INSTALL_SCRIPTS", isNative)
  .replaceAll("SILK_ASSET_GROUP", assetGroup ?? "''");

const project = EVERGREEN_PROJECTS[package];
if (!project) {
  const final = generated
    .split("\n")
    .filter((line) => !line.includes("evergreen"))
    .join("\n");
  process.stdout.write(final);
  process.exit();
}

process.stdout.write(generated);
