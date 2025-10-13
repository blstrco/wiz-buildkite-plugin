#!/usr/bin/env bash

set -euo pipefail

# Show a prompt for a command
function plugin_prompt() {
  if [[ -z "${HIDE_PROMPT:-}" ]] ; then
    echo -ne '\033[90m$\033[0m' >&2
    for arg in "${@}" ; do
      if [[ $arg =~ [[:space:]] ]] ; then
        echo -n " '$arg'" >&2
      else
        echo -n " $arg" >&2
      fi
    done
    echo >&2
  fi
}

# Shorthand for reading env config
function plugin_read_config() {
  local var="BUILDKITE_PLUGIN_WIZ_${1}"
  local default="${2:-}"
  echo "${!var:-$default}"
}

# Reads either a value or a list from plugin config
function plugin_read_list() {
  prefix_read_list "BUILDKITE_PLUGIN_WIZ_$1"
}

# Reads either a value or a list from the given env prefix
function prefix_read_list() {
  local prefix="$1"
  local parameter="${prefix}_0"

  if [[ -n "${!parameter:-}" ]]; then
    local i=0
    local parameter="${prefix}_${i}"
    while [[ -n "${!parameter:-}" ]]; do
      echo "${!parameter}"
      i=$((i+1))
      parameter="${prefix}_${i}"
    done
  elif [[ -n "${!prefix:-}" ]]; then
    echo "${!prefix}"
  fi
}

# Reads either a value or a list from plugin config into a global result array
# Returns success if values were read
function plugin_read_list_into_result() {
  local prefix="$1"
  local parameter="${prefix}_0"
  result=()

  if [[ -n "${!parameter:-}" ]]; then
    local i=0
    local parameter="${prefix}_${i}"
    while [[ -n "${!parameter:-}" ]]; do
      result+=("${!parameter}")
      i=$((i+1))
      parameter="${prefix}_${i}"
    done
  elif [[ -n "${!prefix:-}" ]]; then
    result+=("${!prefix}")
  fi

  [[ ${#result[@]} -gt 0 ]] || return 1
}

function plugin_config_exists() {
  local var="BUILDKITE_PLUGIN_WIZ_${1}"

  # Check if the variable is set
  [ "${!var+is_set}" != "" ]
}

function in_array() {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

# retry <number-of-retries> <command>
function retry {
  local retries=$1; shift
  local attempts=1
  local status=0

  until "$@"; do
    status=$?
    echo "Exited with $status"
    if (( retries == "0" )); then
      return $status
    elif (( attempts == retries )); then
      echo "Failed $attempts retries"
      return $status
    else
      echo "Retrying $((retries - attempts)) more times..."
      attempts=$((attempts + 1))
      sleep $(((attempts - 2) * 2))
    fi
  done
}

