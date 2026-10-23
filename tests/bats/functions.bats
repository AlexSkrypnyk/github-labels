#!/usr/bin/env bats
#
# Test the functions of github-labels.sh in isolation.
#
# shellcheck disable=SC2030,SC2031,SC2034

load _helper

@test "Script does not run when sourced" {
  mock_command "curl" >/dev/null

  run bash -c 'source "${1}"; echo "sourced"' bash "${SCRIPT_FILE}"
  assert_success
  assert_output "sourced"
  mock_assert_no_calls
}

@test "uriencode" {
  dataprovider_run_cases "uriencode" "provide_uriencode" "assert_output"
}

uriencode() {
  script_function uriencode "$@"
}

provide_uriencode() {
  dataprovider_case "plain" "BLOCKED" "BLOCKED"
  dataprovider_case "spaces" "DO NOT MERGE" "DO%20NOT%20MERGE"
  dataprovider_case "percent first" "100% done" "100%25%20done"
  dataprovider_case "slash" "area/ui" "area%2Fui"
  dataprovider_case "plus" "c++" "c%2B%2B"
  dataprovider_case "query" "a?b&c=d#e" "a%3Fb%26c%3Dd%23e"
  dataprovider_case "punctuation" '[x]: y,z;@$"' '%5Bx%5D%3A%20y%2Cz%3B%40%24%22'
  dataprovider_case "unicode" "🐛 bug" "🐛%20bug"
}

@test "json_escape" {
  dataprovider_run_cases "json_escape" "provide_json_escape" "assert_output"
}

json_escape() {
  script_function json_escape "$@"
}

provide_json_escape() {
  dataprovider_case "plain" "Do not merge" "Do not merge"
  dataprovider_case "apostrophe" "Something isn't working" "Something isn't working"
  dataprovider_case "double quotes" 'Say "hi"' 'Say \"hi\"'
  dataprovider_case "backslash" 'a\b' 'a\\b'
  dataprovider_case "backslash and quote" 'a\"b' 'a\\\"b'
}

@test "label_payload" {
  run script_function label_payload 'Say "hi"' "d93f0b" 'Path a\b'
  assert_success
  assert_output '{"name":"Say \"hi\"","color":"d93f0b","description":"Path a\\b"}'
}

@test "json_names" {
  dataprovider_run_cases "json_names" "provide_json_names" "assert_output"
}

json_names() {
  script_function json_names "$@"
}

provide_json_names() {
  dataprovider_case "compact" '[{"id":1,"name":"bug","color":"d73a4a"},{"id":2,"name":"DO NOT MERGE","color":"d93f0b"}]' $'bug\nDO NOT MERGE'
  dataprovider_case "pretty" $'[\n  {\n    "id": 1,\n    "name": "bug",\n    "color": "d73a4a"\n  },\n  {\n    "name" : "help wanted"\n  }\n]' $'bug\nhelp wanted'
  dataprovider_case "description mentions name" '[{"name":"bug","description":"The name of it"}]' "bug"
  dataprovider_case "single" '[{"name":"A1"}]' "A1"
}

@test "json_names returns nothing for an empty list" {
  run script_function json_names "[]"
  assert_success
  assert_output ""
}

@test "api_status" {
  dataprovider_run_cases "api_status" "provide_api_status" "assert_output"
}

api_status() {
  script_function api_status "$@"
}

provide_api_status() {
  dataprovider_case "body and status" $'[{"name":"bug"}]\n200' "200"
  dataprovider_case "multi-line body" $'[\n  {}\n]\n201' "201"
  dataprovider_case "status only" $'\n204' "204"
  dataprovider_case "no body" "000" "000"
}

@test "api_body" {
  dataprovider_run_cases "api_body" "provide_api_body" "assert_output"
}

api_body() {
  script_function api_body "$@"
}

provide_api_body() {
  dataprovider_case "body and status" $'[{"name":"bug"}]\n200' '[{"name":"bug"}]'
  dataprovider_case "multi-line body" $'[\n  {}\n]\n201' $'[\n  {}\n]'
}

@test "api_body returns nothing without a body" {
  run script_function api_body $'\n204'
  assert_success
  assert_output ""

  run script_function api_body "000"
  assert_success
  assert_output ""
}

@test "is_provided_label" {
  dataprovider_run_cases "is_provided_label" "provide_is_provided_label" "assert_output"
}

is_provided_label() {
  if script_function is_provided_label "$@"; then
    echo "provided"
  else
    echo "not provided"
  fi
}

provide_is_provided_label() {
  dataprovider_case "exact" "BLOCKED" "provided"
  dataprovider_case "different case" "blocked" "provided"
  dataprovider_case "with spaces" "do not merge" "provided"
  dataprovider_case "not provided" "bug" "not provided"
  dataprovider_case "partial" "BLOCK" "not provided"
  dataprovider_case "empty" "" "not provided"
}

@test "find_existing_label" {
  dataprovider_run_cases "find_existing_label" "provide_find_existing_label" "assert_output"
}

find_existing_label() {
  if bash -c 'source "${1}"; existing_labels=("bug" "Blocked" "do not merge"); find_existing_label "${2}"' bash "${SCRIPT_FILE}" "${1}"; then
    return 0
  fi

  echo "not found"
}

provide_find_existing_label() {
  dataprovider_case "exact" "bug" "bug"
  dataprovider_case "different case" "BLOCKED" "Blocked"
  dataprovider_case "with spaces" "DO NOT MERGE" "do not merge"
  dataprovider_case "missing" "URGENT" "not found"
}

@test "github_api passes the request to curl" {
  export GITHUB_TOKEN="${TEST_TOKEN}"
  export GITHUB_REPO="${TEST_REPO}"

  declare -a STEPS=(
    "$(step_api GET "/labels/bug" 200 '{"name":"bug"}')"
    "$(step_api POST "/labels" 201 "{}" '{"name":"A1","color":"0E8A16","description":"Worker 1"}')"
  )

  mocks="$(steps_run "setup")"

  run script_function github_api GET "/labels/bug"
  assert_success
  assert_output $'{"name":"bug"}\n200'

  run script_function github_api POST "/labels" '{"name":"A1","color":"0E8A16","description":"Worker 1"}'
  assert_success
  assert_output $'{}\n201'

  steps_run "assert" "${mocks}"
}

@test "countdown" {
  sleep_mock="$(mock_command "sleep")"

  run script_function countdown 2
  assert_success
  assert_output_contains "Processing will start in 2 seconds. Press Ctrl+C to abort"
  assert_output_contains "Processing will start in 1 seconds. Press Ctrl+C to abort"
  assert_equal "2" "$(mock_get_call_num "${sleep_mock}")"
  assert_equal "1" "$(mock_get_call_args "${sleep_mock}" 1)"
}
