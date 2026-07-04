#!/usr/bin/env bash
# Verify credential rotation pinned versions install and import correctly.
#
# Usage: ./scripts/test-credential-rotation-pinned-versions.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="${SCRIPT_DIR}/../tools/credential-rotation"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# shellcheck source=lib/versions-yq.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/versions-yq.sh"
versions_yq_init "${SCRIPT_DIR}" || exit 1

echo "Credential rotation pinned version compatibility test"
echo "====================================================="

"${SCRIPT_DIR}/validate-python-requirements.sh" credential_rotation

VENV="${TOOL_DIR}/.test-venv"
rm -rf "${VENV}"
"${SCRIPT_DIR}/install-python-dev.sh" credential_rotation --venv "${VENV}"
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

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
check_pip PyMySQL "$(read_version '.python_packages.pymysql.current')" || FAILED=1
check_pip boto3 "$(read_version '.python_packages.boto3.current')" || FAILED=1
check_pip requests "$(read_version '.python_packages.requests.current')" || FAILED=1
check_pip kubernetes "$(read_version '.python_packages.kubernetes.current')" || FAILED=1
check_pip pytest "$(read_version '.python_packages.pytest.current')" || FAILED=1

if [[ ${FAILED} -ne 0 ]]; then
  exit 1
fi

cd "${TOOL_DIR}"
PYTHONPATH=src python -c "
from credential_rotation.cli import main
from credential_rotation.rotate import RotationOrchestrator
from credential_rotation.secrets_manager import SecretsManagerSlots
print('Credential rotation imports successful')
"

echo -e "${GREEN}Credential rotation pinned versions are compatible.${NC}"
