# Contributing

Thank you for considering a contribution to this project. Follow this guide to install the dependencies and run the same linters and tests that CI runs on your pull request. Run the section for each stack your change touches, from the repository root.

## Shell

The linters need [ShellCheck](https://www.shellcheck.net/) and [shfmt](https://github.com/mvdan/sh) on your `PATH`. Install the BATS test dependencies, then run the linters and the tests:

```bash
npm ci --prefix tests/bats
shellcheck github-labels.sh tests/bats/*.bash tests/bats/*.bats
shfmt -i 2 -ci -s -d github-labels.sh tests/bats/*.bash tests/bats/*.bats
./tests/bats/node_modules/.bin/bats tests/bats
```

To apply the formatting that shfmt reports, run the shfmt command with `-w` in place of `-d`.

The tests use [BATS](https://github.com/bats-core/bats-core) and [bats-helpers](https://github.com/drevops/bats-helpers). They replace `curl` with a mock, so they run offline.

