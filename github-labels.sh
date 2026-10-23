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
#
# Every non-archived repository of an organization or a user, after a
# confirmation:
# GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg
# GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg --exclude=myorg/repo1,myorg/repo2
# GITHUB_TOKEN=ghp_123 ./github-labels.sh myorg --yes

set -eu
[ "${DEBUG-}" = "1" ] && set -x

# GitHub repository as "org/name", or an organization or user as "org", to
# perform operations on. Falls back to the first script argument.
GITHUB_REPO="${GITHUB_REPO:-}"

# GitHub token to perform operations.
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Delete existing labels to mirror the list below.
GITHUB_DELETE_EXISTING_LABELS="${GITHUB_DELETE_EXISTING_LABELS:-1}"

# Seconds to wait before processing starts, giving a chance to abort.
GITHUB_PROCESSING_DELAY="${GITHUB_PROCESSING_DELAY:-3}"

# Number of items requested per page when listing labels or repositories.
GITHUB_PER_PAGE=100

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

# Names of the labels that exist in the repository, populated by
# process_labels().
existing_labels=()

# Repositories to process as "org/repo", populated by main() or
# select_owner_repos().
repos=()

# Repositories to skip as "org/repo", populated by parse_excludes().
excluded_repos=()

# ------------------------------------------------------------------------------

main() {
  local target=""
  local exclude=""
  local assume_yes=0
  local arg

  for arg in "$@"; do
    case "${arg}" in
      --exclude=*) exclude="${arg#--exclude=}" ;;
      -y | --yes) assume_yes=1 ;;
      -*)
        fail "Unknown option \"${arg}\""
        exit 1
        ;;
      *)
        if [ -z "${target}" ]; then
          target="${arg}"
        fi
        ;;
    esac
  done

  GITHUB_REPO="${GITHUB_REPO:-${target}}"

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
    echo -n 'Enter GitHub Org/Repo, or Org for all its repositories (e.g. myorg/myrepo or myorg): '
    read -r GITHUB_REPO || true
  fi

  if [ "${GITHUB_REPO}" = "" ]; then
    fail "GitHub repository name is required"
    exit 1
  fi

  if ! is_repo_name "${GITHUB_REPO}" && ! is_owner_name "${GITHUB_REPO}"; then
    fail "GitHub repository must be in the format \"org/repo\" or \"org\""
    exit 1
  fi

  local owner="${GITHUB_REPO%%/*}"
  local bulk=1

  if is_repo_name "${GITHUB_REPO}"; then
    bulk=0
  fi

  if [ "${bulk}" = "0" ] && [ -n "${exclude}" ]; then
    fail "Option --exclude can only be used with an organization, not with a repository"
    exit 1
  fi

  if ! parse_excludes "${owner}" "${exclude}"; then
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

  if [ "${bulk}" = "1" ]; then
    if ! select_owner_repos "${owner}"; then
      exit 1
    fi

    if [ "${assume_yes}" != "1" ] && ! confirm "Update labels in ${#repos[@]} repositories?"; then
      fail "Aborted"
      exit 1
    fi
  else
    if ! user_has_access; then
      fail "User does not have access to specified repository. Please check your credentials"
      exit 1
    fi

    repos=("${GITHUB_REPO}")
  fi

  echo
  note "Starting label processing"
  echo

  countdown "${GITHUB_PROCESSING_DELAY}"
  echo

  local -a failed_repos=()
  local repo

  for repo in "${repos[@]}"; do
    GITHUB_REPO="${repo}"

    if [ "${bulk}" = "1" ]; then
      info "Processing repository \"${repo}\""
    fi

    if ! process_labels; then
      failed_repos+=("${repo}")
    fi
  done

  if [ "${#failed_repos[@]}" -gt 0 ]; then
    if [ "${bulk}" = "1" ]; then
      fail "Label processing failed in ${#failed_repos[@]} of ${#repos[@]} repositories:"

      for repo in "${failed_repos[@]}"; do
        note "${repo}"
      done
    fi

    exit 1
  fi

  pass "Label processing complete"
  echo
}

# Synchronizes the labels of $GITHUB_REPO with the provided list.
process_labels() {
  note "Checking existing labels"
  local existing_labels_list

  if ! existing_labels_list="$(label_all)"; then
    fail "Unable to fetch existing labels"
    return 1
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
    return 1
  fi
}

# Populates repos with the non-archived, non-excluded repositories of an
# organization or a user, and prints them.
select_owner_repos() {
  local owner="${1}"
  local type

  if ! type="$(owner_type "${owner}")"; then
    fail "Unable to find \"${owner}\". Please check the name and your credentials"
    return 1
  fi

  # Private repositories of a user are listed only for the token's own user.
  local path="/user/repos?affiliation=owner"

  if [ "${type}" = "Organization" ]; then
    path="/orgs/${owner}/repos?type=all"
  fi

  local listed

  if ! listed="$(github_paginate "${path}" json_repos)"; then
    fail "Unable to list repositories of \"${owner}\""
    return 1
  fi

  repos=()
  local archived_count=0
  local excluded_count=0
  local name archived name_owner

  while IFS=$'\t' read -r name archived; do
    name_owner="${name%%/*}"

    # The token's user may differ from the owner, so the list can hold
    # repositories of another owner.
    if [ -z "${name}" ] || [ "${name_owner,,}" != "${owner,,}" ]; then
      continue
    fi

    if [ "${archived}" = "true" ]; then
      archived_count=$((archived_count + 1))
    elif is_excluded "${name}"; then
      excluded_count=$((excluded_count + 1))
    else
      repos+=("${name}")
    fi
  done <<<"${listed}"

  if [ "${#repos[@]}" -eq 0 ]; then
    fail "No repositories to process in \"${owner}\""
    return 1
  fi

  echo
  note "Found ${#repos[@]} repositories in \"${owner}\":"

  for name in "${repos[@]}"; do
    note "  ${name}"
  done

  note "Skipped ${archived_count} archived and ${excluded_count} excluded repositories"
  echo
}

