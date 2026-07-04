"""KMS key recovery for encrypted RDS snapshots."""

from __future__ import annotations

from openemr_dr.common import log
from openemr_dr.common.shell import run, run_json
from openemr_dr.errors import DrError


def _describe_key(region: str, key_id: str) -> tuple[str, bool]:
    data = run_json(["aws", "kms", "describe-key", "--region", region, "--key-id", key_id], retries=2)
    meta = data.get("KeyMetadata") or {}
    state = str(meta.get("KeyState") or "")
    enabled = bool(meta.get("Enabled"))
    return state, enabled


def recover_snapshot_kms_key(region: str, snapshot_id: str) -> None:
    """Ensure the snapshot's KMS key is usable (cancel pending deletion, enable if disabled)."""
    log.step("Checking snapshot KMS key")
    snap = run_json(
        [
            "aws",
            "rds",
            "describe-db-cluster-snapshots",
            "--region",
            region,
            "--db-cluster-snapshot-identifier",
            snapshot_id,
        ],
        retries=3,
    )
    snaps = snap.get("DBClusterSnapshots") or []
    if not snaps:
        raise DrError(f"Snapshot not found: {snapshot_id}")
    kms_key = snaps[0].get("KmsKeyId")
    if not kms_key or kms_key == "None":
        log.info("Snapshot is not KMS-encrypted")
        return

    key_state, enabled = _describe_key(region, str(kms_key))
    log.info(f"KMS key {kms_key}: state={key_state}, enabled={enabled}")

    if key_state == "PendingDeletion":
        log.warning("KMS key pending deletion — canceling")
        run(["aws", "kms", "cancel-key-deletion", "--region", region, "--key-id", str(kms_key)], retries=2)
        key_state, enabled = _describe_key(region, str(kms_key))

    if not enabled:
        log.warning("KMS key disabled — enabling")
        run(["aws", "kms", "enable-key", "--region", region, "--key-id", str(kms_key)], retries=2)
        key_state, enabled = _describe_key(region, str(kms_key))

    if not enabled:
        raise DrError(f"KMS key not enabled after recovery: {kms_key}")
    if key_state in {"PendingDeletion", "PendingImport", "Unavailable"}:
        raise DrError(f"KMS key unusable: state={key_state}")
    log.success("KMS key is available")
