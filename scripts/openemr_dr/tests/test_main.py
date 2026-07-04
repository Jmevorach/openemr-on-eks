"""Tests for __main__ entrypoint."""

from __future__ import annotations

import runpy
from unittest.mock import patch

import pytest


def test_main_module_entry() -> None:
    with patch("openemr_dr.cli.main", return_value=0):
        with pytest.raises(SystemExit) as exc_info:
            runpy.run_module("openemr_dr", run_name="__main__")
        assert exc_info.value.code == 0
