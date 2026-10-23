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

| Variable                        | Default | Description                                                                      |
|---------------------------------|---------|----------------------------------------------------------------------------------|
| `GITHUB_REPO`                   | None    | Repository as `org/repo`. Takes precedence over the first argument.              |
| `GITHUB_TOKEN`                  | None    | Personal access token. The script prompts for it when empty.                     |
| `GITHUB_DELETE_EXISTING_LABELS` | `1`     | If `1`, deletes every label missing from the list, so the repository mirrors it. |
| `GITHUB_PROCESSING_DELAY`       | `3`     | Seconds to wait before changing labels. Press <kbd>Ctrl-C</kbd> to abort.        |
| `DEBUG`                         | None    | If `1`, prints every command the script runs.                                    |

Label names match case-insensitively. An existing `blocked` label gets renamed to `BLOCKED`, so it stays on its issues and pull requests.

The script exits with `1` when it can't create, update or delete a label.

## Testing

The tests use [BATS](https://github.com/bats-core/bats-core) and [bats-helpers](https://github.com/drevops/bats-helpers). They replace `curl` with a mock, so they run offline.

To run the tests:

```shell
npm ci --prefix tests/bats
./tests/bats/node_modules/.bin/bats tests/bats
```
