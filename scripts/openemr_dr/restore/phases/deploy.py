"""OpenEMR deployment phase."""

from __future__ import annotations

from openemr_dr.common import log
from openemr_dr.common.paths import PROJECT_ROOT
from openemr_dr.common.shell import run as run_cmd
from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.phases import verify as verify_phase


def run(ctx: RestoreContext) -> None:
    if ctx.dry_run:
        log.info("[dry-run] Would run restore-defaults.sh and deploy.sh")
        return

    log.step("Deploying OpenEMR")
    defaults = run_cmd(
        ["bash", str(PROJECT_ROOT / "scripts" / "restore-defaults.sh"), "--force"],
        cwd=str(PROJECT_ROOT),
        check=False,
    )
    if defaults.returncode != 0:
        raise PhaseError("deploy", "restore-defaults.sh failed")

    efs_ready = run_cmd(
        ["bash", str(PROJECT_ROOT / "scripts" / "ensure-efs-csi-ready.sh")],
        cwd=str(PROJECT_ROOT),
        check=False,
    )
    if efs_ready.returncode != 0:
        raise PhaseError("deploy", "ensure-efs-csi-ready.sh failed")

    deploy = run_cmd(["bash", str(PROJECT_ROOT / "k8s" / "deploy.sh")], cwd=str(PROJECT_ROOT), check=False)
    if deploy.returncode != 0:
        raise PhaseError("deploy", "deploy.sh failed")

    verify_phase.prepare_single_replica(ctx)
    verify_phase.cleanup_crypto_keys(ctx)
    log.success("OpenEMR deployment complete")
