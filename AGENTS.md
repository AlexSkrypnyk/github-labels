# AGENTS.md

This file provides guidance to AI agents when working with
code in this repository.


## Project Overview

This project was created from the Scaffold template and provides a foundation
for Shell scripts, PHP CLI applications, and/or NodeJS projects with integrated
testing, code quality tools, and CI/CD workflows.


```bash
# Shell script tests
./tests/bats/node_modules/bats/bin/bats tests/bats/
```


### Shell Script Testing with BATS

Shell script tests use BATS:

- Tests in `tests/bats/` with `.bats` extension
- Helper functions in `tests/bats/_helper.bash`
- Coverage exclusions: `# LCOV_EXCL_START` / `# LCOV_EXCL_END`


- `.github/workflows/test-shell.yml` - Shell script testing
- `.github/workflows/release-assets.yml` - Attaches `github-labels.sh` to published releases


## Updating from the template

This project was generated from a template and can pull the template's latest
infrastructure (CI workflows, linting and test configuration, Docker, and docs)
at any time. When you are asked to "update scaffold", fetch the updater skill
from the template repository into the local `.claude/skills/` directory, then
invoke it:

1. Create the target directory if it does not exist:

   ```bash
   mkdir -p .claude/skills/update-consumer-scaffold
   ```

2. Download the skill:

   ```bash
   curl -sSL https://raw.githubusercontent.com/AlexSkrypnyk/scaffold/main/.scaffold/skills/update-consumer-scaffold/SKILL.md -o .claude/skills/update-consumer-scaffold/SKILL.md
   ```

3. Invoke the `update-consumer-scaffold` skill and follow its steps.

The skill directory is fetched on demand and is git-ignored - it is not
committed to the project.

## Configure the GitHub repository

When you are asked to configure the project's GitHub repository (settings,
labels or branch protection), run the following command in the project root:

```bash
curl -fsSL https://getscaffold.dev/install.sh | bash -s -- github
```

It needs GitHub CLI (`gh`) and a token in `SCAFFOLD_GITHUB_TOKEN`; it never
uses the logged-in `gh` account. It leaves the project files untouched. Add
`--dry-run` to print the changes without making them, and run with `--help`
for the section options.
