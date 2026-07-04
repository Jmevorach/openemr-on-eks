"""RDS restore phase."""

from __future__ import annotations

from openemr_dr.aws import rds as rds_ops
from openemr_dr.common import log
from openemr_dr.common.shell import terraform_output
from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext


def run(ctx: RestoreContext) -> None:
    cluster_id = terraform_output("aurora_cluster_id")
    if not cluster_id:
        raise PhaseError("rds", "Could not resolve aurora_cluster_id from Terraform")

    if ctx.dry_run:
        mode = "AWS Backup" if ctx.use_aws_backup else "snapshot"
        log.info(f"[dry-run] Would restore RDS ({mode}): {cluster_id} ← {ctx.snapshot_id}")
        return

    log.step("Restoring RDS cluster")
    try:
        if ctx.use_aws_backup:
            rds_ops.restore_via_aws_backup(ctx.aws_region, cluster_id, ctx.snapshot_id)
        else:
            rds_ops.restore_cluster_from_snapshot(
                ctx.aws_region,
                cluster_id,
                ctx.snapshot_id,
                custom_kms_key=ctx.custom_kms_key,
            )
    except Exception as exc:
        raise PhaseError("rds", str(exc)) from exc
