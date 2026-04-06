"""Structured error tracing for Jac CLI and runtime surfaces.

This module provides a small, bounded tracing facility focused on failures.
It is intentionally separate from LLM telemetry and is designed for debugging:
- capture a stable structured event for each error
- keep a bounded in-memory store for recent failures
- optionally emit JSON lines to stderr and/or a file sink
"""

import from typing { Any }

"""Runtime settings for structured error tracing."""
obj ErrorTraceSettings {
    has enabled: bool = False,
        emit_stderr: bool = False,
        store_limit: int = 1000,
        file_path: str = "";
}

"""Single structured error trace event."""
obj ErrorTraceEvent {
    has error_id: str = "",
        trace_id: str = "",
        request_id: str | None = None,
        timestamp: str = "",
        surface: str = "",
        phase: str = "",
        module: str = "",
        command: str = "",
        target: str = "",
        caller_name: str = "",
        username: str | None = None,
        error_type: str = "",
        message: str = "",
        stack_trace: str = "",
        context: dict[str, Any] = {},
        frames: list[dict[str, Any]] = [],
        call_path: list[dict[str, Any]] = [],
        call_tree: dict[str, Any] = {},
        call_graph: dict[str, Any] = {},
        root_entry: str = "",
        entry_frame_index: int | None = None,
        error_frame_index: int | None = None;

    def to_dict -> dict[str, Any];
}

"""Bounded in-memory store for recent error trace events."""
obj ErrorTraceStore {
    has max_events: int = 1000,
        _lock: Any = None,
        _events: Any = None;

    def postinit -> None;
    def add(event: ErrorTraceEvent) -> None;
    def get(error_id: str) -> dict[str, Any] | None;
    def list(limit: int = 50, offset: int = 0) -> dict[str, Any];
    def clear -> None;
}

"""Configure structured error tracing for the current process."""
def configure_error_tracing(
    enabled: bool = False,
    emit_stderr: bool = False,
    file_path: str = "",
    store_limit: int = 1000
) -> None;

"""Return the current error tracing settings."""
def get_error_trace_settings -> ErrorTraceSettings;

"""Return the global in-memory error trace store."""
def get_error_trace_store -> ErrorTraceStore;

"""Return whether structured error tracing is currently enabled."""
def is_error_tracing_enabled -> bool;

"""Capture a structured error trace event and emit it to configured sinks.

Returns the event when tracing is enabled, otherwise None.
"""
def capture_error_trace(
    surface: str,
    phase: str,
    exc: Exception | None = None,
    message: str = "",
    stack_trace: str = "",
    module: str = "",
    command: str = "",
    target: str = "",
    caller_name: str = "",
    username: str | None = None,
    request_id: str | None = None,
    trace_id: str | None = None,
    context: dict[str, Any] | None = None
) -> ErrorTraceEvent | None;
