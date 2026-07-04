#!/usr/bin/env bash
# Verify Warp pinned versions from versions.yaml install and import correctly.
#
# Usage: ./scripts/test-warp-pinned-versions.sh
#
set -euo pipefail

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is required but not found. Install: https://github.com/mikefarah/yq" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WARP_DIR="${SCRIPT_DIR}/../warp"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# shellcheck source=lib/versions-yq.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/versions-yq.sh"
versions_yq_init "${SCRIPT_DIR}" || exit 1

echo "Warp pinned version compatibility test"
echo "======================================"

"${SCRIPT_DIR}/validate-python-requirements.sh" warp

VENV="${WARP_DIR}/.test-venv"
rm -rf "${VENV}"
"${SCRIPT_DIR}/install-python-dev.sh" warp --venv "${VENV}"
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

PYMYSQL_VERSION="$(read_version '.python_packages.pymysql.current')"
BOTO3_VERSION="$(read_version '.python_packages.boto3.current')"
PYTEST_VERSION="$(read_version '.python_packages.pytest.current')"
PYTEST_COV_VERSION="$(read_version '.python_packages.pytest_cov.current')"
FLAKE8_VERSION="$(read_version '.python_packages.flake8.current')"
BLACK_VERSION="$(read_version '.python_packages.black.current')"
MYPY_VERSION="$(read_version '.python_packages.mypy.current')"

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
check_pip PyMySQL "${PYMYSQL_VERSION}" || FAILED=1
check_pip boto3 "${BOTO3_VERSION}" || FAILED=1
check_pip pytest "${PYTEST_VERSION}" || FAILED=1
check_pip pytest-cov "${PYTEST_COV_VERSION}" || FAILED=1
check_pip flake8 "${FLAKE8_VERSION}" || FAILED=1
check_pip black "${BLACK_VERSION}" || FAILED=1
check_pip mypy "${MYPY_VERSION}" || FAILED=1

if [[ ${FAILED} -ne 0 ]]; then
  exit 1
fi

python -c "
import pymysql
import boto3
from warp.core.omop_to_ccda import OMOPToCCDAConverter
from warp.core.db_importer import OpenEMRDBImporter
from warp.core.uploader import Uploader
from warp.core.credential_discovery import CredentialDiscovery
print('All Warp imports successful')
"

python -c "
from warp.core.omop_to_ccda import OMOPToCCDAConverter
import tempfile
import os

temp_dir = tempfile.mkdtemp()
try:
    converter = OMOPToCCDAConverter(data_source=temp_dir)
    assert converter._map_gender(8507) == 'M'
    assert converter._map_gender(8532) == 'F'
finally:
    os.rmdir(temp_dir)
print('Basic Warp functionality OK')
"

echo -e "${GREEN}Warp pinned versions are compatible.${NC}"
