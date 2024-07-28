import sys
from packaging.version import Version

version = Version(sys.argv[1])
new_version = None

if version.is_devrelease:
    # For dev releases, increment the dev release number.
    new_version = f"{version.major}.{version.minor}.{version.micro}.dev{version.dev + 1}"
elif version.is_prerelease:
    # For pre releases, go back to dev release.
    rel_type, rel_num = version.pre
    new_version = f"{version.major}.{version.minor}.{version.micro}.dev0"
elif version.micro == 0:
    # For minor releases, go to next minor release.
    new_version = f"{version.major}.{version.minor + 1}.0.dev0"
else:
    # For patch releases, go to the next patch release.
    new_version = f"{version.major}.{version.minor}.{version.micro + 1}.dev0"

print(str(new_version))