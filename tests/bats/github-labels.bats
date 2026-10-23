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
    "Enter GitHub Org/Repo (e.g. myorg/myrepo):"
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

@test "Invalid repository format fails" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  mock_command "curl" >/dev/null

  dataprovider_run_cases "run_script_with_repo" "provide_invalid_repositories"

  mock_assert_no_calls
}

run_script_with_repo() {
  "${SCRIPT_FILE}" "${1}"
}

provide_invalid_repositories() {
  dataprovider_case "no org" "myrepo" "[FAIL] GitHub repository must be in the format \"org/repo\""
  dataprovider_case "empty repo" "myorg/" "[FAIL] GitHub repository must be in the format \"org/repo\""
  dataprovider_case "empty org" "/myrepo" "[FAIL] GitHub repository must be in the format \"org/repo\""
  dataprovider_case "extra segment" "myorg/myrepo/extra" "[FAIL] GitHub repository must be in the format \"org/repo\""
  dataprovider_case "whitespace" "my org/myrepo" "[FAIL] GitHub repository must be in the format \"org/repo\""
  dataprovider_case "url" "https://github.com/myorg/myrepo" "[FAIL] GitHub repository must be in the format \"org/repo\""
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
