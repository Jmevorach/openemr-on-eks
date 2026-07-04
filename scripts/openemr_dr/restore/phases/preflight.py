"""Pre-flight validation (native Python)."""

from __future__ import annotations

from openemr_dr.common import log
from openemr_dr.common.paths import TERRAFORM_DIR
from openemr_dr.common.shell import run as run_cmd
from openemr_dr.common.shell import run_json
from openemr_dr.errors import PreflightError
from openemr_dr.models.restore import RestoreContext


def run(ctx: RestoreContext) -> None:
    log.step("Pre-flight validation")
    failed: list[str] = []

    if not (TERRAFORM_DIR / "terraform.tfstate").exists():
        failed.append("Terraform state")
    else:
        log.info("Terraform state present")

    bucket_check = run_cmd(
        ["aws", "s3", "ls", f"s3://{ctx.backup_bucket}/application-data/", "--region", ctx.aws_region],
        capture=True,
        check=False,
        retries=3,
    )
    if bucket_check.returncode != 0:
        failed.append("Backup bucket")
    else:
        log.success(f"Backup bucket accessible: {ctx.backup_bucket}")

    if failed:
        raise PreflightError(failed, "Cannot restore without backup artifacts")

    try:
        snaps = run_json(
            [
                "aws",
                "rds",
                "describe-db-cluster-snapshots",
                "--region",
                ctx.aws_region,
                "--db-cluster-snapshot-identifier",
                ctx.snapshot_id,
            ],
            retries=3,
        )
        status = (snaps.get("DBClusterSnapshots") or [{}])[0].get("Status", "missing")
        if status != "available":
            failed.append("RDS snapshot")
            log.error(f"Snapshot status: {status}")
        else:
            log.success(f"Snapshot available: {ctx.snapshot_id}")
    except Exception:
        failed.append("RDS snapshot")

    if failed:
        raise PreflightError(
            failed,
            "Pre-flight validation failed — snapshot or bucket missing",
        )

    ident = run_cmd(
        ["aws", "sts", "get-caller-identity"],
        capture=True,
        retries=2,
    )
    log.info(f"AWS identity: {(ident.stdout or '').strip()}")
    log.success("Pre-flight validation passed")
