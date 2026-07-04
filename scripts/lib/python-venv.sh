#!/usr/bin/env bash
# Virtualenv helpers for Python CI/dev (source, do not execute).
# shellcheck shell=bash

python_venv_path_for_project() {
  local project="$1"
  local scripts_dir="$2"
  case "${project}" in
    openemr_dr) printf '%s' "${scripts_dir}/.venv-openemr-dr" ;;
    warp) printf '%s' "${scripts_dir}/../warp/.venv" ;;
    credential_rotation) printf '%s' "${scripts_dir}/../tools/credential-rotation/.venv" ;;
    *)
      echo "ERROR: Unknown Python project: ${project}" >&2
      return 1
      ;;
  esac
}

python_venv_activate() {
  local venv_path="$1"
  if [[ ! -d "${venv_path}" ]]; then
    python3 -m venv "${venv_path}"
  fi
  # shellcheck disable=SC1091
  source "${venv_path}/bin/activate"
  python -m pip install --quiet --upgrade pip
}
