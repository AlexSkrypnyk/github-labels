#!/usr/bin/env bash
##
# Update project labels in GitHub.
#
# @usage:
# Interactive prompt:
# ./github-labels.sh
#
# Silent, if $GITHUB_TOKEN is set in an environment and a repository is
# provided as an argument or in $GITHUB_REPO:
# GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg/myrepo
# GITHUB_TOKEN=ghp_123 GITHUB_REPO=myorg/myrepo ./github-labels.sh

set -eu
[ "${DEBUG-}" = "1" ] && set -x

# GitHub repository as "org/name" to perform operations on. Falls back to the
# first script argument.
GITHUB_REPO="${GITHUB_REPO:-}"

# GitHub token to perform operations.
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Delete existing labels to mirror the list below.
GITHUB_DELETE_EXISTING_LABELS="${GITHUB_DELETE_EXISTING_LABELS:-1}"

# Seconds to wait before processing starts, giving a chance to abort.
GITHUB_PROCESSING_DELAY="${GITHUB_PROCESSING_DELAY:-3}"

# Number of labels requested per page when listing existing labels.
GITHUB_LABELS_PER_PAGE=100

# ------------------------------------------------------------------------------

# @formatter:off
note() { printf "       %s\n" "${1}"; }
info() { [ "${TERM:-}" != "dumb" ] && tput colors >/dev/null 2>&1 && printf "\033[34m[INFO] %s\033[0m\n" "${1}" || printf "[INFO] %s\n" "${1}"; }
pass() { [ "${TERM:-}" != "dumb" ] && tput colors >/dev/null 2>&1 && printf "\033[32m[ OK ] %s\033[0m\n" "${1}" || printf "[ OK ] %s\n" "${1}"; }
fail() { [ "${TERM:-}" != "dumb" ] && tput colors >/dev/null 2>&1 && printf "\033[31m[FAIL] %s\033[0m\n" "${1}" || printf "[FAIL] %s\n" "${1}"; }
# @formatter:on

# Array of labels to create. If DELETE_EXISTING_LABELS=1, the labels list will
# be exactly as below, otherwise labels below will be added to existing ones.
labels=(
  "BLOCKED" "D93F0B" "Issue or pull request is blocked"
  "AUTOMERGE" "934BF4" "Pull request has been approved and set to automerge"
  "CONFLICT" "bc143e" "Pull request has a conflict that needs to be resolved before it can be merged"
  "Dependencies" "62E795" "Pull request was raised automatically by a dependency bot"
  "DO NOT MERGE" "d93f0b" "Do not merge this pull request"
  "Do not review" "d93f0b" "Do not review this pull request"
  "Needs review" "5319e7" "Pull request needs a review from assigned developers"
  "Ready for test" "0e8a16" "Pull request is ready for manual testing"
  "Ready to be merged" "c2e0c6" "Pull request is ready to be merged (assigned after testing is complete)"
  "Requires more work" "b60205" "Pull request was reviewed and reviver(s) asked to work further on the pull request"
  "URGENT" "d93f0b" "Pull request needs to be urgently reviewed"
  "UPSTREAM" "fbca04" "Issue or pull request is related to an upstream project"
  "A1" "0E8A16" "Worker 1"
  "A2" "0E8A16" "Worker 2"
  "A3" "0E8A16" "Worker 3"
  "A4" "0E8A16" "Worker 4"

  # Uncomment default Github labels below to preserve them.
  # "bug"                 "d73a4a"  "Something isn't working"
  # "duplicate"           "cfd3d7"  "This issue or pull request already exists"
  # "enhancement"         "a2eeef"  "New feature or request"
  # "help wanted"         "008672"  "Extra attention is needed"
  # "good first issue"    "7057ff"  "Good for newcomers"
  # "invalid"             "e4e669"  "This doesn't seem right"
  # "question"            "d876e3"  "Further information is requested"
  # "wontfix"             "ffffff"  "This will not be worked on"
)

