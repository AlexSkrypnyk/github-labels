#!/usr/bin/env bash
#
# Helpers related to common testing functionality.
#
# Run with "--verbose-run" to see debug output.
#
# shellcheck disable=SC2034

################################################################################
#                       BATS HOOK IMPLEMENTATIONS                              #
################################################################################

setup() {
  export BATS_LIB_PATH="${BATS_TEST_DIRNAME}/node_modules"

  bats_load_library bats-helpers

  mock_setup

  # shellcheck disable=SC2155
  export ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  export SCRIPT_FILE="${ROOT_DIR}/github-labels.sh"

  # Plain output, so assertions do not depend on colour escape sequences.
  export TERM=dumb

  export GITHUB_PROCESSING_DELAY=0

  unset GITHUB_REPO GITHUB_TOKEN GITHUB_DELETE_EXISTING_LABELS DEBUG

  TEST_REPO="myorg/myrepo"
  TEST_TOKEN="ghp_test_token"
}

################################################################################
#                               HELPERS                                        #
################################################################################

# Runs a function from the script in a separate shell.
#
# Arguments:
#   1. Function name.
#   2+. Function arguments.
script_function() {
  bash -c 'source "${1}"; shift; "$@"' bash "${SCRIPT_FILE}" "$@"
}

# Prints the labels the script provides: name, color and description per row.
provided_labels() {
  bash -c 'source "${1}"; printf "%s\n" "${labels[@]}"' bash "${SCRIPT_FILE}"
}

# Prints the JSON payload the script sends for a label.
label_payload() {
  printf '{"name":"%s","color":"%s","description":"%s"}' "${1}" "${2}" "${3}"
}

# Prints a step that mocks 1 GitHub API call made through 'curl'.
#
# Arguments:
#   1. HTTP method.
#   2. Endpoint relative to the repository URL.
#   3. HTTP status code returned by the API.
#   4. Response body. Optional.
#   5. Request body. Optional.
step_api() {
  local data=""

  if [ -n "${5-}" ]; then
    data=" --data ${5}"
  fi

  printf '@curl -s -u %s:x-oauth-basic -H Accept: application/vnd.github+json -w \\n%%{http_code} --request %s%s https://api.github.com/repos/%s%s # 0 # %s\\n%s' "${TEST_TOKEN}" "${1}" "${data}" "${TEST_REPO}" "${2}" "${4-}" "${3}"
}

# Prints a step that mocks the repository access check.
#
# Arguments:
#   1. HTTP status code. Optional, defaults to 200.
step_access() {
  step_api GET "/labels?per_page=1" "${1:-200}" "[]"
}

# Prints a step that mocks 1 page of the existing labels list.
#
# Arguments:
#   1. Page number.
#   2. Response body.
#   3. HTTP status code. Optional, defaults to 200.
step_list() {
  step_api GET "/labels?per_page=100&page=${1}" "${3:-200}" "${2}"
}

# Prints the JSON list of labels with the given names.
#
# Arguments:
#   1+. Label names.
labels_json() {
  local json=""
  local name

  for name in "$@"; do
    json="${json},{\"id\":1,\"name\":\"${name}\",\"color\":\"ffffff\",\"default\":false}"
  done

  printf '[%s]' "${json#,}"
}

# Appends steps for processing every provided label to the STEPS array.
#
# Every label is created with a 201 response unless an override is given.
#
# Arguments:
#   1+. Overrides as "NAME|ACTION|HTTP_STATUS|EXISTING_NAME", where ACTION is
#       'create' or 'update' and EXISTING_NAME is the name the update targets.
steps_labels() {
  local -a provided=()
  mapfile -t provided < <(provided_labels)

  local i name color description override action http existing message
  for ((i = 0; i < ${#provided[@]}; i += 3)); do
    name="${provided[i]}"
    color="${provided[i + 1]}"
    description="${provided[i + 2]}"

    action="create"
    http="201"
    existing=""

    for override in "$@"; do
      if [ "${override%%|*}" = "${name}" ]; then
        IFS='|' read -r _ action http existing <<<"${override}"
      fi
    done

    STEPS+=("Processing label \"${name}\"")

    if [ "${action}" = "update" ]; then
      STEPS+=("$(step_api PATCH "/labels/${existing// /%20}" "${http}" "{}" "$(label_payload "${name}" "${color}" "${description}")")")
      message="UPDATED label \"${name}\""
      [ "${http}" != "200" ] && message="Unable to UPDATE label \"${name}\""
    else
      STEPS+=("$(step_api POST "/labels" "${http}" "{}" "$(label_payload "${name}" "${color}" "${description}")")")
      message="CREATED label \"${name}\""
      [ "${http}" != "201" ] && message="Unable to CREATE label \"${name}\""
    fi

    STEPS+=("${message}")
  done
}
