"""Shared exceptions."""


class DrError(Exception):
    """Base error for disaster-recovery operations."""


class PreflightError(DrError):
    """Pre-flight validation failed."""

    def __init__(self, failed_checks: list[str], message: str = "Pre-flight validation failed") -> None:
        self.failed_checks = failed_checks
        super().__init__(f"{message}: {', '.join(failed_checks)}")


class PhaseError(DrError):
    """A restore or E2E phase failed."""

    def __init__(self, phase: str, message: str) -> None:
        self.phase = phase
        super().__init__(f"Phase '{phase}' failed: {message}")
