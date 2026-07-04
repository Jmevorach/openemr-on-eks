"""Restore orchestration."""

from __future__ import annotations

from openemr_dr.aws import rds as rds_ops
from openemr_dr.backup.metadata import load_metadata
from openemr_dr.common import log
from openemr_dr.common.shell import terraform_output
from openemr_dr.errors import DrError
from openemr_dr.models.restore import PHASES, RestoreContext
from openemr_dr.models.state import RestoreState
from openemr_dr.restore.phases import run_phase


def _invalidate_stale_rds_checkpoint(state: RestoreState, ctx: RestoreContext) -> None:
    """Re-run RDS when checkpoint says later phases completed but the cluster is gone."""
    if not state.completed_phase or state.completed_phase not in PHASES:
        return
    if PHASES.index(state.completed_phase) < PHASES.index("rds"):
        return
    cluster_id = terraform_output("aurora_cluster_id")
    if not cluster_id or rds_ops._cluster_exists(ctx.aws_region, cluster_id):
        return
    log.warning(
        f"Checkpoint shows '{state.completed_phase}' complete but RDS cluster "
        f"{cluster_id} is missing — rerunning from rds phase"
    )
    state.completed_phase = "bootstrap"
    state.save()


def _phase_sequence(ctx: RestoreContext) -> list[str]:
    if ctx.legacy_order:
        return ["preflight", "legacy", "verify"]
    return list(PHASES)


def run_restore(
    ctx: RestoreContext,
    *,
    from_phase: str | None = None,
    state_file: str = ".restore-state",
    single_phase: str | None = None,
) -> None:
    state = RestoreState()
    state.set_path(state_file)
    state.load(state_file)
    state.sync_from_context(ctx)
    state.save()
    if single_phase is None:
        _invalidate_stale_rds_checkpoint(state, ctx)

    phases = [single_phase] if single_phase else _phase_sequence(ctx)

    for phase in phases:
        if phase is None:
            continue
        if single_phase is None and not state.should_run(phase, from_phase):
            log.info(f"Skipping completed phase: {phase}")
            continue
        log.step(f"=== Phase: {phase} ===")
        run_phase(phase, ctx)
        if phase != "legacy":
            state.mark_complete(phase)

    if not single_phase and state.path.exists():
        state.path.unlink()
    log.success("Restore completed successfully")


def context_from_metadata(metadata_uri: str, region: str) -> RestoreContext:
    plan = load_metadata(metadata_uri, region)
    kms = plan.kms_key_id if plan.kms_key_id not in ("", "auto-detected", "none") else ""
    return RestoreContext(
        backup_bucket=plan.backup_bucket,
        snapshot_id=plan.snapshot_id,
        app_data_key=plan.app_data_key,
        aws_region=plan.backup_region or region,
        metadata_uri=plan.metadata_uri,
        custom_kms_key=kms,
    )


def run_restore_cli(args: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="openemr_dr restore")
    parser.add_argument("backup_bucket", nargs="?")
    parser.add_argument("snapshot_id", nargs="?")
    parser.add_argument("--from-metadata", dest="metadata")
    parser.add_argument("--from-phase", choices=list(PHASES))
    parser.add_argument("--phase", choices=[*list(PHASES), "legacy"])
    parser.add_argument("--state-file", default=".restore-state")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--namespace", default="openemr")
    parser.add_argument("--cluster-name", default="")
    parser.add_argument("--use-aws-backup", action="store_true")
    parser.add_argument("--legacy-order", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--kms-key", dest="kms_key", default="")
    parser.add_argument("--list-phases", action="store_true")
    ns = parser.parse_args(args)

    if ns.list_phases:
        for p in PHASES:
            print(p)
        return 0

    if ns.metadata:
        ctx = context_from_metadata(ns.metadata, ns.region)
    elif ns.backup_bucket and ns.snapshot_id:
        ctx = RestoreContext(
            backup_bucket=ns.backup_bucket,
            snapshot_id=ns.snapshot_id,
            aws_region=ns.region,
            namespace=ns.namespace,
            cluster_name=ns.cluster_name,
            use_aws_backup=ns.use_aws_backup,
            legacy_order=ns.legacy_order,
            dry_run=ns.dry_run,
        )
    else:
        parser.error("Provide backup-bucket and snapshot-id, or --from-metadata")

    ctx.use_aws_backup = ns.use_aws_backup
    ctx.legacy_order = ns.legacy_order
    ctx.dry_run = ns.dry_run
    ctx.custom_kms_key = ns.kms_key

    try:
        run_restore(ctx, from_phase=ns.from_phase, state_file=ns.state_file, single_phase=ns.phase)
    except DrError as exc:
        log.error(str(exc))
        return 1
    return 0
