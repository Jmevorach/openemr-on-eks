#!/usr/bin/env bash
# Install pinned Python dev dependencies for a project profile (reads versions.yaml).
#
# Usage:
#   ./scripts/install-python-dev.sh openemr_dr [--venv PATH]
#   ./scripts/install-python-dev.sh warp [--venv PATH]
#   ./scripts/install-python-dev.sh credential_rotation [--venv PATH]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-}"
VENV_OVERRIDE=""

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      VENV_OVERRIDE="${2:?--venv requires a path}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${PROJECT}" ]]; then
  echo "Usage: $0 {openemr_dr|warp|credential_rotation} [--venv PATH]" >&2
  exit 1
fi

# shellcheck source=lib/versions-yq.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/versions-yq.sh"
# shellcheck source=lib/python-venv.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/python-venv.sh"

versions_yq_init "${SCRIPT_DIR}" || exit 1

VENV_PATH="${VENV_OVERRIDE:-$(python_venv_path_for_project "${PROJECT}" "${SCRIPT_DIR}")}"
python_venv_activate "${VENV_PATH}"

case "${PROJECT}" in
  openemr_dr)
    REQ_FILE="${SCRIPT_DIR}/requirements/openemr-dr-dev.txt"
    python -m pip install --quiet -r "${REQ_FILE}"
    ;;
  warp)
    python -m pip install --quiet -r "${SCRIPT_DIR}/requirements/warp-dev.txt"
    python -m pip install --quiet -r "${SCRIPT_DIR}/../warp/requirements.txt"
    python -m pip install --quiet -e "${SCRIPT_DIR}/../warp"
    ;;
  credential_rotation)
    python -m pip install --quiet -r "${SCRIPT_DIR}/../tools/credential-rotation/requirements.txt"
    python -m pip install --quiet -r "${SCRIPT_DIR}/requirements/credential-rotation-dev.txt"
    ;;
  *)
    echo "ERROR: Unknown project: ${PROJECT}" >&2
    exit 1
    ;;
esac

echo "Installed Python dev dependencies for ${PROJECT} in ${VENV_PATH}"
