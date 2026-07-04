#!/usr/bin/env bash
# Verify openemr_dr dev toolchain pins from versions.yaml install and import correctly.
#
# Usage: ./scripts/test-openemr-dr-pinned-versions.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=lib/versions-yq.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/versions-yq.sh"
versions_yq_init "${SCRIPT_DIR}" || exit 1

echo "OpenEMR DR pinned version compatibility test"
echo "============================================="

"${SCRIPT_DIR}/validate-python-requirements.sh" openemr_dr

VENV="${SCRIPT_DIR}/.venv-openemr-dr-test"
rm -rf "${VENV}"
"${SCRIPT_DIR}/install-python-dev.sh" openemr_dr --venv "${VENV}"
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

PYTEST_VERSION="$(read_version '.python_packages.pytest.current')"
PYTEST_COV_VERSION="$(read_version '.python_packages.pytest_cov.current')"
RUFF_VERSION="$(read_version '.python_packages.ruff.current')"
MYPY_VERSION="$(read_version '.python_packages.mypy.current')"
BANDIT_VERSION="$(read_version '.pre_commit_hooks.bandit.current')"

check_pip() {
  local pip_name="$1"
  local expected="$2"
  local actual
  actual=$(python -m pip show "${pip_name}" 2>/dev/null | awk '/^Version:/{print $2}')
  if [[ "${actual}" != "${expected}" ]]; then
    echo -e "${RED}✗${NC} ${pip_name}: ${actual:-MISSING} (expected ${expected})"
    return 1
  fi
  echo -e "${GREEN}✓${NC} ${pip_name}: ${actual}"
}

FAILED=0
check_pip pytest "${PYTEST_VERSION}" || FAILED=1
check_pip pytest-cov "${PYTEST_COV_VERSION}" || FAILED=1
check_pip ruff "${RUFF_VERSION}" || FAILED=1
check_pip mypy "${MYPY_VERSION}" || FAILED=1
check_pip bandit "${BANDIT_VERSION}" || FAILED=1

python -c "import pytest, ruff, mypy, bandit" || FAILED=1

export PYTHONPATH="${SCRIPT_DIR}"
if ! python -m ruff check "${SCRIPT_DIR}/openemr_dr" >/dev/null; then
  echo -e "${RED}✗${NC} ruff check failed on openemr_dr"
  FAILED=1
else
  echo -e "${GREEN}✓${NC} ruff check passed"
fi

if [[ ${FAILED} -ne 0 ]]; then
  echo -e "${RED}Pinned version test failed${NC}"
  exit 1
fi

echo -e "${GREEN}All openemr_dr pinned versions verified${NC}"
