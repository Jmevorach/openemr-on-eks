#!/usr/bin/env bash
# Shared helpers for reading versions.yaml (source, do not execute).
# shellcheck shell=bash

versions_yq_require() {
  if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq is required but not found. Install: https://github.com/mikefarah/yq" >&2
    return 1
  fi
}

versions_yq_init() {
  local script_dir="${1:?script_dir required}"
  VERSIONS_YQ_PROJECT_ROOT="$(cd "${script_dir}/.." && pwd)"
  VERSIONS_YQ_FILE="${VERSIONS_YQ_PROJECT_ROOT}/versions.yaml"
  if [[ ! -f "${VERSIONS_YQ_FILE}" ]]; then
    echo "ERROR: versions.yaml not found at ${VERSIONS_YQ_FILE}" >&2
    return 1
  fi
  versions_yq_require || return 1
}

read_version() {
  local path="$1"
  local version
  local yq_output
  local yq_exit_code

  yq_output=$(yq eval "$path" "${VERSIONS_YQ_FILE}" 2>&1)
  yq_exit_code=$?
  if [[ ${yq_exit_code} -ne 0 ]]; then
    echo "ERROR: Failed to read versions.yaml path: ${path}" >&2
    echo "       yq error: ${yq_output}" >&2
    return 1
  fi

  version="${yq_output}"
  if [[ -z "${version}" || "${version}" == "null" ]]; then
    echo "ERROR: Missing version at versions.yaml path: ${path}" >&2
    return 1
  fi
  printf '%s' "${version}"
}

read_python_version() {
  read_version '.semver_packages.python_version.current'
}

normalize_python_version() {
  echo "$1" | awk -F. '{print $1"."$2}'
}
