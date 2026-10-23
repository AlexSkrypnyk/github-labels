# Update project labels in GitHub.

[![Test](https://github.com/AlexSkrypnyk/github-labels/actions/workflows/test.yml/badge.svg)](https://github.com/AlexSkrypnyk/github-labels/actions/workflows/test.yml)

## Usage:
```shell
# Interactive prompt:
# ./github-labels.sh
#
# Silent, if $GITHUB_TOKEN or $GITHUB_TOKEN is set in an environment and
# a repository provided as an argument:
# GITHUB_TOKEN=ghp_123 GITHUB_REPO=myorg/myrepo ./github-labels.sh
```

The script needs Bash 4 or later and `curl`. Pass the repository as `org/repo`, either as the first argument or in `GITHUB_REPO`:

```shell
GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg/myrepo
```

The script reads these environment variables:

| Variable                        | Default | Description                                                                                   |
|---------------------------------|---------|-----------------------------------------------------------------------------------------------|
| `GITHUB_REPO`                   | None    | Repository as `org/repo`, or organization as `org`. Takes precedence over the first argument. |
| `GITHUB_TOKEN`                  | None    | Personal access token. The script prompts for it when empty.                                  |
| `GITHUB_DELETE_EXISTING_LABELS` | `1`     | If `1`, deletes every label missing from the list, so the repository mirrors it.              |
| `GITHUB_PROCESSING_DELAY`       | `3`     | Seconds to wait before changing labels. Press <kbd>Ctrl-C</kbd> to abort.                     |
| `DEBUG`                         | None    | If `1`, prints every command the script runs.                                                 |

Label names match case-insensitively. An existing `blocked` label gets renamed to `BLOCKED`, so it stays on its issues and pull requests.

The script exits with `1` when it can't create, update or delete a label.

## Update every repository of an organization

To update every repository of an organization or user, pass its name without `/repo`:

```shell
GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg
```

The script lists the repositories it will update and asks `Update labels in N repositories? [y/N]` before it changes anything. It skips archived repositories.

The owner type decides which repositories the list holds:

- For an organization, the list holds every repository the token can read, private ones included.
- For a user, the list holds the repositories the token's own user owns, so pass your own user name.

To skip repositories, list them in `--exclude`. Each entry is `org/repo` in the same organization. Any other entry stops the script before it sends a request:

```shell
GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg --exclude=myorg/repo1,myorg/repo2
```

To skip the confirmation, for example in CI, add `--yes` or `-y`:

```shell
GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg --yes
```

A failing repository doesn't stop the run. The script processes the remaining repositories, lists the failed ones and exits with `1`.

## Testing

The tests use [BATS](https://github.com/bats-core/bats-core) and [bats-helpers](https://github.com/drevops/bats-helpers). They replace `curl` with a mock, so they run offline.

To run the tests:

```shell
npm ci --prefix tests/bats
./tests/bats/node_modules/.bin/bats tests/bats
```
