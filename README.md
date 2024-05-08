# drivers-github-tools

> [!IMPORTANT]
> This Repository is NOT a supported MongoDB product

This repository contains GitHub Actions that are common to drivers.

## Signing tools

The actions in the `garasign` folder are used to sign artifacts using the team's
GPG key.

### git-sign

Use this action to create signed git artifacts:
```markdown
- name: "Create signed commit"
  uses: mongodb/drivers-github-tools/garasign/git-sign@main
  with:
    command: "git commit -m 'Commit' -s --gpg-sign=${{ vars.GPG_KEY_ID }}"
    garasign_username: ${{ secrets.GRS_CONFIG_USER1_USERNAME }}
    garasign_password: ${{ secrets.GRS_CONFIG_USER1_PASSWORD }}
    artifactory_username: ${{ secrets.ARTIFACTORY_USER }}
    artifactory_password: ${{ secrets.ARTIFACTORY_PASSWORD }}

- name: "Create signed tag"
  uses: mongodb/drivers-github-tools/garasign/git-sign@main
  with:
    command: "git tag -m 'Tag' -s --local-user=${{ vars.GPG_KEY_ID }} <tag>"
    garasign_username: ${{ secrets.GRS_CONFIG_USER1_USERNAME }}
    garasign_password: ${{ secrets.GRS_CONFIG_USER1_PASSWORD }}
    artifactory_username: ${{ secrets.ARTIFACTORY_USER }}
    artifactory_password: ${{ secrets.ARTIFACTORY_PASSWORD }}
    skip_setup: true
```

If the action is used multiple times within the same job, the `skip_setup`
option can be set to a truthy value to avoid unnecessary logins to artifactory.

### gpg-sign

This action is used to create detached signatures for files:

```markdown
- name: "Create detached signature"
  uses: mongodb/drivers-github-tools/garasign/gpg-sign@main
  with:
    filenames: somefile.ext
    garasign_username: ${{ secrets.GRS_CONFIG_USER1_USERNAME }}
    garasign_password: ${{ secrets.GRS_CONFIG_USER1_PASSWORD }}
    artifactory_username: ${{ secrets.ARTIFACTORY_USER }}
    artifactory_password: ${{ secrets.ARTIFACTORY_PASSWORD }}
```

The action will create a signature file `somefile.ext.sig` in the working
directory.
If the action is used multiple times within the same job, the `skip_setup`
option can be set to a truthy value to avoid unnecessary logins to artifactory.

You can also supply multiple space-separated filenames to sign a list of files:

```markdown
- name: "Create detached signature"
  uses: mongodb/drivers-github-tools/garasign/gpg-sign@main
  with:
    filenames: somefile.ext someotherfile.txt
    garasign_username: ${{ secrets.GRS_CONFIG_USER1_USERNAME }}
    garasign_password: ${{ secrets.GRS_CONFIG_USER1_PASSWORD }}
    artifactory_username: ${{ secrets.ARTIFACTORY_USER }}
    artifactory_password: ${{ secrets.ARTIFACTORY_PASSWORD }}
```
