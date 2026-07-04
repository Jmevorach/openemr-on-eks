"""Application data restore via Kubernetes Job."""

from __future__ import annotations

import re
import subprocess
import tempfile
from pathlib import Path

from openemr_dr import config
from openemr_dr.aws import rds as rds_ops
from openemr_dr.common import log
from openemr_dr.common.paths import DATA_RESTORE_JOB, DATA_RESTORE_SCRIPT, TERRAFORM_DIR
from openemr_dr.common.shell import run as run_cmd
from openemr_dr.errors import DrError, PhaseError
from openemr_dr.models.restore import RestoreContext

JOB_WAIT_SECONDS = 600


def _apply_configmap(ctx: RestoreContext) -> None:
    cm_yaml = run_cmd(
        [
            "kubectl",
            "create",
            "configmap",
            "openemr-data-restore-script",
            f"--from-file=data-restore.sh={DATA_RESTORE_SCRIPT}",
            "-n",
            ctx.namespace,
            "--dry-run=client",
            "-o",
            "yaml",
        ],
        capture=True,
    )
    subprocess.run(["kubectl", "apply", "-f", "-"], input=cm_yaml.stdout, text=True, check=True)


def run(ctx: RestoreContext) -> None:
    app_key = ctx.resolve_app_data_key()
    ts_match = re.search(r"app-data-backup-(\d{8}-\d{6})", app_key)
    timestamp = ts_match.group(1) if ts_match else ""

    openemr_version = config.DEFAULT_OPENEMR_VERSION
    try:
        import json

        raw = run_cmd(["terraform", "output", "-json", "openemr_app_config"], cwd=str(TERRAFORM_DIR), capture=True)
        openemr_version = json.loads(raw.stdout or "{}").get("value", {}).get("version", openemr_version)
    except (json.JSONDecodeError, DrError, KeyError, TypeError):
        log.warning(f"Using default OpenEMR version: {openemr_version}")

    db_endpoint, db_pass = rds_ops.resolve_db_credentials(ctx.aws_region)
    if ctx.dry_run:
        log.info(f"[dry-run] Would restore {app_key} via Job openemr-data-restore")
        return

    log.step("Restoring application data via Kubernetes Job")
    _apply_configmap(ctx)
    run_cmd(
        ["kubectl", "delete", "job", "openemr-data-restore", "-n", ctx.namespace, "--ignore-not-found", "--wait=true"],
        check=False,
    )

    template = DATA_RESTORE_JOB.read_text(encoding="utf-8")
    subs = {
        "${NAMESPACE}": ctx.namespace,
        "${OPENEMR_VERSION}": openemr_version,
        "${AWS_REGION}": ctx.aws_region,
        "${BACKUP_BUCKET}": ctx.backup_bucket,
        "${APP_DATA_KEY}": app_key,
        "${TIMESTAMP}": timestamp,
        "${DB_ENDPOINT}": db_endpoint,
        "${DB_USER}": "openemr",
        "${DB_PASS}": db_pass,
        "${DB_NAME}": "openemr",
        "${MEMORY_REQUEST}": "1Gi",
        "${CPU_REQUEST}": "500m",
        "${MEMORY_LIMIT}": "2Gi",
        "${CPU_LIMIT}": "1000m",
    }
    for needle, value in subs.items():
        template = template.replace(needle, value)

    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp:
        tmp.write(template)
        job_path = tmp.name

    try:
        run_cmd(["kubectl", "apply", "-f", job_path])
        wait = run_cmd(
            [
                "kubectl",
                "wait",
                "--for=condition=complete",
                "job/openemr-data-restore",
                "-n",
                ctx.namespace,
                f"--timeout={JOB_WAIT_SECONDS}s",
            ],
            check=False,
        )
        if wait.returncode != 0:
            run_cmd(["kubectl", "logs", "job/openemr-data-restore", "-n", ctx.namespace], check=False)
            raise PhaseError("data", "data-restore Job did not complete")
    finally:
        Path(job_path).unlink(missing_ok=True)

    log.success("Application data restored")
