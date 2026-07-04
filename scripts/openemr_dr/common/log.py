"""Simple structured logging to stdout."""

from __future__ import annotations

import sys
from enum import StrEnum


class Level(StrEnum):
    INFO = "INFO"
    OK = "OK"
    WARN = "WARN"
    ERROR = "ERROR"
    STEP = "STEP"


def _emit(level: Level, msg: str) -> None:
    print(f"[{level.value}] {msg}", file=sys.stderr if level == Level.ERROR else sys.stdout, flush=True)


def info(msg: str) -> None:
    _emit(Level.INFO, msg)


def success(msg: str) -> None:
    _emit(Level.OK, msg)


def warning(msg: str) -> None:
    _emit(Level.WARN, msg)


def error(msg: str) -> None:
    _emit(Level.ERROR, msg)


def step(msg: str) -> None:
    _emit(Level.STEP, msg)