# Names of the labels that exist in the repository, populated by main().
existing_labels=()

# ------------------------------------------------------------------------------

main() {
  GITHUB_REPO="${GITHUB_REPO:-${1:-}}"

  for cmd in curl; do
    if ! command -v "${cmd}" >/dev/null; then
      fail "Command ${cmd} is not available"
      exit 1
    fi
  done

  info "Processing GitHub labels."

  echo
  if [ "${GITHUB_DELETE_EXISTING_LABELS}" = "1" ]; then
    echo "  This script will remove the default GitHub labels."
  else
    echo "  This script will not remove the default GitHub labels."
  fi
  echo "  This script will create new labels."
  echo "  A personal access token is required to access private repositories."
  echo

  if [ "${GITHUB_REPO}" = "" ]; then
    echo ''
    echo -n 'Enter GitHub Org/Repo (e.g. myorg/myrepo): '
    read -r GITHUB_REPO || true
  fi

  if [ "${GITHUB_REPO}" = "" ]; then
    fail "GitHub repository name is required"
    exit 1
  fi

  if ! [[ ${GITHUB_REPO} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    fail "GitHub repository must be in the format \"org/repo\""
    exit 1
  fi

  if [ "${GITHUB_TOKEN}" = "" ]; then
    echo ''
    echo -n 'GitHub Personal Access Token: '
    read -r -s GITHUB_TOKEN || true
  fi

  if [ "${GITHUB_TOKEN}" = "" ]; then
    fail "GitHub token is required"
    exit 1
  fi

  if ! user_has_access; then
    fail "User does not have access to specified repository. Please check your credentials"
    exit 1
  fi

  echo
  note "Starting label processing"
  echo

  countdown "${GITHUB_PROCESSING_DELAY}"
  echo

  note "Checking existing labels"
  local existing_labels_list

  if ! existing_labels_list="$(label_all)"; then
    fail "Unable to fetch existing labels"
    exit 1
  fi

  existing_labels=()
  if [ -n "${existing_labels_list}" ]; then
    mapfile -t existing_labels <<<"${existing_labels_list}"
  fi

  local errors=0

  if [ "${GITHUB_DELETE_EXISTING_LABELS}" = "1" ]; then
    for existing_label_name in "${existing_labels[@]}"; do
      if is_provided_label "${existing_label_name}"; then
        continue
      fi

      echo "    Removing label \"${existing_label_name}\" as it is not in the provided list"
      if label_delete "${existing_label_name}"; then
        echo "    DELETED label \"${existing_label_name}\""
      else
        echo "    Unable to DELETE label \"${existing_label_name}\""
        errors=$((errors + 1))
      fi
    done
  fi

  local i name color description existing_name
  for ((i = 0; i < ${#labels[@]}; i += 3)); do
    name="${labels[i]}"
    color="${labels[i + 1]}"
    description="${labels[i + 2]}"

    note "Processing label \"${name}\""

    if existing_name="$(find_existing_label "${name}")"; then
      if label_update "${existing_name}" "${name}" "${color}" "${description}"; then
        echo "    UPDATED label \"${name}\""
      else
        echo "    Unable to UPDATE label \"${name}\""
        errors=$((errors + 1))
      fi
    else
      if label_create "${name}" "${color}" "${description}"; then
        echo "    CREATED label \"${name}\""
      else
        echo "    Unable to CREATE label \"${name}\""
        errors=$((errors + 1))
      fi
    fi
  done

  echo

  if [ "${errors}" -gt 0 ]; then
    fail "Label processing completed with ${errors} error(s)"
    exit 1
  fi

  pass "Label processing complete"
  echo
}

# GitHub label names are case-insensitive, so all name comparisons are too.
is_provided_label() {
  local label="${1,,}"
  local i

  for ((i = 0; i < ${#labels[@]}; i += 3)); do
    if [ "${label}" = "${labels[i],,}" ]; then
      return 0
    fi
  done

  return 1
}

find_existing_label() {
  local label="${1,,}"
  local existing

  for existing in "${existing_labels[@]}"; do
    if [ "${label}" = "${existing,,}" ]; then
      printf '%s' "${existing}"
      return 0
    fi
  done

  return 1
}

user_has_access() {
  local response
  response="$(github_api GET "/labels?per_page=1")" || true

  [ "$(api_status "${response}")" = "200" ]
}

label_all() {
  local page=1
  local response
  local page_labels=()

  while true; do
    response="$(github_api GET "/labels?per_page=${GITHUB_LABELS_PER_PAGE}&page=${page}")" || true

    if [ "$(api_status "${response}")" != "200" ]; then
      return 1
    fi

    page_labels=()
    mapfile -t page_labels < <(json_names "$(api_body "${response}")")

    if [ "${#page_labels[@]}" -gt 0 ]; then
      printf '%s\n' "${page_labels[@]}"
    fi

    if [ "${#page_labels[@]}" -lt "${GITHUB_LABELS_PER_PAGE}" ]; then
      break
    fi

    page=$((page + 1))
  done
}

label_create() {
  local name="${1}"
  local color="${2}"
  local description="${3}"
  local response
  response="$(github_api POST "/labels" "$(label_payload "${name}" "${color}" "${description}")")" || true

  [ "$(api_status "${response}")" = "201" ]
}

label_update() {
  local existing_name="${1}"
  local name="${2}"
  local color="${3}"
  local description="${4}"
  local response
  response="$(github_api PATCH "/labels/$(uriencode "${existing_name}")" "$(label_payload "${name}" "${color}" "${description}")")" || true

  [ "$(api_status "${response}")" = "200" ]
}

label_delete() {
  local name="${1}"
  local response
  response="$(github_api DELETE "/labels/$(uriencode "${name}")")" || true

  [ "$(api_status "${response}")" = "204" ]
}

label_payload() {
  printf '{"name":"%s","color":"%s","description":"%s"}' "$(json_escape "${1}")" "$(json_escape "${2}")" "$(json_escape "${3}")"
}

# Prints the response body followed by the HTTP status code on the last line.
github_api() {
  local method="${1}"
  local endpoint="${2}"
  local data="${3:-}"

  local args=(-s -u "${GITHUB_TOKEN}:x-oauth-basic" -H "Accept: application/vnd.github+json" -w '\n%{http_code}' --request "${method}")

  if [ -n "${data}" ]; then
    args+=(--data "${data}")
  fi

  curl "${args[@]}" "https://api.github.com/repos/${GITHUB_REPO}${endpoint}"
}

api_status() {
  printf '%s' "${1##*$'\n'}"
}

api_body() {
  if [[ ${1} != *$'\n'* ]]; then
    return 0
  fi

  printf '%s' "${1%$'\n'*}"
}

# Label objects have no nested "name" keys, so every "name" value in the
# response is a label name.
json_names() {
  printf '%s' "${1}" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/^"name"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

json_escape() {
  local s="${1}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

uriencode() {
  local s
  s="${1//'%'/%25}"
  s="${s//' '/%20}"
  s="${s//'"'/%22}"
  s="${s//'#'/%23}"
  s="${s//'$'/%24}"
  s="${s//'&'/%26}"
  s="${s//'+'/%2B}"
  s="${s//','/%2C}"
  s="${s//'/'/%2F}"
  s="${s//':'/%3A}"
  s="${s//';'/%3B}"
  s="${s//'='/%3D}"
  s="${s//'?'/%3F}"
  s="${s//'@'/%40}"
  s="${s//'['/%5B}"
  s="${s//']'/%5D}"
  printf %s "${s}"
}

countdown() {
  local seconds="${1}"

  while [ "${seconds}" -gt 0 ]; do
    echo -ne "Processing will start in ${seconds} seconds. Press Ctrl+C to abort\033[0K\r"
    sleep 1
    seconds=$((seconds - 1))
  done

  echo
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
