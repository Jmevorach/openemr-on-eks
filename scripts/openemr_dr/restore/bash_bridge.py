"""Bridge to bash restore.sh for phases not yet fully ported to Python."""

from __future__ import annotations

from openemr_dr.common.log import step
from openemr_dr.common.paths import PROJECT_ROOT, RESTORE_SH
from openemr_dr.common.shell import run
from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext


def run_bash_phase(phase: str, ctx: RestoreContext) -> None:
    """Execute a single restore phase via restore.sh (RESTORE_INTERNAL=1)."""
    step(f"Running phase via bash bridge: {phase}")
    env = {
        "RESTORE_INTERNAL": "1",
        "EXECUTE_PHASE": phase,
        "BACKUP_BUCKET": ctx.backup_bucket,
        "SNAPSHOT_ID": ctx.snapshot_id,
        "APP_DATA_KEY": ctx.app_data_key,
        "AWS_REGION": ctx.aws_region,
        "NAMESPACE": ctx.namespace,
        "CLUSTER_NAME": ctx.cluster_name,
        "METADATA_URI": ctx.metadata_uri,
        "USE_AWS_BACKUP": "true" if ctx.use_aws_backup else "false",
        "LEGACY_ORDER": "true" if ctx.legacy_order else "false",
    }
    result = run(
        ["bash", str(RESTORE_SH), ctx.backup_bucket, ctx.snapshot_id, "--region", ctx.aws_region, "--bash-only"],
        cwd=str(PROJECT_ROOT),
        env=env,
        check=False,
        retries=1,
    )
    if result.returncode != 0:
        raise PhaseError(phase, f"bash bridge exited {result.returncode}")
