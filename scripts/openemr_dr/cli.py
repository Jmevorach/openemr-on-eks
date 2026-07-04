"""CLI entrypoints for openemr_dr."""

from __future__ import annotations

import sys

from openemr_dr.backup.orchestrator import run_backup_cli
from openemr_dr.e2e.runner import run_e2e_cli
from openemr_dr.restore.orchestrator import run_restore_cli


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print("Usage: python -m openemr_dr {restore|backup|e2e} [options]")
        print("  restore  — phased backup restore (Python orchestrator)")
        print("  backup   — backup driver (→ backup.sh until fully ported)")
        print("  e2e      — end-to-end test driver")
        return 0 if args else 1

    cmd, rest = args[0], args[1:]
    if cmd == "restore":
        return run_restore_cli(rest)
    if cmd == "backup":
        return run_backup_cli(rest)
    if cmd == "e2e":
        return run_e2e_cli(rest)
    print(f"Unknown command: {cmd}", file=sys.stderr)
    return 1
