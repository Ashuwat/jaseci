"""Tests for structured error tracing."""

import asyncio;
import from types { SimpleNamespace }
import from jaclang.runtimelib.error_trace {
    capture_error_trace,
    configure_error_tracing,
    get_error_trace_store
}
import from jaclang.runtimelib.server { ExecutionManager }

test "capture_error_trace stores structured event and redacts secrets" {
    store = get_error_trace_store();
    store.clear();
    configure_error_tracing(enabled=True, emit_stderr=False, store_limit=10);

    event = capture_error_trace(
        surface="cli",
        phase="command",
        message="boom",
        command="run",
        target="main.jac",
        context={
            "password": "super-secret",
            "nested": {"token": "abc123"},
            "safe": "value"
        }
    );

    assert event is not None;
    detail = store.get(event.error_id);
    assert detail is not None;
    assert detail["message"] == "boom";
    assert detail["context"]["password"] == "[redacted]";
    assert detail["context"]["nested"]["token"] == "[redacted]";
    assert detail["context"]["safe"] == "value";
}

test "capture_error_trace is disabled by default" {
    configure_error_tracing(enabled=False, emit_stderr=False);
    event = capture_error_trace(surface="cli", phase="command", message="no-op");
    assert event is None;
}

test "execution manager returns traced ids for early runtime errors" {
    store = get_error_trace_store();
    store.clear();
    configure_error_tracing(enabled=True, emit_stderr=False, store_limit=10);

    dummy_user_mgr = SimpleNamespace(get_root_id=lambda username : None);
    mgr = ExecutionManager(base_path=".", user_manager=dummy_user_mgr);

    def sample() -> str {
        return "ok";
    }

    result = asyncio.run(
        mgr.execute_function(
            sample, {}, "ghost", {"request_id": "req-1", "trace_id": "trace-1"}
        )
    );

    assert result["error"] == "User not found";
    assert result["trace_id"] == "trace-1";
    assert result["request_id"] == "req-1";
    assert "error_id" in result;
}
