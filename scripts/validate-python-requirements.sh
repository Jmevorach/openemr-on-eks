#!/usr/bin/env bash
# Verify pinned requirements/*.txt and runtime requirement files match versions.yaml.
#
# Usage: ./scripts/validate-python-requirements.sh [openemr_dr|warp|credential_rotation|all]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-all}"

# shellcheck source=lib/versions-yq.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/versions-yq.sh"
versions_yq_init "${SCRIPT_DIR}" || exit 1

check_pin() {
  local file="$1"
  local package="$2"
  local expected="$3"
  local pattern="^${package}=="
  local actual
  actual=$(grep -E "${pattern}" "${file}" | head -1 | sed "s/${package}==//" | tr -d '[:space:]' || true)
  if [[ "${actual}" != "${expected}" ]]; then
    echo "MISMATCH ${file}: ${package} pinned as '${actual:-MISSING}', versions.yaml has '${expected}'" >&2
    return 1
  fi
  echo "OK ${file}: ${package}==${expected}"
}

check_bandit_pin() {
  local file="$1"
  local expected
  expected="$(read_version '.pre_commit_hooks.bandit.current')"
  if ! grep -qE "^bandit\\[toml\\]==${expected}$" "${file}"; then
    echo "MISMATCH ${file}: bandit[toml] expected ${expected}" >&2
    return 1
  fi
  echo "OK ${file}: bandit[toml]==${expected}"
}

check_flake8_toolchain() {
  local file="$1"
  local failed=0
  check_pin "${file}" "pytest" "$(read_version '.python_packages.pytest.current')" || failed=1
  check_pin "${file}" "pytest-cov" "$(read_version '.python_packages.pytest_cov.current')" || failed=1
  check_pin "${file}" "flake8" "$(read_version '.python_packages.flake8.current')" || failed=1
  check_pin "${file}" "black" "$(read_version '.python_packages.black.current')" || failed=1
  check_pin "${file}" "mypy" "$(read_version '.python_packages.mypy.current')" || failed=1
  check_bandit_pin "${file}" || failed=1
  return "${failed}"
}

validate_openemr_dr() {
  local file="${SCRIPT_DIR}/requirements/openemr-dr-dev.txt"
  local failed=0
  check_pin "${file}" "pytest" "$(read_version '.python_packages.pytest.current')" || failed=1
  check_pin "${file}" "pytest-cov" "$(read_version '.python_packages.pytest_cov.current')" || failed=1
  check_pin "${file}" "ruff" "$(read_version '.python_packages.ruff.current')" || failed=1
  check_pin "${file}" "mypy" "$(read_version '.python_packages.mypy.current')" || failed=1
  check_bandit_pin "${file}" || failed=1
  return "${failed}"
}

validate_warp() {
  local failed=0
  check_flake8_toolchain "${SCRIPT_DIR}/requirements/warp-dev.txt" || failed=1
  local runtime="${SCRIPT_DIR}/../warp/requirements.txt"
  check_pin "${runtime}" "pymysql" "$(read_version '.python_packages.pymysql.current')" || failed=1
  check_pin "${runtime}" "boto3" "$(read_version '.python_packages.boto3.current')" || failed=1
  local setup_py="${SCRIPT_DIR}/../warp/setup.py"
  if ! grep -qE "pymysql==$(read_version '.python_packages.pymysql.current')" "${setup_py}"; then
    echo "MISMATCH ${setup_py}: pymysql install_requires does not match versions.yaml" >&2
    failed=1
  else
    echo "OK ${setup_py}: pymysql install_requires matches versions.yaml"
  fi
  if ! grep -qE "boto3==$(read_version '.python_packages.boto3.current')" "${setup_py}"; then
    echo "MISMATCH ${setup_py}: boto3 install_requires does not match versions.yaml" >&2
    failed=1
  else
    echo "OK ${setup_py}: boto3 install_requires matches versions.yaml"
  fi
  return "${failed}"
}

validate_credential_rotation() {
  local failed=0
  check_flake8_toolchain "${SCRIPT_DIR}/requirements/credential-rotation-dev.txt" || failed=1
  local runtime="${SCRIPT_DIR}/../tools/credential-rotation/requirements.txt"
  check_pin "${runtime}" "pymysql" "$(read_version '.python_packages.pymysql.current')" || failed=1
  check_pin "${runtime}" "boto3" "$(read_version '.python_packages.boto3.current')" || failed=1
  check_pin "${runtime}" "requests" "$(read_version '.python_packages.requests.current')" || failed=1
  check_pin "${runtime}" "kubernetes" "$(read_version '.python_packages.kubernetes.current')" || failed=1
  return "${failed}"
}

FAILED=0
case "${TARGET}" in
  openemr_dr) validate_openemr_dr || FAILED=1 ;;
  warp) validate_warp || FAILED=1 ;;
  credential_rotation) validate_credential_rotation || FAILED=1 ;;
  all)
    validate_openemr_dr || FAILED=1
    validate_warp || FAILED=1
    validate_credential_rotation || FAILED=1
    ;;
  *)
    echo "Unknown target: ${TARGET}" >&2
    exit 1
    ;;
esac

if [[ ${FAILED} -ne 0 ]]; then
  echo "Requirements pin validation failed. Update requirements files to match versions.yaml." >&2
  exit 1
fi

echo "All requirement pins match versions.yaml (${TARGET})."
