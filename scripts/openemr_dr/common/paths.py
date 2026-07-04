"""Project path helpers."""

from __future__ import annotations

from pathlib import Path

_PKG = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = _PKG.parent
PROJECT_ROOT = SCRIPTS_DIR.parent
TERRAFORM_DIR = PROJECT_ROOT / "terraform"
K8S_DIR = PROJECT_ROOT / "k8s"
RESTORE_SH = SCRIPTS_DIR / "restore.sh"
BACKUP_SH = SCRIPTS_DIR / "backup.sh"
E2E_SH = SCRIPTS_DIR / "test-end-to-end-backup-restore.sh"
RESTORE_BOOTSTRAP_SH = K8S_DIR / "restore-bootstrap.sh"
DATA_RESTORE_JOB = K8S_DIR / "jobs" / "data-restore-job.yaml"
DATA_RESTORE_SCRIPT = K8S_DIR / "jobs" / "data-restore-script.sh"
