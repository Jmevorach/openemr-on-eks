#!/usr/bin/env python3
"""CLI helper: print restore plan JSON from metadata URI."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from metadata import RestorePlan, load_metadata  # noqa: E402


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: load_plan.py <metadata-uri> [region]", file=sys.stderr)
        return 1
    uri = sys.argv[1]
    region = sys.argv[2] if len(sys.argv) > 2 else "us-west-2"
    plan: RestorePlan = load_metadata(uri, region)
    print(
        json.dumps(
            {
                "backup_bucket": plan.backup_bucket,
                "snapshot_id": plan.snapshot_id,
                "app_data_key": plan.app_data_key,
                "openemr_version": plan.openemr_version,
                "backup_strategy": plan.backup_strategy,
                "backup_region": plan.backup_region,
                "kms_key_id": plan.kms_key_id,
                "manifest_version": plan.manifest_version,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
