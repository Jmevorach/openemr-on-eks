"""Restore checkpoint persistence."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from openemr_dr.models.restore import PHASES

if TYPE_CHECKING:
    from openemr_dr.models.restore import RestoreContext


@dataclass
class RestoreState:
    completed_phase: str = ""
    backup_bucket: str = ""
    snapshot_id: str = ""
    app_data_key: str = ""
    metadata_uri: str = ""
    aws_region: str = "us-west-2"
    use_aws_backup: bool = False
    legacy_order: bool = False
    _state_file: str = ".restore-state"

    @property
    def path(self) -> Path:
        return Path(self._state_file)

    def set_path(self, state_file: str) -> None:
        self._state_file = state_file

    def load(self, state_file: str | None = None) -> None:
        if state_file:
            self._state_file = state_file
        if not self.path.exists():
            return
        values: dict[str, str] = {}
        for line in self.path.read_text(encoding="utf-8").splitlines():
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip().strip("'\"")
        self.completed_phase = values.get("COMPLETED_PHASE", "")
        self.backup_bucket = values.get("BACKUP_BUCKET", self.backup_bucket)
        self.snapshot_id = values.get("SNAPSHOT_ID", self.snapshot_id)
        self.app_data_key = values.get("APP_DATA_KEY", self.app_data_key)
        self.metadata_uri = values.get("METADATA_URI", self.metadata_uri)
        self.aws_region = values.get("AWS_REGION", self.aws_region)
        self.use_aws_backup = values.get("USE_AWS_BACKUP", "false") == "true"
        self.legacy_order = values.get("LEGACY_ORDER", "false") == "true"

    def save(self) -> None:
        lines = [
            f"COMPLETED_PHASE={self.completed_phase}",
            f"BACKUP_BUCKET={self.backup_bucket}",
            f"SNAPSHOT_ID={self.snapshot_id}",
            f"APP_DATA_KEY={self.app_data_key}",
            f"METADATA_URI={self.metadata_uri}",
            f"AWS_REGION={self.aws_region}",
            f"USE_AWS_BACKUP={'true' if self.use_aws_backup else 'false'}",
            f"LEGACY_ORDER={'true' if self.legacy_order else 'false'}",
        ]
        self.path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def mark_complete(self, phase: str) -> None:
        self.completed_phase = phase
        self.save()

    def should_run(self, phase: str, from_phase: str | None) -> bool:
        if phase not in PHASES:
            return True
        if from_phase:
            start = PHASES.index(from_phase) if from_phase in PHASES else 0
            return PHASES.index(phase) >= start
        if not self.completed_phase or self.completed_phase not in PHASES:
            return True
        return PHASES.index(phase) > PHASES.index(self.completed_phase)

    def sync_from_context(self, ctx: RestoreContext) -> None:
        self.backup_bucket = ctx.backup_bucket
        self.snapshot_id = ctx.snapshot_id
        self.app_data_key = ctx.app_data_key
        self.metadata_uri = ctx.metadata_uri
        self.aws_region = ctx.aws_region
        self.use_aws_backup = ctx.use_aws_backup
        self.legacy_order = ctx.legacy_order
