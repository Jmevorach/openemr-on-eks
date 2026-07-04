#!/usr/bin/env python3
"""
OpenEMR restore orchestrator.

Phased restore with checkpoints, metadata v2 loading, and optional AWS Backup RDS restore.
Delegates phase execution to restore.sh (RESTORE_INTERNAL=1).
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from metadata import load_metadata  # noqa: E402
from state import PHASES, RestoreState  # noqa: E402
PROJECT_ROOT = SCRIPT_DIR.parent.parent
RESTORE_SH = PROJECT_ROOT / "scripts" / "restore.sh"


def _log(msg: str) -> None:
    print(msg, flush=True)


def _run_phase(state: RestoreState, phase: str, extra_env: dict[str, str] | None = None) -> None:
    env = os.environ.copy()
    env["RESTORE_INTERNAL"] = "1"
    env["EXECUTE_PHASE"] = phase
    env["BACKUP_BUCKET"] = state.backup_bucket
    env["SNAPSHOT_ID"] = state.snapshot_id
    env["APP_DATA_KEY"] = state.app_data_key
    env["AWS_REGION"] = state.aws_region
    env["RESTORE_STATE_FILE"] = str(state.path)
    env["METADATA_URI"] = state.metadata_uri
    if state.use_aws_backup:
        env["USE_AWS_BACKUP"] = "true"
    if state.legacy_order:
        env["LEGACY_ORDER"] = "true"
    if extra_env:
        env.update(extra_env)

    _log(f"\n{'=' * 60}\nPhase: {phase}\n{'=' * 60}")
    result = subprocess.run(
        ["bash", str(RESTORE_SH), state.backup_bucket, state.snapshot_id, "--region", state.aws_region],
        env=env,
        cwd=str(PROJECT_ROOT),
    )
    if result.returncode != 0:
        raise SystemExit(result.returncode)
    state.mark_complete(phase)


def _phase_sequence(state: RestoreState) -> list[str]:
    if state.legacy_order:
        return ["preflight", "legacy", "verify"]
    return list(PHASES)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="OpenEMR phased restore orchestrator")
    parser.add_argument("backup_bucket", nargs="?", help="S3 backup bucket")
    parser.add_argument("snapshot_id", nargs="?", help="RDS snapshot identifier")
    parser.add_argument("--from-metadata", dest="metadata", help="s3://bucket/metadata/backup-metadata-....json")
    parser.add_argument("--from-phase", dest="from_phase", choices=list(PHASES), default=None)
    parser.add_argument("--state-file", default=".restore-state")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--use-aws-backup", action="store_true")
    parser.add_argument("--legacy-order", action="store_true", help="Use legacy clean→deploy→RDS→data order")
    parser.add_argument("--list-phases", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.list_phases:
        for phase in PHASES:
            print(phase)
        return 0

    state = RestoreState(aws_region=args.region)
    state.set_path(args.state_file)
    state.load(args.state_file)
    state.use_aws_backup = args.use_aws_backup
    state.legacy_order = args.legacy_order

    if args.metadata:
        plan = load_metadata(args.metadata, args.region)
        state.backup_bucket = plan.backup_bucket
        state.snapshot_id = plan.snapshot_id
        state.app_data_key = plan.app_data_key
        state.metadata_uri = plan.metadata_uri
        state.aws_region = plan.backup_region or args.region
        _log(f"Loaded restore plan from metadata v{plan.manifest_version}")
        _log(f"  Bucket: {state.backup_bucket}")
        _log(f"  Snapshot: {state.snapshot_id}")
        _log(f"  App data: {state.app_data_key}")
    else:
        if not args.backup_bucket or not args.snapshot_id:
            print("Error: provide backup-bucket and snapshot-id, or --from-metadata", file=sys.stderr)
            return 1
        state.backup_bucket = args.backup_bucket
        state.snapshot_id = args.snapshot_id

    state.save()

    for phase in _phase_sequence(state):
        if phase == "legacy":
            env = os.environ.copy()
            env["RESTORE_INTERNAL"] = "1"
            env["LEGACY_ORDER"] = "true"
            result = subprocess.run(
                ["bash", str(RESTORE_SH), state.backup_bucket, state.snapshot_id, "--region", state.aws_region, "--legacy-order"],
                env=env,
                cwd=str(PROJECT_ROOT),
            )
            if result.returncode != 0:
                return result.returncode
            state.mark_complete("deploy")
            continue

        if not state.should_run(phase, args.from_phase):
            _log(f"Skipping phase (already complete): {phase}")
            continue
        try:
            _run_phase(state, phase)
        except SystemExit as exc:
            return int(exc.code) if exc.code is not None else 1

    _log("\nRestore orchestrator completed successfully.")
    if state.path.exists():
        state.path.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