# Prints "User" or "Organization" for an account name.
owner_type() {
  local response
  response="$(github_request GET "/users/${1}")" || true

  if [ "$(api_status "${response}")" != "200" ]; then
    return 1
  fi

  local -a types=()
  mapfile -t types < <(json_strings type "$(api_body "${response}")")

  if [ "${#types[@]}" -eq 0 ]; then
    return 1
  fi

  printf '%s' "${types[0]}"
}

# Validates a comma-separated list of "org/repo" entries against the owner and
# stores them in excluded_repos.
parse_excludes() {
  local owner="${1}"
  local -a entries=()
  local entry entry_owner

  IFS=',' read -r -a entries <<<"${2}"
  excluded_repos=()

  for entry in "${entries[@]}"; do
    if [ -z "${entry}" ]; then
      continue
    fi

    if ! is_repo_name "${entry}"; then
      fail "Excluded repository \"${entry}\" must be in the format \"org/repo\""
      return 1
    fi

    entry_owner="${entry%%/*}"

    if [ "${entry_owner,,}" != "${owner,,}" ]; then
      fail "Excluded repository \"${entry}\" does not belong to \"${owner}\""
      return 1
    fi

    excluded_repos+=("${entry}")
  done
}

# GitHub repository names are case-insensitive.
is_excluded() {
  local repo="${1,,}"
  local excluded

  for excluded in "${excluded_repos[@]}"; do
    if [ "${repo}" = "${excluded,,}" ]; then
      return 0
    fi
  done

  return 1
}

is_repo_name() {
  [[ ${1} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
}

is_owner_name() {
  [[ ${1} =~ ^[A-Za-z0-9_.-]+$ ]]
}

# Asks a yes/no question that defaults to "no".
confirm() {
  local answer=""

  echo -n "${1} [y/N] "
  read -r answer || true

  [[ ${answer} =~ ^[Yy]([Ee][Ss])?$ ]]
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
  github_paginate "/repos/${GITHUB_REPO}/labels" json_names
}

# Prints 1 line per item of every page of a list endpoint.
#
# The extractor receives a page body and must print exactly 1 line per item,
# so a short page marks the last one.
github_paginate() {
  local path="${1}"
  local extractor="${2}"
  local separator="?"
  local page=1
  local response
  local page_items=()

  if [[ ${path} == *\?* ]]; then
    separator="&"
  fi

  while true; do
    response="$(github_request GET "${path}${separator}per_page=${GITHUB_PER_PAGE}&page=${page}")" || true

    if [ "$(api_status "${response}")" != "200" ]; then
      return 1
    fi

    page_items=()
    mapfile -t page_items < <("${extractor}" "$(api_body "${response}")")

    if [ "${#page_items[@]}" -gt 0 ]; then
      printf '%s\n' "${page_items[@]}"
    fi

    if [ "${#page_items[@]}" -lt "${GITHUB_PER_PAGE}" ]; then
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

# Sends a request to an endpoint of $GITHUB_REPO.
github_api() {
  github_request "${1}" "/repos/${GITHUB_REPO}${2}" "${3:-}"
}

# Prints the response body followed by the HTTP status code on the last line.
github_request() {
  local method="${1}"
  local path="${2}"
  local data="${3:-}"

  local args=(-s -u "${GITHUB_TOKEN}:x-oauth-basic" -H "Accept: application/vnd.github+json" -w '\n%{http_code}' --request "${method}")

  if [ -n "${data}" ]; then
    args+=(--data "${data}")
  fi

  curl "${args[@]}" "https://api.github.com${path}"
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
  json_strings name "${1}"
}

# Prints every string value of a key, in any object of the JSON document.
json_strings() {
  printf '%s' "${2}" | grep -o "\"${1}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/^\"${1}\"[[:space:]]*:[[:space:]]*\"//; s/\"\$//" || true
}

# Prints "org/repo<TAB>true|false" with the archived flag of every repository
# in a list response.
#
# Each repository object holds exactly 1 "full_name" and 1 "archived" key, with
# "full_name" first, so the keys pair up in document order.
json_repos() {
  local line
  local name=""

  while IFS= read -r line; do
    case "${line}" in
      '"full_name"'*)
        name="${line#*:}"
        name="${name#*\"}"
        name="${name%\"}"
        ;;
      *)
        if [ -n "${name}" ]; then
          printf '%s\t%s\n' "${name}" "${line##*[[:space:]:]}"
        fi

        name=""
        ;;
    esac
  done < <(printf '%s' "${1}" | grep -oE '"(full_name|archived)"[[:space:]]*:[[:space:]]*("[^"]*"|true|false)' || true)
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
