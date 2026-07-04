"""Subprocess helpers with retries."""

from __future__ import annotations

import json
import os
import subprocess
import time
from typing import Any

from openemr_dr.common.paths import TERRAFORM_DIR
from openemr_dr.errors import DrError


def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    cwd: str | None = None,
    env: dict[str, str] | None = None,
    retries: int = 1,
    retry_delay: float = 5.0,
) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    merged["AWS_PAGER"] = ""
    merged["AWS_CLI_AUTO_PROMPT"] = "off"
    if env:
        merged.update(env)

    last: subprocess.CompletedProcess[str] | None = None
    for attempt in range(1, retries + 1):
        last = subprocess.run(
            cmd,
            cwd=cwd,
            env=merged,
            text=True,
            capture_output=capture,
            check=False,
        )
        if last.returncode == 0:
            return last
        if attempt < retries:
            time.sleep(retry_delay)
    if last is None:
        raise DrError(f"Command failed with no result: {' '.join(cmd)}")
    if check:
        err = (last.stderr or last.stdout or "").strip()
        raise DrError(f"Command failed ({last.returncode}): {' '.join(cmd)}\n{err}")
    return last


def run_json(cmd: list[str], **kwargs: Any) -> Any:
    result = run([*cmd, "--output", "json"], capture=True, **kwargs)
    return json.loads(result.stdout or "null")


def terraform_output(name: str, *, raw: bool = True) -> str:
    cmd = ["terraform", "output"]
    if raw:
        cmd.append("-raw")
    cmd.append(name)
    result = run(cmd, cwd=str(TERRAFORM_DIR), capture=True, retries=3)
    return (result.stdout or "").strip().strip("%").strip()
