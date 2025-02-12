# GitHub Backup

A simple Ruby command line script that downloads zip files of all your GitHub repositories and Gists for backup purposes.

## Configuration

Run `ruby backup.rb config --github-access-token GITHUB_ACCESS_TOKEN --backup-directory BACKUP_DIRECTORY`, or copy `config.example.yaml` to `config.yaml` and edit the values.

The script uses a fine-grained personal access token, which you can create at <https://github.com/settings/personal-access-tokens/new>.
Select "all repositories", then give read-only access for "contents" (under repository permissions) and read-write access for "gists" (under "account permissions").
The script does not write anything, but there is no read-only permission level for gists.

The backup directory can be anywhere on your file system that you have write access to, as either an absolute or relative (from the script directory) path.
A `./backups` directory is provided as a default.

## Running backups

There are separate commands for backing up repositories and gists.

### Backing up repositories

Run `ruby backup.rb backup-repos`. By default, this will only get public repositories. Add `--private-repos` to also get private repositories.
For each repository, the script will download a zip file containing the current state of the default branch.

### Backing up gists

Run `ruby backup.rb backup-gists`. This will get all gists (public and secret).
For each gist, the script will download a zip file containing the latest version of all the files in that gist.

## Errors

Most errors are captured and presented with as much information as possible.

If you start seeing `403` errors, it's very likely that you've hit a rate limit. Try again later, and consider increasing the sleep between each request.
