"""Structured error tracing implementations."""

import json;
import logging;
import os;
import sys;
import threading;
import traceback;
import uuid;
import from collections { OrderedDict }
import from datetime { UTC, datetime }
import from pathlib { Path }
import from typing { Any }

glob logger = logging.getLogger(__name__),
     _error_trace_settings: Any = None,
     _error_trace_store: ErrorTraceStore | None = None;

glob _SENSITIVE_KEYS = {
         "authorization",
         "cookie",
         "password",
         "secret",
         "token",
         "api_key",
         "apikey",
         "access_token",
         "refresh_token"
     };

"""Mask likely secret values and trim payload size."""
def _sanitize_value(value: Any, depth: int = 0) -> Any {
    if depth > 4 {
        return "[max-depth]";
    }
    if isinstance(value, dict) {
        result: dict[str, Any] = {};
        for key in value {
            lowered = str(key).lower();
            if lowered in _SENSITIVE_KEYS {
                result[str(key)] = "[redacted]";
            } else {
                result[str(key)] = _sanitize_value(value[key], depth + 1);
            }
        }
        return result;
    }
    if isinstance(value, list) {
        return [_sanitize_value(item, depth + 1) for item in value[:20]];
    }
    if isinstance(value, tuple) {
        return tuple(_sanitize_value(item, depth + 1) for item in value[:20]);
    }
    if isinstance(value, str) {
        return value[:4000];
    }
    if isinstance(value, (int, float, bool)) or value is None {
        return value;
    }
    return str(value)[:4000];
}

"""Append one event as JSONL if a file sink is configured."""
def _append_jsonl(path_str: str, event: ErrorTraceEvent) -> None {
    if not path_str {
        return;
    }
    try {
        path = Path(path_str).expanduser();
        if path.parent and not path.parent.exists() {
            path.parent.mkdir(parents=True, exist_ok=True);
        }
        with open(path, "a", encoding="utf-8") as f {
            f.write(json.dumps(event.to_dict(), ensure_ascii=False) + "\n");
        }
    } except Exception as e {
        logger.debug(f"Failed to write error trace JSONL: {e}");
    }
}

impl ErrorTraceEvent.to_dict -> dict[str, Any] {
    return {
        "error_id": self.error_id,
        "trace_id": self.trace_id,
        "request_id": self.request_id,
        "timestamp": self.timestamp,
        "surface": self.surface,
        "phase": self.phase,
        "module": self.module,
        "command": self.command,
        "target": self.target,
        "caller_name": self.caller_name,
        "username": self.username,
        "error_type": self.error_type,
        "message": self.message,
        "stack_trace": self.stack_trace,
        "context": self.context
    };
}

impl ErrorTraceStore.postinit -> None {
    self._lock = threading.Lock();
    self._events = OrderedDict();
}

impl ErrorTraceStore.add(event: ErrorTraceEvent) -> None {
    with self._lock {
        self._events[event.error_id] = event;
        while len(self._events) > self.max_events {
            self._events.popitem(last=False);
        }
    }
}

impl ErrorTraceStore.get(error_id: str) -> dict[str, Any] | None {
    with self._lock {
        event = self._events.get(error_id);
        return event.to_dict() if event else None;
    }
}

impl ErrorTraceStore.list(limit: int = 50, offset: int = 0) -> dict[str, Any] {
    with self._lock {
        items = list(reversed(self._events.values()));
        total = len(items);
        page = items[offset:offset + limit];
        return {
            "events": [event.to_dict() for event in page],
            "total": total,
            "has_more": (offset + limit) < total
        };
    }
}

impl ErrorTraceStore.clear -> None {
    with self._lock {
        self._events.clear();
    }
}

"""Lazily initialize settings to avoid bootstrap ordering issues."""
def _settings -> ErrorTraceSettings {
    global _error_trace_settings;
    if _error_trace_settings is None {
        _error_trace_settings = ErrorTraceSettings();
    }
    return _error_trace_settings;
}

impl configure_error_tracing(
    enabled: bool = False,
    emit_stderr: bool = False,
    file_path: str = "",
    store_limit: int = 1000
) -> None {
    global _error_trace_store;
    settings = _settings();
    env_file = os.environ.get("JAC_ERROR_TRACE_FILE", "");
    settings.enabled = enabled;
    settings.emit_stderr = emit_stderr;
    settings.store_limit = int(store_limit) if int(store_limit) > 0 else 1000;
    settings.file_path = file_path or env_file;
    if enabled {
        if _error_trace_store is None {
            _error_trace_store = ErrorTraceStore(max_events=settings.store_limit);
        } else {
            _error_trace_store.max_events = settings.store_limit;
        }
    }
}

impl get_error_trace_settings -> ErrorTraceSettings {
    return _settings();
}

impl get_error_trace_store -> ErrorTraceStore {
    global _error_trace_store;
    if _error_trace_store is None {
        _error_trace_store = ErrorTraceStore(max_events=_settings().store_limit);
    }
    return _error_trace_store;
}

impl is_error_tracing_enabled -> bool {
    return _settings().enabled;
}

impl capture_error_trace(
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
) -> ErrorTraceEvent | None {
    settings = _settings();
    if not settings.enabled {
        return None;
    }
    err_id = str(uuid.uuid4());
    effective_trace_id = trace_id or err_id;
    stack = stack_trace;
    if not stack and exc {
        stack = traceback.format_exc();
        if not stack or stack.strip() == "NoneType: None" {
            stack = "".join(
                traceback.format_exception(type(exc), exc, exc.__traceback__)
            );
        }
    }
    event = ErrorTraceEvent(
        error_id=err_id,
        trace_id=effective_trace_id,
        request_id=request_id,
        timestamp=datetime.now(UTC).isoformat(),
        surface=surface,
        phase=phase,
        module=module,
        command=command,
        target=target,
        caller_name=caller_name,
        username=username,
        error_type=type(exc).__name__ if exc else "Error",
        message=(message or str(exc or ""))[:2000],
        stack_trace=stack[:20000],
        context=_sanitize_value(context or {})
    );
    store = get_error_trace_store();
    store.add(event);
    if settings.emit_stderr {
        try {
            print(json.dumps(event.to_dict(), ensure_ascii=False), file=sys.stderr);
        } except Exception as e {
            logger.debug(f"Failed to emit error trace to stderr: {e}");
        }
    }
    _append_jsonl(settings.file_path, event);
    return event;
