"""Restore phase registry."""

from __future__ import annotations

from collections.abc import Callable

from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore import bash_bridge
from openemr_dr.restore.phases import bootstrap, data, deploy, preflight, rds, verify

NATIVE: dict[str, Callable[[RestoreContext], None]] = {
    "preflight": preflight.run,
    "bootstrap": bootstrap.run,
    "rds": rds.run,
    "data": data.run,
    "deploy": deploy.run,
    "verify": verify.run,
}

BASH_BRIDGE = frozenset({"legacy"})


def run_phase(name: str, ctx: RestoreContext) -> None:
    if name in NATIVE:
        NATIVE[name](ctx)
    elif name in BASH_BRIDGE:
        bash_bridge.run_bash_phase(name, ctx)
    else:
        raise ValueError(f"Unknown phase: {name}")
