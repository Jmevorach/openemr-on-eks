"""Metadata loader tests."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.backup.metadata import load_metadata


def test_load_metadata_s3() -> None:
    with patch("openemr_dr.backup.metadata.subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=0)
        with patch("openemr_dr.backup.metadata.load_from_path") as mock_load:
            mock_load.return_value = MagicMock()
            load_metadata("s3://bucket/metadata/file.json", "us-west-2")
            mock_run.assert_called_once()


def test_load_metadata_s3_failure() -> None:
    with patch("openemr_dr.backup.metadata.subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=1, stderr="fail")
        with pytest.raises(RuntimeError):
            load_metadata("s3://bucket/metadata/file.json", "us-west-2")


def test_load_metadata_bucket_key() -> None:
    with patch("openemr_dr.backup.metadata.subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=0)
        with patch("openemr_dr.backup.metadata.load_from_path") as mock_load:
            mock_load.return_value = MagicMock()
            load_metadata("bucket/key/file.json", "us-west-2")


def test_load_metadata_invalid_ref() -> None:
    with pytest.raises(ValueError):
        load_metadata("invalid", "us-west-2")
