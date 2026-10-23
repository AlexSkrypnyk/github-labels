#!/usr/bin/env bats
#
# Test github-labels.sh end-to-end with a mocked 'curl'.
#
# Example usage:
# ./tests/bats/node_modules/.bin/bats tests/bats
#
# shellcheck disable=SC2030,SC2031,SC2034

load _helper

@test "Repository and token are requested interactively" {
  declare -a STEPS=(
    "This script will remove the default GitHub labels."
    "Enter GitHub Org/Repo, or Org for all its repositories (e.g. myorg/myrepo or myorg):"
    "GitHub Personal Access Token:"
    "$(step_access)"
    "$(step_list 1 "[]")"
    "- Removing label"
  )
  steps_labels
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  tui_run "${TEST_REPO}" "${TEST_TOKEN}"
  assert_success
  tui_assert_prompts "Enter GitHub Org/Repo" "GitHub Personal Access Token"

  steps_run "assert" "${mocks}"
}

@test "Repository is read from the first argument" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "- Enter GitHub Org/Repo"
    "- GitHub Personal Access Token:"
    "$(step_access)"
    "$(step_list 1 "[]")"
  )
  steps_labels
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Repository is read from GITHUB_REPO before the first argument" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  export GITHUB_REPO="${TEST_REPO}"

  declare -a STEPS=(
    "- Enter GitHub Org/Repo"
    "$(step_access)"
    "$(step_list 1 "[]")"
  )
  steps_labels
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "otherorg/otherrepo"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Missing repository fails" {
  mock_command "curl" >/dev/null

  tui_run ""
  assert_failure
  assert_output_contains "[FAIL] GitHub repository name is required"
  mock_assert_no_calls
}

@test "Invalid arguments fail before any request" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  mock_command "curl" >/dev/null

  dataprovider_run_cases "run_script" "provide_invalid_arguments"

  mock_assert_no_calls
}

run_script() {
  "${SCRIPT_FILE}" "$@"
}

provide_invalid_arguments() {
  dataprovider_case "empty repo" "myorg/" "[FAIL] GitHub repository must be in the format \"org/repo\" or \"org\""
  dataprovider_case "empty org" "/myrepo" "[FAIL] GitHub repository must be in the format \"org/repo\" or \"org\""
  dataprovider_case "extra segment" "myorg/myrepo/extra" "[FAIL] GitHub repository must be in the format \"org/repo\" or \"org\""
  dataprovider_case "whitespace" "my org/myrepo" "[FAIL] GitHub repository must be in the format \"org/repo\" or \"org\""
  dataprovider_case "url" "https://github.com/myorg/myrepo" "[FAIL] GitHub repository must be in the format \"org/repo\" or \"org\""
  dataprovider_case "unknown option" "myorg" "--force" "[FAIL] Unknown option \"--force\""
  dataprovider_case "exclude without separator" "--exclude=myorg/one,two" "myorg" "[FAIL] Excluded repository \"two\" must be in the format \"org/repo\""
  dataprovider_case "exclude with another org" "myorg" "--exclude=myorg/one,otherorg/two" "[FAIL] Excluded repository \"otherorg/two\" does not belong to \"myorg\""
  dataprovider_case "exclude with a repository" "myorg/myrepo" "--exclude=myorg/one" "[FAIL] Option --exclude can only be used with an organization, not with a repository"
}

@test "Missing token fails" {
  export GITHUB_REPO="${TEST_REPO}"
  mock_command "curl" >/dev/null

  tui_run ""
  assert_failure
  tui_assert_prompts "GitHub Personal Access Token"
  assert_output_contains "[FAIL] GitHub token is required"
  mock_assert_no_calls
}

@test "Missing curl fails" {
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin_dir}"

  run env PATH="${bin_dir}" "${BASH}" "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_failure
  assert_output_contains "[FAIL] Command curl is not available"
}

