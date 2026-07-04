"""Backup orchestration (delegates AWS operations to backup.sh until fully ported)."""

from __future__ import annotations

import argparse
import os

from openemr_dr.common import log
from openemr_dr.common.paths import BACKUP_SH, PROJECT_ROOT
from openemr_dr.common.shell import run


def run_backup_cli(args: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="openemr_dr backup")
    parser.add_argument("--cluster-name", default=os.environ.get("CLUSTER_NAME", "openemr-eks"))
    parser.add_argument("--source-region", default=os.environ.get("AWS_REGION", "us-west-2"))
    parser.add_argument("--backup-region", default="")
    parser.add_argument("--namespace", default=os.environ.get("NAMESPACE", "openemr"))
    parser.add_argument("--strategy", default=os.environ.get("BACKUP_STRATEGY", "same-region"))
    parser.add_argument("--bash-only", action="store_true", help="Force bash backup.sh")
    ns, passthrough = parser.parse_known_args(args)

    if ns.bash_only or os.environ.get("BACKUP_BASH_ONLY") == "1":
        return _run_bash_backup(ns, passthrough)

    log.step("Backup via Python driver → backup.sh (AWS operations)")
    return _run_bash_backup(ns, passthrough)


def _run_bash_backup(ns: argparse.Namespace, passthrough: list[str]) -> int:
    cmd = ["bash", str(BACKUP_SH)]
    if ns.cluster_name:
        cmd.extend(["--cluster-name", ns.cluster_name])
    if ns.source_region:
        cmd.extend(["--source-region", ns.source_region])
    if ns.backup_region:
        cmd.extend(["--backup-region", ns.backup_region])
    if ns.namespace:
        cmd.extend(["--namespace", ns.namespace])
    if ns.strategy:
        cmd.extend(["--strategy", ns.strategy])
    cmd.extend(passthrough)
    log.info(f"Running: {' '.join(cmd)}")
    result = run(cmd, cwd=str(PROJECT_ROOT), check=False, retries=1)
    return result.returncode
