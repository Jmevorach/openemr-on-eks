"""Kubernetes bootstrap for restore."""

from __future__ import annotations

from openemr_dr.common import log
from openemr_dr.common.paths import PROJECT_ROOT, RESTORE_BOOTSTRAP_SH
from openemr_dr.common.shell import run as run_cmd
from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext


def run(ctx: RestoreContext) -> None:
    if ctx.dry_run:
        log.info(f"[dry-run] Would run {RESTORE_BOOTSTRAP_SH}")
        return
    log.step("Bootstrapping Kubernetes for restore")
    env = {
        "NAMESPACE": ctx.namespace,
        "AWS_REGION": ctx.aws_region,
        "CLUSTER_NAME": ctx.cluster_name,
    }
    result = run_cmd(["bash", str(RESTORE_BOOTSTRAP_SH)], cwd=str(PROJECT_ROOT), env=env, check=False)
    if result.returncode != 0:
        raise PhaseError("bootstrap", "restore-bootstrap.sh failed")
    log.success("Kubernetes bootstrap complete")