@test "Repository without access fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_access 404)"
    "[FAIL] User does not have access to specified repository. Please check your credentials"
    "- Starting label processing"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Network failure during the access check fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "@curl -s -u ${TEST_TOKEN}:x-oauth-basic -H Accept: application/vnd.github+json -w \\n%{http_code} --request GET https://api.github.com/repos/${TEST_REPO}/labels?per_page=1 # 7"
    "[FAIL] User does not have access to specified repository. Please check your credentials"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Failure to list existing labels fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_access)"
    "$(step_list 1 '{"message":"Server Error"}' 500)"
    "[FAIL] Unable to fetch existing labels"
    "- Processing label"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Labels not in the provided list are deleted and matching labels are updated" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_access)"
    "$(step_list 1 "$(labels_json "bug" "blocked" "URGENT" "good first issue")")"
    "Removing label \"bug\" as it is not in the provided list"
    "$(step_api DELETE "/labels/bug" 204)"
    "DELETED label \"bug\""
    "Removing label \"good first issue\" as it is not in the provided list"
    "$(step_api DELETE "/labels/good%20first%20issue" 204)"
    "DELETED label \"good first issue\""
    "- Removing label \"blocked\""
    "- Removing label \"URGENT\""
  )
  steps_labels "BLOCKED|update|200|blocked" "URGENT|update|200|URGENT"
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Labels not in the provided list are preserved when deletion is disabled" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  export GITHUB_DELETE_EXISTING_LABELS=0

  declare -a STEPS=(
    "This script will not remove the default GitHub labels."
    "$(step_api GET "/labels?per_page=1" 200 "[]")"
    "$(step_list 1 "$(labels_json "bug" "Dependencies")")"
    "- Removing label"
    "- DELETED label"
  )
  steps_labels "Dependencies|update|200|Dependencies"
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Existing labels are read from every page" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  export GITHUB_DELETE_EXISTING_LABELS=0

  local -a page_one=()
  local i
  for ((i = 1; i <= 100; i++)); do
    page_one+=("label-${i}")
  done

  declare -a STEPS=(
    "$(step_access)"
    "$(step_list 1 "$(labels_json "${page_one[@]}")")"
    "$(step_list 2 "$(labels_json "do not merge")")"
  )
  steps_labels "DO NOT MERGE|update|200|do not merge"
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Failed label operations are reported and fail the run" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_access)"
    "$(step_list 1 "$(labels_json "bug" "Needs review")")"
    "$(step_api DELETE "/labels/bug" 403 '{"message":"Forbidden"}')"
    "Unable to DELETE label \"bug\""
  )
  steps_labels "CONFLICT|create|422|" "Needs review|update|500|Needs review"
  STEPS+=(
    "[FAIL] Label processing completed with 3 error(s)"
    "- [ OK ] Label processing complete"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Countdown is shown before processing starts" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  export GITHUB_PROCESSING_DELAY=1

  declare -a STEPS=(
    "$(step_access)"
    "Processing will start in 1 seconds. Press Ctrl+C to abort"
    "$(step_list 1 "[]")"
  )
  steps_labels

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Countdown is skipped when the delay is 0" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_access)"
    "- Processing will start in"
    "$(step_list 1 "[]")"
  )
  steps_labels

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "${TEST_REPO}"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Organization repositories are listed, confirmed and processed" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  export GITHUB_REPO="myorg"

  declare -a STEPS=(
    "$(step_owner myorg Organization)"
    "$(step_repos "/orgs/myorg/repos?type=all" 1 "$(repos_json "myorg/one" "myorg/old:archived" "myorg/two")")"
    "Found 2 repositories in \"myorg\":"
    "myorg/one"
    "myorg/two"
    "- myorg/old"
    "Skipped 1 archived and 0 excluded repositories"
  )
  steps_repos_labels "myorg/one" "myorg/two"
  STEPS+=(
    "[ OK ] Label processing complete"
    "- [FAIL]"
  )

  mocks="$(steps_run "setup")"

  tui_run "y"
  assert_success
  tui_assert_prompts "Update labels in 2 repositories? [y/N]"

  steps_run "assert" "${mocks}"
}

