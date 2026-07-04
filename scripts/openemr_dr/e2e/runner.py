"""E2E test step runner (Python driver; delegates unported steps to bash)."""

from __future__ import annotations

import argparse
import subprocess
from dataclasses import dataclass

from openemr_dr.common import log
from openemr_dr.common.paths import E2E_SH, PROJECT_ROOT


@dataclass(frozen=True)
class E2EStep:
    number: int
    name: str
    native_python: bool = False  # True when step logic lives in openemr_dr


E2E_STEPS: tuple[E2EStep, ...] = (
    E2EStep(1, "Deploy infrastructure"),
    E2EStep(2, "Deploy OpenEMR"),
    E2EStep(3, "Deploy test data"),
    E2EStep(4, "Backup installation"),
    E2EStep(5, "Test monitoring stack"),
    E2EStep(6, "Delete infrastructure"),
    E2EStep(7, "Recreate infrastructure"),
    E2EStep(8, "Restore from backup", native_python=False),  # uses openemr_dr restore via restore.sh
    E2EStep(9, "Verify restoration"),
    E2EStep(10, "Final cleanup"),
)

STEP_GROUPS: dict[str, tuple[int, int, str]] = {
    "full": (1, 10, ""),
    "deploy": (1, 3, ""),
    "backup": (4, 4, ""),
    "monitoring": (5, 5, ""),
    "destroy": (6, 6, ""),
    "recreate": (7, 7, ""),
    "restore": (8, 9, ""),
    "cleanup": (10, 10, ""),
    "backup-restore": (4, 9, ""),
    "backup-restore-inplace": (4, 9, "5 6 7"),
}


def _should_run(step: int, from_step: int, to_step: int, skip_steps: set[int]) -> bool:
    return from_step <= step <= to_step and step not in skip_steps


def _run_bash_e2e(extra_args: list[str]) -> int:
    cmd = ["bash", str(E2E_SH), *extra_args]
    log.info(f"Delegating to bash E2E: {' '.join(cmd)}")
    return subprocess.call(cmd, cwd=str(PROJECT_ROOT))


def run_e2e_cli(args: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="openemr_dr e2e")
    parser.add_argument("--group", choices=list(STEP_GROUPS.keys()))
    parser.add_argument("--from-step", type=int, default=1)
    parser.add_argument("--to-step", type=int, default=10)
    parser.add_argument("--step", type=int)
    parser.add_argument("--list-steps", action="store_true")
    parser.add_argument("--list-groups", action="store_true")
    parser.add_argument("--state-file", default=".e2e-test-state")
    parser.add_argument("--cluster-name", default="openemr-eks-test")
    parser.add_argument("--aws-region", default="us-west-2")
    parser.add_argument("--skip-restore-defaults", action="store_true")
    parser.add_argument("--skip-orphan-check", action="store_true")
    parser.add_argument("--no-emergency-cleanup", action="store_true")
    ns, passthrough = parser.parse_known_args(args)

    if ns.list_steps:
        for s in E2E_STEPS:
            flag = " [python-ready]" if s.native_python else ""
            print(f"  Step {s.number}: {s.name}{flag}")
        return 0

    if ns.list_groups:
        for name, (f, t, skip_str) in STEP_GROUPS.items():
            extra = f" (skip {skip_str})" if skip_str else ""
            print(f"  {name}: steps {f}-{t}{extra}")
        return 0

    from_step, to_step = ns.from_step, ns.to_step
    skip_steps: set[int] = set()
    if ns.group:
        from_step, to_step, skip_str = STEP_GROUPS[ns.group]
        skip_steps = {int(x) for x in skip_str.split() if x.strip()}
    if ns.step:
        from_step = to_step = ns.step

    bash_args = [
        "--from-step",
        str(from_step),
        "--to-step",
        str(to_step),
        "--state-file",
        ns.state_file,
        "--cluster-name",
        ns.cluster_name,
        "--aws-region",
        ns.aws_region,
    ]
    if ns.skip_restore_defaults:
        bash_args.append("--skip-restore-defaults")
    if ns.skip_orphan_check:
        bash_args.append("--skip-orphan-check")
    if ns.no_emergency_cleanup:
        bash_args.append("--no-emergency-cleanup")
    bash_args.extend(passthrough)

    log.step(f"E2E runner: steps {from_step}-{to_step} (Python driver → bash implementation)")
    for s in E2E_STEPS:
        if _should_run(s.number, from_step, to_step, skip_steps):
            log.info(f"  Step {s.number}: {s.name}")

    return _run_bash_e2e(bash_args)
