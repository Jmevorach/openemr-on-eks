#!/usr/bin/env bash
# Run openemr_dr Python tests with coverage, ruff, mypy, and bandit (pinned deps).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/ci/run-python-ci.sh" openemr_dr "$@"