@test "User repositories are listed from the token's own repositories" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_owner myuser User)"
    "$(step_repos "/user/repos?affiliation=owner" 1 "$(repos_json "myuser/one" "otheruser/fork" "MyUser/two")")"
    "Found 2 repositories in \"myuser\":"
    "- otheruser/fork"
    "- Update labels in"
  )
  steps_repos_labels "myuser/one" "MyUser/two"
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myuser" "--yes"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Excluded repositories are skipped" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_owner myorg Organization)"
    "$(step_repos "/orgs/myorg/repos?type=all" 1 "$(repos_json "myorg/one" "myorg/two" "myorg/three")")"
    "Found 1 repositories in \"myorg\":"
    "Skipped 0 archived and 2 excluded repositories"
    "- Processing repository \"myorg/two\""
    "- Processing repository \"myorg/three\""
  )
  steps_repos_labels "myorg/one"
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myorg" "--exclude=myorg/two,MYORG/Three,myorg/missing,," "-y"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Repositories are read from every page" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  local -a page_one=()
  local i
  for ((i = 1; i <= 100; i++)); do
    page_one+=("myorg/old-${i}:archived")
  done

  declare -a STEPS=(
    "$(step_owner myorg Organization)"
    "$(step_repos "/orgs/myorg/repos?type=all" 1 "$(repos_json "${page_one[@]}")")"
    "$(step_repos "/orgs/myorg/repos?type=all" 2 "$(repos_json "myorg/one")")"
    "Found 1 repositories in \"myorg\":"
    "Skipped 100 archived and 0 excluded repositories"
  )
  steps_repos_labels "myorg/one"
  STEPS+=("[ OK ] Label processing complete")

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myorg" "--yes"
  assert_success

  steps_run "assert" "${mocks}"
}

@test "Declining the confirmation aborts" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  export GITHUB_REPO="myorg"

  declare -a STEPS=(
    "$(step_owner myorg Organization)"
    "$(step_repos "/orgs/myorg/repos?type=all" 1 "$(repos_json "myorg/one")")"
    "[FAIL] Aborted"
    "- Starting label processing"
  )

  mocks="$(steps_run "setup")"

  tui_run "n"
  assert_failure
  tui_assert_prompts "Update labels in 1 repositories? [y/N]"

  steps_run "assert" "${mocks}"
}

@test "Unknown owner fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_owner myorg Organization 404)"
    "[FAIL] Unable to find \"myorg\". Please check the name and your credentials"
    "- Starting label processing"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myorg" "--yes"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Owner without a type fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_request GET "/users/myorg" 200 '{"login":"myorg"}')"
    "[FAIL] Unable to find \"myorg\". Please check the name and your credentials"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myorg" "--yes"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Failure to list repositories fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_owner myorg Organization)"
    "$(step_repos "/orgs/myorg/repos?type=all" 1 '{"message":"Server Error"}' 500)"
    "[FAIL] Unable to list repositories of \"myorg\""
    "- Starting label processing"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myorg" "--yes"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Organization without repositories to process fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_owner myorg Organization)"
    "$(step_repos "/orgs/myorg/repos?type=all" 1 "$(repos_json "myorg/old:archived" "myorg/one")")"
    "[FAIL] No repositories to process in \"myorg\""
    "- Starting label processing"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myorg" "--exclude=myorg/one" "--yes"
  assert_failure

  steps_run "assert" "${mocks}"
}

@test "Failed repository does not stop the others and fails the run" {
  export GITHUB_TOKEN="${TEST_TOKEN}"

  declare -a STEPS=(
    "$(step_owner myorg Organization)"
    "$(step_repos "/orgs/myorg/repos?type=all" 1 "$(repos_json "myorg/one" "myorg/two")")"
    "Processing repository \"myorg/one\""
  )
  TEST_REPO="myorg/one"
  STEPS+=(
    "$(step_list 1 '{"message":"Server Error"}' 500)"
    "[FAIL] Unable to fetch existing labels"
  )
  steps_repos_labels "myorg/two"
  STEPS+=(
    "[FAIL] Label processing failed in 1 of 2 repositories:"
    "- [ OK ] Label processing complete"
  )

  mocks="$(steps_run "setup")"

  run "${SCRIPT_FILE}" "myorg" "--yes"
  assert_failure

  steps_run "assert" "${mocks}"
}
