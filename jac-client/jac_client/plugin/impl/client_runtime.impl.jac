impl __jacJsx(tag: Any, props: dict = {}, children: Any = []) -> JsxElement {
    if tag == None {
        tag = React.Fragment;
    }
    childrenArray = [];
    if children != None {
        if Array.isArray(children) {
            childrenArray = children;
        } else {
            childrenArray = [children];
        }
    }
    reactChildren = [];
    for child in childrenArray {
        if child != None {
            reactChildren.push(child);
        }
    }
    if len(reactChildren) > 0 {
        args = [tag, props];
        for child in reactChildren {
            args.push(child);
        }
        return React.createElement.apply(React, args);
    } else {
        return React.createElement(tag, props);
    }
}

impl useRouter -> dict {
    navigate = reactRouterUseNavigate();
    location = reactRouterUseLocation();
    params = reactRouterUseParams();
    return {
        "navigate": navigate,
        "location": location,
        "params": params,
        "pathname": location.pathname,
        "search": location.search,
        "hash": location.hash
    };
}

impl navigate(path: str) -> None {
    window.history.pushState({}, "", path);
    window.dispatchEvent(Reflect.construct(PopStateEvent, ["popstate"]));
}

impl __createJacSchema(zodLib: any) -> any {
    handler = {
        "apply": lambda target: any , thisArg: any , argumentsList: any -> any {
        # When called as JacSchema({...}), call z.object({...})
        return zodLib.object.apply(zodLib, argumentsList); },
        "get": lambda target: any , prop: any , receiver: any -> any {
        # When accessing properties like JacSchema.string(), forward to z
        return zodLib[prop]; }
    };
    # Create a dummy function as the proxy target
    dummyFunc = lambda schema: any -> any { return zodLib.object(schema); };
    return Reflect.construct(Proxy, [dummyFunc, handler]);
}

impl __getApiBaseUrl -> str {
    # globalThis.__JAC_API_BASE_URL__ is replaced by Vite's define at build time.
    # Falls back to empty string (same-origin) when not configured.
    return globalThis.__JAC_API_BASE_URL__ || "";
}

impl __getJacInitData -> dict {
    if not globalThis.__jacInitData__ {
        initEl = None;
        try {
            initEl = document.getElementById("__jac_init__");
        } except Exception as e {
            console.warn("[jac-client] Failed to find __jac_init__ element:", e);
        }
        if initEl {
            try {
                globalThis.__jacInitData__ = JSON.parse(initEl.textContent) or {};
            } except Exception as e {
                console.warn(
                    "[jac-client] Failed to parse __jac_init__ data, using empty init payload:",
                    e
                );
                globalThis.__jacInitData__ = {};
            }
        } else {
            globalThis.__jacInitData__ = {};
        }
    }
    return globalThis.__jacInitData__;
}

impl __getDebugUiConfig -> dict {
    initData = __getJacInitData();
    serverDebug = initData["debugUi"] if initData["debugUi"] else {};
    localFlag = __getLocalStorage("jac_debug_ui");
    queryFlag = "";
    trueFlags = ["1", "true", "TRUE", "True"];
    falseFlags = ["0", "false", "FALSE", "False"];
    try {
        params = Reflect.construct(URLSearchParams, [window.location.search]);
        queryFlag = params.get("jac_debug") or "";
    } except Exception { }
    if trueFlags.includes(queryFlag) {
        __setLocalStorage("jac_debug_ui", "1");
        localFlag = "1";
    } elif falseFlags.includes(queryFlag) {
        __removeLocalStorage("jac_debug_ui");
        localFlag = "";
    }
    envFlag = globalThis.__JAC_DEBUG_UI__ || "";
    featureEnabled = (
        trueFlags.includes(queryFlag)
        or localFlag == "1"
        or envFlag == "1"
        or envFlag == True
    );
    traceErrors = bool(serverDebug["traceErrors"]) if serverDebug else False;
    return {
        "enabled": bool(traceErrors or featureEnabled),
        "traceErrors": traceErrors,
        "featureFlag": featureEnabled,
        "queryFlag": queryFlag,
        "server": serverDebug
    };
}

impl jacShouldShowDebugUi -> bool {
    return bool(__getDebugUiConfig()["enabled"]);
}

impl __getDebugStore -> dict {
    if not globalThis.__jacDebugStore__ {
        globalThis.__jacDebugStore__ = {
            "events": [],
            "maxEvents": 100,
            "consolePatched": False,
            "llmTraceRequests": {}
        };
    }
    return globalThis.__jacDebugStore__;
}

impl __debugValueToString(value: Any) -> str {
    if value == None {
        return "null";
    }
    try {
        if value.message {
            return String(value.message);
        }
    } except Exception {
    }
    try {
        jsonValue = JSON.stringify(value);
        if jsonValue and jsonValue != "{}" {
            return jsonValue;
        }
    } except Exception {
    }
    return String(value);
}

impl __debugArgsToMessage(*args: Any) -> str {
    parts = [];
    for arg in args {
        parts.push(__debugValueToString(arg));
    }
    return parts.join(" ");
}

impl __notifyDebugStore -> None {
    try {
        window.dispatchEvent(
            Reflect.construct(Event, ["jac-debug-store-update"])
        );
    } except Exception {
    }
}

impl __recordDebugEvent(
    severity: str,
    source: str,
    message: str,
    stack: str = "",
    details: dict = {}
) -> None {
    if not message and not stack {
        return;
    }
    store = __getDebugStore();
    timestamp = Reflect.construct(Date, []).toISOString();
    route = "";
    try {
        route = window.location.pathname or "";
    } except Exception {
    }
    fingerprint = f"{severity}|{message}|{stack}";
    existing = None;
    for event in store["events"] {
        if event["fingerprint"] == fingerprint {
            existing = event;
        }
    }
    if existing {
        existing["timestamp"] = timestamp;
        existing["count"] = existing["count"] + 1;
        if not existing["sources"].includes(source) {
            existing["sources"].push(source);
        }
        if route {
            existing["route"] = route;
        }
        if details {
            existing["details"] = details;
        }
    } else {
        store["events"].push(
            {
                "id": len(store["events"]) + 1,
                "fingerprint": fingerprint,
                "severity": severity,
                "message": message,
                "stack": stack,
                "sources": [source],
                "route": route,
                "timestamp": timestamp,
                "count": 1,
                "details": details or {}
            }
        );
        while len(store["events"]) > store["maxEvents"] {
            store["events"].shift();
        }
    }
    __notifyDebugStore();
}

impl __recordLlmTraceEvent(trace: dict, source: str = "llm.trace") -> None {
    invocationId = trace["invocation_id"] or "";
    if not invocationId {
        return;
    }
    store = __getDebugStore();
    timestamp = Reflect.construct(Date, []).toISOString();
    route = "";
    try {
        route = window.location.pathname or "";
    } except Exception {
    }
    summary = {
        "invocation_id": invocationId,
        "caller_name": trace["caller_name"] or "unknown",
        "model": trace["model"] or "unknown",
        "status": trace["status"] or "unknown",
        "total_latency_ms": trace["total_latency_ms"] or 0,
        "total_tokens": trace["total_tokens"] or 0,
        "total_cost": trace["total_cost"] or 0,
        "llm_call_count": trace["llm_call_count"] or len(trace["llm_calls"] or []),
        "error": trace["error"] or ""
    };
    message = f"{summary['caller_name']} -> {summary['model']}";
    fingerprint = f"llm_trace|{invocationId}";
    existing = None;
    for event in store["events"] {
        if event["fingerprint"] == fingerprint {
            existing = event;
        }
    }
    if existing {
        existing["timestamp"] = timestamp;
        if route {
            existing["route"] = route;
        }
        if not existing["sources"].includes(source) {
            existing["sources"].push(source);
        }
        existing["message"] = message;
        existing["details"] = summary;
        existing["trace"] = trace;
    } else {
        store["events"].push(
            {
                "id": len(store["events"]) + 1,
                "fingerprint": fingerprint,
                "kind": "llm_trace",
                "severity": "info",
                "message": message,
                "stack": "",
                "sources": [source],
                "route": route,
                "timestamp": timestamp,
                "count": 1,
                "details": summary,
                "trace": trace
            }
        );
        while len(store["events"]) > store["maxEvents"] {
            store["events"].shift();
        }
    }
    __notifyDebugStore();
}

impl __extractLlmTraceIds(payload: dict) -> list {
    traceIds = [];
    if not payload or not payload["meta"] or not payload["meta"]["extra"] {
        return traceIds;
    }
    rawIds = payload["meta"]["extra"]["llm_trace_ids"];
    if not rawIds or not Array.isArray(rawIds) {
        return traceIds;
    }
    for traceId in rawIds {
        if traceId and not traceIds.includes(traceId) {
            traceIds.push(traceId);
        }
    }
    return traceIds;
}

impl __fetchLlmTraceDetail(
    invocation_id: str, source: str = "llm.trace"
) -> None {
    if not invocation_id {
        return;
    }
    store = __getDebugStore();
    if store["llmTraceRequests"][invocation_id] {
        return;
    }
    for event in store["events"] {
        if event["kind"] == "llm_trace"
        and event["details"]
        and event["details"]["invocation_id"] == invocation_id
        and event["trace"]
        and event["trace"]["llm_calls"] {
            return;
        }
    }
    store["llmTraceRequests"][invocation_id] = True;
    try {
        response = await fetch(
            __getApiBaseUrl()
                + "/debug/llm/telemetry/traces/"
                + encodeURIComponent(invocation_id),
            {
                "method": "GET",
                "headers": {"Accept": "application/json"}
            }
        );
        if not response.ok {
            return;
        }
        payload = JSON.parse(await response.text());
        if payload["ok"] and payload["data"] {
            __recordLlmTraceEvent(payload["data"], source);
        }
    } except Exception {
    } finally {
        Reflect.deleteProperty(store["llmTraceRequests"], invocation_id);
    }
}

impl __maybeLoadLlmTraces(
    payload: dict, source: str = "llm.trace"
) -> None {
    traceIds = __extractLlmTraceIds(payload);
    for traceId in traceIds {
        await __fetchLlmTraceDetail(traceId, source);
    }
}

impl __installDebugConsoleHooks -> None {
    store = __getDebugStore();
    if store["consolePatched"] {
        return;
    }
    store["consolePatched"] = True;
    originalWarn = console.warn;
    originalError = console.error;
    def patchedWarn(message: Any = "", meta: Any = None) -> None {
        warnText = String(message);
        if meta {
            warnText = warnText + " " + String(meta);
        }
        __recordDebugEvent(
            "warning",
            "console.warn",
            warnText
        );
        originalWarn.apply(console, [message, meta] if meta else [message]);
    }
    def patchedError(message: Any = "", meta: Any = None) -> None {
        errorText = String(message);
        if meta {
            errorText = errorText + " " + String(meta);
        }
        __recordDebugEvent(
            "error",
            "console.error",
            errorText
        );
        originalError.apply(
            console,
            [message, meta] if meta else [message]
        );
    }
    console.warn = patchedWarn;
    console.error = patchedError;
}

impl __getDebugSnapshot -> dict {
    store = __getDebugStore();
    errors = [];
    warnings = [];
    llmTraces = [];
    idx = len(store["events"]) - 1;
    while idx >= 0 {
        event = store["events"][idx];
        if event["kind"] == "llm_trace" {
            llmTraces.push(event);
        } elif event["severity"] == "error" {
            errors.push(event);
        } elif event["severity"] == "warning" {
            warnings.push(event);
        }
        idx = idx - 1;
    }
    status = "ok";
    if len(errors) > 0 {
        status = "error";
    } elif len(warnings) > 0 {
        status = "warning";
    }
    return {
        "events": store["events"],
        "errors": errors,
        "warnings": warnings,
        "llmTraces": llmTraces,
        "errorCount": len(errors),
        "warningCount": len(warnings),
        "llmTraceCount": len(llmTraces),
        "eventCount": len(store["events"]),
        "status": status
    };
}

impl __clearDebugEvents -> None {
    store = __getDebugStore();
    store["events"] = [];
    store["llmTraceRequests"] = {};
    __notifyDebugStore();
}

impl __renderDebugEventListItem(
    event: dict, is_selected: bool = False, on_select: Any = None
) -> JsxElement {
    isLlmTrace = event["kind"] == "llm_trace";
    severityColor = (
        "#2563eb"
        if isLlmTrace and event["details"] and event["details"]["status"] != "error"
        else (
            "#dc2626"
            if (
                (isLlmTrace and event["details"] and event["details"]["status"] == "error")
                or event["severity"] == "error"
            )
            else "#d97706"
        )
    );
    itemStyle = {
        padding: "0.75rem 0.8rem",
        borderRadius: "12px",
        border: (
            f"1px solid {severityColor}"
            if is_selected
            else "1px solid rgba(15, 23, 42, 0.08)"
        ),
        background: (
            "#eff6ff"
            if isLlmTrace
            else ("#fff7ed" if event["severity"] == "warning" else "#fff")
        ),
        boxShadow: (
            "0 8px 18px rgba(15, 23, 42, 0.08)"
            if is_selected
            else "none"
        ),
        cursor: "pointer",
        marginBottom: "0.6rem"
    };
    preview = event["message"] or "(no message)";
    if len(preview) > 90 {
        preview = preview[:87] + "...";
    }
    return (
        <div
            onClick={on_select}
            style={itemStyle}
            role="button"
        >
            <div
                style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    gap: "0.5rem",
                    marginBottom: "0.35rem"
                }}
            >
                <span
                    style={{
                        color: severityColor,
                        fontWeight: "700",
                        textTransform: "uppercase",
                        letterSpacing: "0.06em"
                    }}
                >
                    {"llm" if isLlmTrace else event["severity"]}
                </span>
                <span style={{color: "#64748b"}}>
                    {
                        (
                            str(event["details"]["llm_call_count"]) + " calls"
                            if isLlmTrace and event["details"]
                            else str(event["count"]) + "x"
                        )
                    }
                </span>
            </div>
            <div style={{fontWeight: "600", marginBottom: "0.25rem"}}>
                {preview}
            </div>
            <div style={{color: "#475569", fontSize: "11px"}}>
                {
                    (
                        (event["details"]["status"] or "unknown")
                        + " · "
                        + (event["details"]["invocation_id"] or "")
                        if isLlmTrace and event["details"]
                        else event["sources"].join(", ")
                    )
                }
            </div>
            <div style={{color: "#94a3b8", fontSize: "11px"}}>
                {event["timestamp"]}
            </div>
        </div>
    );
}

impl __renderDebugEventDetail(
    event: dict, trace_enabled: bool = False
) -> JsxElement {
    if event["kind"] == "llm_trace" {
        return __renderDebugLlmTraceDetail(event);
    }
    severityColor = "#dc2626" if event["severity"] == "error" else "#d97706";
    details = event["details"] or {};
    detailText = "";
    stackLines = [];
    stackViews = [];
    stackText = event["stack"] or "";
    endpoint = details["endpoint"] or "";
    method = details["method"] or "";
    httpStatus = details["http_status"] or "";
    errorCode = details["code"] or "";
    errorId = details["error_id"] or "";
    traceId = details["trace_id"] or "";
    requestId = details["request_id"] or "";
    try {
        detailText = JSON.stringify(details, None, 2);
    } except Exception {
        detailText = "";
    }
    if stackText {
        stackLines = stackText.split("\n");
        for idx in range(len(stackLines)) {
            line = stackLines[idx];
            stackViews.push(
                <div
                    key={str(idx)}
                    style={{
                        padding: "0.55rem 0.7rem",
                        borderTop: (
                            "1px solid rgba(15, 23, 42, 0.06)"
                            if idx > 0
                            else "none"
                        ),
                        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
                        fontSize: "11px",
                        whiteSpace: "pre-wrap",
                        wordBreak: "break-word",
                        background: "#fff"
                    }}
                >
                    {line}
                </div>
            );
        }
    }
    return (
        <div>
            <div
                style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    gap: "0.75rem",
                    marginBottom: "0.75rem"
                }}
            >
                <div>
                    <div
                        style={{
                            color: severityColor,
                            fontWeight: "700",
                            textTransform: "uppercase",
                            letterSpacing: "0.06em",
                            marginBottom: "0.25rem"
                        }}
                    >
                        {event["severity"]}
                    </div>
                    <div style={{fontSize: "18px", fontWeight: "700"}}>
                        {event["message"]}
                    </div>
                </div>
                <div style={{color: "#64748b", textAlign: "right"}}>
                    <div>{event["timestamp"]}</div>
                    <div>{event["count"]}x</div>
                </div>
            </div>
            <div
                style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                    gap: "0.6rem",
                    marginBottom: "0.9rem"
                }}
            >
                <div>
                    <div style={{color: "#64748b"}}>Sources</div>
                    <div>{event["sources"].join(", ")}</div>
                </div>
                <div>
                    <div style={{color: "#64748b"}}>Route</div>
                    <div>{event["route"] or "-"}</div>
                </div>
                <div hidden={not endpoint}>
                    <div style={{color: "#64748b"}}>Endpoint</div>
                    <div>{endpoint}</div>
                </div>
                <div hidden={not method}>
                    <div style={{color: "#64748b"}}>Method</div>
                    <div>{method}</div>
                </div>
                <div hidden={not httpStatus}>
                    <div style={{color: "#64748b"}}>HTTP Status</div>
                    <div>{httpStatus}</div>
                </div>
                <div hidden={not errorCode}>
                    <div style={{color: "#64748b"}}>Code</div>
                    <div>{errorCode}</div>
                </div>
                <div hidden={not errorId}>
                    <div style={{color: "#64748b"}}>Error ID</div>
                    <div>{errorId}</div>
                </div>
                <div hidden={not traceId}>
                    <div style={{color: "#64748b"}}>Trace ID</div>
                    <div>{traceId}</div>
                </div>
                <div hidden={not requestId}>
                    <div style={{color: "#64748b"}}>Request ID</div>
                    <div>{requestId}</div>
                </div>
            </div>
            <div hidden={len(stackLines) == 0}>
                <div style={{fontWeight: "700", marginBottom: "0.45rem"}}>
                    Stack / Trace
                </div>
                <div
                    style={{
                        border: "1px solid rgba(15, 23, 42, 0.08)",
                        borderRadius: "12px",
                        overflow: "hidden",
                        marginBottom: "0.9rem"
                    }}
                >
                    {stackViews}
                </div>
            </div>
            <div hidden={not detailText or detailText == "{}"}>
                <div style={{fontWeight: "700", marginBottom: "0.45rem"}}>
                    Structured Details
                </div>
                <pre
                    style={{
                        margin: "0",
                        padding: "0.75rem",
                        borderRadius: "12px",
                        background: "#f8fafc",
                        border: "1px solid rgba(15, 23, 42, 0.08)",
                        whiteSpace: "pre-wrap",
                        wordBreak: "break-word",
                        overflowX: "auto"
                    }}
                >
                    {detailText}
                </pre>
            </div>
            <div
                hidden={not trace_enabled}
                style={{
                    marginTop: "0.75rem",
                    color: "#64748b",
                    fontSize: "11px"
                }}
            >
                Structured trace capture is enabled for this app.
            </div>
        </div>
    );
}

impl __renderDebugLlmTraceDetail(event: dict) -> JsxElement {
    trace = event["trace"] or {};
    summary = event["details"] or {};
    promptText = trace["user_prompt"] or "";
    responseText = trace["agent_response"] or "";
    historyText = "";
    traceError = trace["error"] or "";
    llmCalls = trace["llm_calls"] or [];
    invocationId = summary["invocation_id"] or "";
    callerName = summary["caller_name"] or "";
    modelName = summary["model"] or "";
    traceStatus = summary["status"] or "unknown";
    totalLatencyMs = summary["total_latency_ms"] or 0;
    totalTokens = summary["total_tokens"] or 0;
    llmCallCount = summary["llm_call_count"] or len(llmCalls);
    callViews = [];
    try {
        if trace["conversation_history"] {
            historyText = JSON.stringify(trace["conversation_history"], None, 2);
        }
    } except Exception {
        historyText = "";
    }
    for idx in range(len(llmCalls)) {
        call = llmCalls[idx];
        messagesText = "";
        responseDetail = "";
        callModel = call["model"] or modelName or "unknown";
        callStatus = call["status"] or "unknown";
        callLatencyMs = call["latency_ms"] or 0;
        callPromptTokens = call["prompt_tokens"] or 0;
        callCompletionTokens = call["completion_tokens"] or 0;
        callCost = call["response_cost"] or 0;
        callError = call["error"] or "";
        try {
            messagesText = JSON.stringify(call["messages"] or [], None, 2);
        } except Exception {
            messagesText = String(call["messages"] or "");
        }
        try {
            responseDetail = JSON.stringify(call["response"], None, 2);
        } except Exception {
            responseDetail = String(call["response"] or "");
        }
        callViews.push(
            <div
                key={invocationId + "-" + str(idx)}
                style={{
                    border: "1px solid rgba(37, 99, 235, 0.12)",
                    borderRadius: "14px",
                    background: "#f8fbff",
                    padding: "0.85rem",
                    marginBottom: "0.75rem"
                }}
            >
                <div
                    style={{
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "center",
                        gap: "0.75rem",
                        marginBottom: "0.55rem"
                    }}
                >
                    <div style={{fontWeight: "700"}}>
                        Call {idx + 1} · {callModel}
                    </div>
                    <div style={{color: "#475569"}}>
                        {callStatus}
                    </div>
                </div>
                <div
                    style={{
                        display: "grid",
                        gridTemplateColumns: "repeat(4, minmax(0, 1fr))",
                        gap: "0.5rem",
                        marginBottom: "0.65rem",
                        color: "#334155"
                    }}
                >
                    <div>Latency: {str(Math.round(callLatencyMs))}ms</div>
                    <div>Prompt: {str(callPromptTokens)}</div>
                    <div>Completion: {str(callCompletionTokens)}</div>
                    <div>Cost: ${str(callCost)}</div>
                </div>
                <div hidden={not messagesText}>
                    <div style={{fontWeight: "700", marginBottom: "0.35rem"}}>
                        Messages
                    </div>
                    <pre
                        style={{
                            margin: "0 0 0.65rem 0",
                            padding: "0.7rem",
                            borderRadius: "12px",
                            background: "#ffffff",
                            border: "1px solid rgba(15, 23, 42, 0.08)",
                            whiteSpace: "pre-wrap",
                            wordBreak: "break-word",
                            overflowX: "auto"
                        }}
                    >
                        {messagesText}
                    </pre>
                </div>
                <div hidden={not responseDetail}>
                    <div style={{fontWeight: "700", marginBottom: "0.35rem"}}>
                        Response
                    </div>
                    <pre
                        style={{
                            margin: "0",
                            padding: "0.7rem",
                            borderRadius: "12px",
                            background: "#ffffff",
                            border: "1px solid rgba(15, 23, 42, 0.08)",
                            whiteSpace: "pre-wrap",
                            wordBreak: "break-word",
                            overflowX: "auto"
                        }}
                    >
                        {responseDetail}
                    </pre>
                </div>
                <div hidden={not callError} style={{marginTop: "0.65rem", color: "#b91c1c"}}>
                    Error: {callError}
                </div>
            </div>
        );
    }
    return (
        <div>
            <div
                style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    gap: "0.75rem",
                    marginBottom: "0.9rem"
                }}
            >
                <div>
                    <div
                        style={{
                            color: "#2563eb",
                            fontWeight: "700",
                            textTransform: "uppercase",
                            letterSpacing: "0.06em",
                            marginBottom: "0.25rem"
                        }}
                    >
                        llm trace
                    </div>
                    <div style={{fontSize: "18px", fontWeight: "700"}}>
                        {event["message"]}
                    </div>
                </div>
                <div style={{color: "#64748b", textAlign: "right"}}>
                    <div>{traceStatus}</div>
                    <div>{event["timestamp"]}</div>
                </div>
            </div>
            <div
                style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                    gap: "0.6rem",
                    marginBottom: "0.9rem"
                }}
            >
                <div>
                    <div style={{color: "#64748b"}}>Invocation ID</div>
                    <div>{invocationId or "-"}</div>
                </div>
                <div>
                    <div style={{color: "#64748b"}}>Caller</div>
                    <div>{callerName or "-"}</div>
                </div>
                <div>
                    <div style={{color: "#64748b"}}>Model</div>
                    <div>{modelName or "-"}</div>
                </div>
                <div>
                    <div style={{color: "#64748b"}}>Calls</div>
                    <div>{llmCallCount}</div>
                </div>
                <div>
                    <div style={{color: "#64748b"}}>Latency</div>
                    <div>{str(Math.round(totalLatencyMs))}ms</div>
                </div>
                <div>
                    <div style={{color: "#64748b"}}>Tokens</div>
                    <div>{totalTokens}</div>
                </div>
            </div>
            <div hidden={not promptText} style={{marginBottom: "0.9rem"}}>
                <div style={{fontWeight: "700", marginBottom: "0.4rem"}}>
                    Prompt
                </div>
                <pre
                    style={{
                        margin: "0",
                        padding: "0.75rem",
                        borderRadius: "12px",
                        background: "#f8fafc",
                        border: "1px solid rgba(15, 23, 42, 0.08)",
                        whiteSpace: "pre-wrap",
                        wordBreak: "break-word",
                        overflowX: "auto"
                    }}
                >
                    {promptText}
                </pre>
            </div>
            <div hidden={not responseText} style={{marginBottom: "0.9rem"}}>
                <div style={{fontWeight: "700", marginBottom: "0.4rem"}}>
                    Agent Response
                </div>
                <pre
                    style={{
                        margin: "0",
                        padding: "0.75rem",
                        borderRadius: "12px",
                        background: "#f8fafc",
                        border: "1px solid rgba(15, 23, 42, 0.08)",
                        whiteSpace: "pre-wrap",
                        wordBreak: "break-word",
                        overflowX: "auto"
                    }}
                >
                    {responseText}
                </pre>
            </div>
            <div hidden={not traceError} style={{marginBottom: "0.9rem", color: "#b91c1c"}}>
                Error: {traceError}
            </div>
            <div hidden={not historyText} style={{marginBottom: "0.9rem"}}>
                <div style={{fontWeight: "700", marginBottom: "0.4rem"}}>
                    Conversation History
                </div>
                <pre
                    style={{
                        margin: "0",
                        padding: "0.75rem",
                        borderRadius: "12px",
                        background: "#f8fafc",
                        border: "1px solid rgba(15, 23, 42, 0.08)",
                        whiteSpace: "pre-wrap",
                        wordBreak: "break-word",
                        overflowX: "auto",
                        maxHeight: "220px",
                        overflowY: "auto"
                    }}
                >
                    {historyText}
                </pre>
            </div>
            <div>
                <div style={{fontWeight: "700", marginBottom: "0.5rem"}}>
                    LLM Calls ({str(len(llmCalls))})
                </div>
                <div hidden={len(llmCalls) != 0}>
                    <div style={{color: "#64748b"}}>
                        No per-call records available for this trace yet.
                    </div>
                </div>
                {callViews}
            </div>
        </div>
    );
}

impl __renderDebugEvent(event: dict) -> JsxElement {
    return __renderDebugEventDetail(event);
}

# ============================================================================
# AUTO-CACHE INFRASTRUCTURE
# ============================================================================

# Read compiler-provided endpoint effects from __jac_init__ JSON
impl __getEndpointEffects -> dict {
    if not globalThis.__jacEndpointEffects__ {
        data = __getJacInitData();
        globalThis.__jacEndpointEffects__ = data["endpointEffects"] or {};
    }
    return globalThis.__jacEndpointEffects__;
}

# Get or initialize cache state on globalThis
impl __getCacheState -> dict {
    if not globalThis.__jacCacheState__ {
        globalThis.__jacCacheState__ = {
            "cache": {},
            "order": [],
            "pending": {},
            "config": {"maxEntries": 500, "defaultTtlMs": 60000}
        };
    }
    return globalThis.__jacCacheState__;
}

# Check if a cache entry is still fresh
impl __isFresh(`entry: dict) -> bool {
    if not `entry {
        return False;
    }
    age = Date.now() - `entry["timestamp"];
    return age < `entry["ttl"];
}

# Get a cache entry and promote it in LRU order
impl __cacheGet(key: str) -> dict {
    state = __getCacheState();
    entry = state["cache"][key];
    if not entry {
        return None;
    }
    # Move to end (most recently used)
    idx = state["order"].indexOf(key);
    if idx > -1 {
        state["order"].splice(idx, 1);
    }
    state["order"].push(key);
    return entry;
}

# Store an entry in the cache with LRU eviction
impl __cacheSet(key: str, data: Any, ttl: int) -> None {
    state = __getCacheState();
    # Remove existing entry if present
    if state["cache"][key] {
        idx = state["order"].indexOf(key);
        if idx > -1 {
            state["order"].splice(idx, 1);
        }
    }
    # Evict oldest if at capacity
    while len(state["order"]) >= state["config"]["maxEntries"] {
        __evictOldest();
    }
    state["cache"][key] = {"data": data, "timestamp": Date.now(), "ttl": ttl};
    state["order"].push(key);
}

# Evict the oldest cache entry
impl __evictOldest -> None {
    state = __getCacheState();
    if len(state["order"]) > 0 {
        oldest = state["order"].shift();
        if oldest and state["cache"][oldest] {
            Reflect.deleteProperty(state["cache"], oldest);
        }
    }
}

# Check if two lists share any element
impl __overlaps(list1: list, list2: list) -> bool {
    for item in list1 {
        if list2.includes(item) {
            return True;
        }
    }
    return False;
}

# Invalidate all cache entries for a given endpoint key prefix
impl __invalidateEndpoint(endpoint_key: str) -> None {
    state = __getCacheState();
    keys_to_delete = [];
    for key in Object.keys(state["cache"]) {
        if key.startsWith(endpoint_key) {
            keys_to_delete.push(key);
        }
    }
    for key in keys_to_delete {
        Reflect.deleteProperty(state["cache"], key);
        idx = state["order"].indexOf(key);
        if idx > -1 {
            state["order"].splice(idx, 1);
        }
    }
}

# ============================================================================
# RAW FETCH HELPERS (no caching, just HTTP)
# ============================================================================

# Direct walker fetch (POST /walker/<name>[/<nodeId>])
impl __doWalkerFetch(`walker: str, nodeId: str, fields: dict) -> Any {
    token = __getLocalStorage("jac_token");
    base_url = __getApiBaseUrl();
    url = f"{base_url}/walker/{`walker}";
    if nodeId != "" {
        url = f"{base_url}/walker/{`walker}/{nodeId}";
    }
    headers = {"Content-Type": "application/json", "Accept": "application/json"};
    if token {
        headers["Authorization"] = f"Bearer {token}";
    }
    response = await fetch(
        url, {"method": "POST", "headers": headers, "body": JSON.stringify(fields)}
    );
    if not response.ok {
        response_text = await response.text();
        response_payload = None;
        try {
            response_payload = JSON.parse(response_text);
        } except Exception {
        }
        if response.status == 401 {
            __recordDebugEvent(
                "warning",
                "fetch.walker",
                f"Walker {`walker} returned 401",
                "",
                {
                    "endpoint": url,
                    "method": "POST",
                    "http_status": response.status
                }
            );
            __removeLocalStorage("jac_token");
            window.location.reload();
            return {};
        }
        walker_name = f"{`walker}/{nodeId}" if nodeId else `walker;
        error_message = f"Walker {walker_name} failed";
        error_stack = "";
        error_details = {
            "endpoint": url,
            "method": "POST",
            "http_status": response.status,
            "target": walker_name
        };
        if response_payload and response_payload["error"] {
            error_obj = response_payload["error"];
            if error_obj["message"] {
                error_message = error_obj["message"];
            }
            if error_obj["code"] {
                error_details["code"] = error_obj["code"];
            }
            if error_obj["details"] {
                for key in Object.keys(error_obj["details"]) {
                    error_details[key] = error_obj["details"][key];
                }
                if error_obj["details"]["traceback"] {
                    error_stack = error_obj["details"]["traceback"];
                }
            }
        } else {
            error_details["raw_response"] = response_text;
        }
        if response_payload and response_payload["meta"] {
            if response_payload["meta"]["trace_id"] and not error_details["trace_id"] {
                error_details["trace_id"] = response_payload["meta"]["trace_id"];
            }
            if response_payload["meta"]["request_id"] and not error_details["request_id"] {
                error_details["request_id"] = response_payload["meta"]["request_id"];
            }
        }
        if response_payload {
            await __maybeLoadLlmTraces(response_payload, "fetch.walker");
        }
        __recordDebugEvent(
            "error",
            "fetch.walker",
            error_message,
            error_stack,
            error_details
        );
        raise Exception(f"Walker {walker_name} failed: {response_text}");
    }
    payload = await response.json();
    await __maybeLoadLlmTraces(payload, "fetch.walker");
    return payload["data"] if payload["data"] else {};
}

# Direct function fetch (POST /function/<name>)
impl __doFuncFetch(function_name: str, args: dict) -> Any {
    token = __getLocalStorage("jac_token");
    base_url = __getApiBaseUrl();
    headers = {"Content-Type": "application/json"};
    if token {
        headers["Authorization"] = f"Bearer {token}";
    }
    response = await fetch(
        f"{base_url}/function/{function_name}",
        {"method": "POST", "headers": headers, "body": JSON.stringify(args)}
    );
    if not response.ok {
        response_text = await response.text();
        response_payload = None;
        try {
            response_payload = JSON.parse(response_text);
        } except Exception {
        }
        error_message = f"Function {function_name} failed";
        error_stack = "";
        error_details = {
            "endpoint": f"{base_url}/function/{function_name}",
            "method": "POST",
            "http_status": response.status,
            "target": function_name
        };
        if response_payload and response_payload["error"] {
            error_obj = response_payload["error"];
            if error_obj["message"] {
                error_message = error_obj["message"];
            }
            if error_obj["code"] {
                error_details["code"] = error_obj["code"];
            }
            if error_obj["details"] {
                for key in Object.keys(error_obj["details"]) {
                    error_details[key] = error_obj["details"][key];
                }
                if error_obj["details"]["traceback"] {
                    error_stack = error_obj["details"]["traceback"];
                }
            }
        } else {
            error_details["raw_response"] = response_text;
        }
        if response_payload and response_payload["meta"] {
            if response_payload["meta"]["trace_id"] and not error_details["trace_id"] {
                error_details["trace_id"] = response_payload["meta"]["trace_id"];
            }
            if response_payload["meta"]["request_id"] and not error_details["request_id"] {
                error_details["request_id"] = response_payload["meta"]["request_id"];
            }
        }
        if response_payload {
            await __maybeLoadLlmTraces(response_payload, "fetch.function");
        }
        __recordDebugEvent(
            "error",
            "fetch.function",
            error_message,
            error_stack,
            error_details
        );
        raise Exception(f"Function {function_name} failed: {response_text}");
    }
    payload = await response.json();
    await __maybeLoadLlmTraces(payload, "fetch.function");
    if not payload["ok"] {
        error_obj = payload["error"] if payload["error"] else {};
        error_msg = (
            error_obj["message"]
            if error_obj and error_obj["message"]
            else (
                error_obj
                if error_obj and type(error_obj) == "string"
                else "Unknown error"
            )
        );
        error_stack = "";
        error_details = {
            "endpoint": f"{base_url}/function/{function_name}",
            "method": "POST",
            "target": function_name
        };
        if error_obj and error_obj["code"] {
            error_details["code"] = error_obj["code"];
        }
        if error_obj and error_obj["details"] {
            for key in Object.keys(error_obj["details"]) {
                error_details[key] = error_obj["details"][key];
            }
            if error_obj["details"]["traceback"] {
                error_stack = error_obj["details"]["traceback"];
            }
        }
        if payload["meta"] {
            if payload["meta"]["trace_id"] and not error_details["trace_id"] {
                error_details["trace_id"] = payload["meta"]["trace_id"];
            }
            if payload["meta"]["request_id"] and not error_details["request_id"] {
                error_details["request_id"] = payload["meta"]["request_id"];
            }
            if payload["meta"]["extra"] and payload["meta"]["extra"]["http_status"] {
                error_details["http_status"] = payload["meta"]["extra"]["http_status"];
            }
        }
        __recordDebugEvent(
            "error",
            "fetch.function",
            error_msg,
            error_stack,
            error_details
        );
        raise Exception(f"Function {function_name} failed: {error_msg}");
    }
    result = None;
    try {
        if payload["data"] and payload["data"]["result"] {
            result = payload["data"]["result"];
        }
    } except Exception as e {
        console.warn(f"Failed to extract result for {function_name}:", e);
    }
    return result;
}

# ============================================================================
# AUTO-CACHE DISPATCH — shared by __jacSpawn and __jacCallFunction
# ============================================================================
impl __cachedEndpointCall(endpoint_key: str, args_key: str, fetch_fn: Any) -> Any {
    effects = __getEndpointEffects();
    info = effects[endpoint_key];
    state = __getCacheState();
    # If endpoint is a known READER, check cache first
    if info and not info["is_writer"] {
        cached = __cacheGet(args_key);
        if cached and __isFresh(cached) {
            return cached["data"];
        }
        # Dedup concurrent identical requests
        if state["pending"][args_key] {
            return await state["pending"][args_key];
        }
        fetch_promise = fetch_fn();
        state["pending"][args_key] = fetch_promise;
        try {
            data = await fetch_promise;
            __cacheSet(args_key, data, state["config"]["defaultTtlMs"]);
            return data;
        } finally {
            Reflect.deleteProperty(state["pending"], args_key);
        }
    }
    # If endpoint is a known WRITER, fetch then auto-invalidate readers
    if info and info["is_writer"] {
        data = await fetch_fn();
        writer_touches = info["touches"];
        for endpoint_name in Object.keys(effects) {
            reader_info = effects[endpoint_name];
            if reader_info and not reader_info["is_writer"] {
                if writer_touches.includes("*")
                or __overlaps(reader_info["touches"], writer_touches) {
                    __invalidateEndpoint(endpoint_name);
                }
            }
        }
        return data;
    }
    # Unknown endpoint (no metadata) — direct fetch, no caching
    return await fetch_fn();
}

# ============================================================================
# PUBLIC API — __jacSpawn and __jacCallFunction with auto-caching
# ============================================================================
impl __jacSpawn(left: str, right: str = "", fields: dict = {}) -> Any {
    # Auth walkers always skip cache
    if left == "login"
    or left == "signup"
    or left == "logout"
    or left == "refresh_token" {
        return await __doWalkerFetch(left, right, fields);
    }
    endpoint_key = f"walker:{left}";
    args_key = f"{endpoint_key}:{right}:{JSON.stringify(fields)}";
    return await __cachedEndpointCall(
        endpoint_key,
        args_key,
        lambda -> Any { return __doWalkerFetch(left, right, fields); }
    );
}

impl jacSpawn(left: str, right: str = "", fields: dict = {}) -> Any {
    return __jacSpawn(left, right, fields);
}

impl __jacCallFunction(function_name: str, args: dict = {}) -> Any {
    endpoint_key = f"func:{function_name}";
    args_key = f"{endpoint_key}:{JSON.stringify(args)}";
    return await __cachedEndpointCall(
        endpoint_key,
        args_key,
        lambda -> Any { return __doFuncFetch(function_name, args); }
    );
}

impl jacSignup(username: str, password: str) -> dict {
    base_url = __getApiBaseUrl();
    response = await fetch(
        f"{base_url}/user/register",
        {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": JSON.stringify({"username": username, "password": password})
        }
    );
    if response.ok {
        data = JSON.parse(await response.text());
        token = None;
        if data["data"] and data["data"]["token"] {
            token = data["data"]["token"];
        }
        if token {
            # Clear cache on auth change
            state = __getCacheState();
            for key in Object.keys(state["cache"]) {
                Reflect.deleteProperty(state["cache"], key);
            }
            state["order"].splice(0, state["order"].length);
            __setLocalStorage("jac_token", token);
            return {"success": True, "token": token, "username": username};
        }
        return {"success": False, "error": "No token received"};
    } else {
        error_text = await response.text();
        try {
            error_data = JSON.parse(error_text);
            return {
                "success": False,
                "error": error_data["error"]
                    if error_data["error"] != None
                    else "Signup failed"
            };
        } except Exception {
            return {"success": False, "error": error_text};
        }
    }
}

impl jacLogin(username: str, password: str) -> bool {
    base_url = __getApiBaseUrl();
    response = await fetch(
        f"{base_url}/user/login",
        {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": JSON.stringify({"username": username, "password": password})
        }
    );
    if response.ok {
        data = JSON.parse(await response.text());
        token = None;
        try {
            if data["data"] and data["data"]["token"] {
                token = data["data"]["token"];
            }
        } except Exception as e {
            console.warn("Failed to extract login token:", e);
        }
        if token {
            # Clear cache on auth change
            state = __getCacheState();
            for key in Object.keys(state["cache"]) {
                Reflect.deleteProperty(state["cache"], key);
            }
            state["order"].splice(0, state["order"].length);
            __setLocalStorage("jac_token", token);
            return True;
        }
    }
    return False;
}

impl jacLogout -> None {
    # Clear cache on auth change
    state = __getCacheState();
    for key in Object.keys(state["cache"]) {
        Reflect.deleteProperty(state["cache"], key);
    }
    state["order"].splice(0, state["order"].length);
    __removeLocalStorage("jac_token");
}

impl jacIsLoggedIn -> bool {
    token = __getLocalStorage("jac_token");
    return token != None and token != "";
}

impl __getLocalStorage(key: str) -> str {
    storage = globalThis.localStorage;
    return storage.getItem(key) if storage else "";
}

impl __setLocalStorage(key: str, value: str) -> None {
    storage = globalThis.localStorage;
    if storage {
        storage.setItem(key, value);
    }
}

impl __removeLocalStorage(key: str) -> None {
    storage = globalThis.localStorage;
    if storage {
        storage.removeItem(key);
    }
}

"""Auth guard component for file-based routing. Renders child routes if
authenticated, otherwise redirects to the login path."""
impl AuthGuard(redirect: str = "/login") -> JsxElement {
    if jacIsLoggedIn() {
        return
            <ReactRouterOutlet/>;
    }
    return
        <ReactRouterNavigate to={redirect} replace={True}/>;
}

impl ErrorFallback(error: str, resetErrorBoundary: Any) -> JsxElement {
    # Report error to server for logging
    try {
        errMsg = error.error.message if error.error else str(error);
        errStack = error.error.stack if error.error else "";
        __recordDebugEvent("error", "ErrorBoundary", errMsg, errStack);
        __jacReportError(errMsg, errStack, "", "ErrorBoundary");
    } except Exception as e {
        console.warn("[jac-client] ErrorFallback: failed to report error:", e);
    }
    return
        <div
            role="alert"
            style={{
                minHeight: "100vh",
                display: "flex",
                justifyContent: "center",
                alignItems: "center",
                backgroundColor: "#f9fafb",
                fontFamily: "system-ui, sans-serif",

            }}
        >
            <div
                role="alert"
                style={{
                    minHeight: "100vh",
                    display: "flex",
                    flexDirection: "column",
                    justifyContent: "center",
                    alignItems: "center",
                    backgroundColor: "#f9fafb",
                    fontFamily: "system-ui, sans-serif",

                }}
            >
                <h2 style={{color: "#dc2626", marginBottom: "12px"}}>
                    🚨 Something went wrong
                </h2>
                <p style={{color: "#374151", marginBottom: "16px"}}>
                    An unexpected error occurred. Please try again.
                </p>
                <pre
                    style={{
                        color: "#991b1b",
                        background: "#fee2e2",
                        padding: "12px",
                        borderRadius: "8px",
                        fontSize: "14px",
                        overflowX: "auto",
                        marginBottom: "16px",

                    }}
                >
                    {error.error.message}
                </pre>
                <button
                    onClick={lambda { error.resetErrorBoundary();}}
                    style={{
                        backgroundColor: "#2563eb",
                        color: "#fff",
                        padding: "10px 16px",
                        borderRadius: "8px",
                        border: "none",
                        cursor: "pointer",
                        fontSize: "14px",

                    }}
                >
                    🔄 Try again
                </button>
            </div>
        </div>;
}

impl JacDebugWidget() -> JsxElement {
    config = __getDebugUiConfig();
    [open, setOpen] = reactUseState(False);
    [snapshot, setSnapshot] = reactUseState(__getDebugSnapshot());
    [selectedEventId, setSelectedEventId] = reactUseState(0);
    reactUseEffect(
        lambda {
            listener = lambda event: Any {
                setSnapshot(__getDebugSnapshot());
            };
            window.addEventListener("jac-debug-store-update", listener);
            return lambda {
                window.removeEventListener("jac-debug-store-update", listener);
            };
        },
        []
    );
    reactUseEffect(
        lambda {
            nextSelectedId = selectedEventId;
            exists = False;
            for event in snapshot["events"] {
                if event["id"] == nextSelectedId {
                    exists = True;
                }
            }
            if nextSelectedId == 0 or not exists {
                if len(snapshot["errors"]) > 0 {
                    nextSelectedId = snapshot["errors"][0]["id"];
                } elif len(snapshot["warnings"]) > 0 {
                    nextSelectedId = snapshot["warnings"][0]["id"];
                } elif len(snapshot["llmTraces"]) > 0 {
                    nextSelectedId = snapshot["llmTraces"][0]["id"];
                } else {
                    nextSelectedId = 0;
                }
            }
            if nextSelectedId != selectedEventId {
                setSelectedEventId(nextSelectedId);
            }
        },
        [snapshot, selectedEventId]
    );
    if not config["enabled"] {
        return <></>;
    }
    totalCount = snapshot["errorCount"] + snapshot["warningCount"];
    selectedEvent = None;
    for event in snapshot["errors"] {
        if event["id"] == selectedEventId {
            selectedEvent = event;
        }
    }
    for event in snapshot["warnings"] {
        if event["id"] == selectedEventId {
            selectedEvent = event;
        }
    }
    for event in snapshot["llmTraces"] {
        if event["id"] == selectedEventId {
            selectedEvent = event;
        }
    }
    errorViews = [];
    for event in snapshot["errors"] {
        errorViews.push(
            __renderDebugEventListItem(
                event,
                event["id"] == selectedEventId,
                lambda { setSelectedEventId(event["id"]); }
            )
        );
    }
    warningViews = [];
    for event in snapshot["warnings"] {
        warningViews.push(
            __renderDebugEventListItem(
                event,
                event["id"] == selectedEventId,
                lambda { setSelectedEventId(event["id"]); }
            )
        );
    }
    llmTraceViews = [];
    for event in snapshot["llmTraces"] {
        llmTraceViews.push(
            __renderDebugEventListItem(
                event,
                event["id"] == selectedEventId,
                lambda { setSelectedEventId(event["id"]); }
            )
        );
    }
    chipStyle = {
        position: "fixed",
        right: "16px",
        bottom: "16px",
        zIndex: 2147483647,
        display: "flex",
        alignItems: "center",
        gap: "0.5rem",
        padding: "0.72rem 0.82rem",
        borderRadius: "999px",
        border: "1px solid rgba(15, 23, 42, 0.12)",
        background: (
            "#dc2626"
            if snapshot["status"] == "error"
            else (
                "#d97706"
                if snapshot["status"] == "warning"
                else "rgba(15, 23, 42, 0.92)"
            )
        ),
        color: "white",
        boxShadow: "0 12px 30px rgba(15, 23, 42, 0.28)",
        cursor: "pointer",
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        fontSize: "12px"
    };
    panelStyle = {
        position: "fixed",
        right: "16px",
        bottom: "72px",
        zIndex: 2147483647,
        width: "880px",
        height: "560px",
        border: "1px solid rgba(15, 23, 42, 0.12)",
        background: "rgba(255, 255, 255, 0.98)",
        color: "#0f172a",
        boxShadow: "0 18px 40px rgba(15, 23, 42, 0.18)",
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        fontSize: "12px",
        lineHeight: "1.5",
        borderRadius: "18px",
        overflow: "hidden"
    };
    shellStyle = {
        display: "grid",
        gridTemplateColumns: "320px minmax(0, 1fr)",
        height: "100%"
    };
    listPaneStyle = {
        borderRight: "1px solid rgba(15, 23, 42, 0.08)",
        padding: "0.9rem 0.85rem",
        overflowY: "auto",
        background: "#fcfcfd"
    };
    detailPaneStyle = {
        padding: "1rem 1.1rem",
        overflowY: "auto"
    };
    statusColor = (
        "#fecaca"
        if snapshot["status"] == "error"
        else ("#fde68a" if snapshot["status"] == "warning" else "#86efac")
    );
    return (
        <>
            <div
                onClick={lambda { setOpen(not open);}}
                style={chipStyle}
                role="button"
                title="Toggle Jac debug overlay"
            >
                <span
                    style={{
                        width: "8px",
                        height: "8px",
                        borderRadius: "999px",
                        background: statusColor,
                        display: "inline-block"
                    }}
                />
                <span>
                    {totalCount}
                </span>
            </div>
            <div style={panelStyle} hidden={not open}>
                <div style={shellStyle}>
                    <div style={listPaneStyle}>
                        <div
                            style={{
                                display: "flex",
                                justifyContent: "space-between",
                                alignItems: "center",
                                gap: "0.75rem",
                                marginBottom: "0.85rem"
                            }}
                        >
                            <div>
                                <div style={{fontWeight: "700"}}>
                                    Debug Events
                                </div>
                                <div style={{color: "#64748b"}}>
                                    {snapshot["errorCount"]} errors / {snapshot["warningCount"]} warnings / {snapshot["llmTraceCount"]} traces
                                </div>
                            </div>
                            <button
                                onClick={lambda {
                                    __clearDebugEvents();
                                    setSelectedEventId(0);
                                }}
                                style={{
                                    border: "1px solid rgba(15, 23, 42, 0.12)",
                                    borderRadius: "999px",
                                    background: "white",
                                    padding: "0.35rem 0.65rem",
                                    cursor: "pointer",
                                    fontSize: "11px"
                                }}
                            >
                                Clear
                            </button>
                        </div>
                        <div
                            hidden={snapshot["llmTraceCount"] == 0}
                            style={{marginBottom: "0.4rem", fontWeight: "700"}}
                        >
                            LLM Traces
                        </div>
                        {llmTraceViews}
                        <div
                            hidden={snapshot["errorCount"] == 0}
                            style={{
                                marginTop: ("0.6rem" if snapshot["llmTraceCount"] > 0 else "0"),
                                marginBottom: "0.4rem",
                                fontWeight: "700"
                            }}
                        >
                            Errors
                        </div>
                        {errorViews}
                        <div
                            hidden={snapshot["warningCount"] == 0}
                            style={{marginTop: "0.6rem", marginBottom: "0.4rem", fontWeight: "700"}}
                        >
                            Warnings
                        </div>
                        {warningViews}
                        <div
                            hidden={snapshot["eventCount"] != 0}
                            style={{color: "#64748b", marginTop: "1rem"}}
                        >
                            No client warnings or errors captured yet.
                        </div>
                    </div>
                    <div style={detailPaneStyle}>
                        <div
                            style={{
                                display: "flex",
                                justifyContent: "space-between",
                                alignItems: "center",
                                gap: "0.75rem",
                                marginBottom: "0.9rem"
                            }}
                        >
                            <div>
                                <div style={{fontWeight: "700"}}>
                                    Trace Inspector
                                </div>
                                <div style={{color: "#64748b"}}>
                                    route: {window.location.pathname}
                                </div>
                            </div>
                            <div style={{textAlign: "right", color: "#64748b"}}>
                                <div>trace errors: {("on" if config["traceErrors"] else "off")}</div>
                                <div>feature flag: {("on" if config["featureFlag"] else "off")}</div>
                            </div>
                        </div>
                        <div hidden={selectedEvent != None}>
                            <div style={{color: "#64748b"}}>
                                Select an event to inspect its trace details.
                            </div>
                        </div>
                        <div hidden={selectedEvent == None}>
                            {selectedEvent and __renderDebugEventDetail(
                                selectedEvent,
                                config["traceErrors"]
                            )}
                        </div>
                    </div>
                </div>
            </div>
        </>
    );
}

impl errorOverlay(filePath: str, errors: str) -> JsxElement {
    return (
        <div
            style={{
                position: "fixed",
                top: 0,
                left: 0,
                width: "100%",
                height: "100%",
                background: "rgba(0, 0, 0, 0.85)",
                color: "#fff",
                fontFamily: "'Monaco', 'Menlo', 'Ubuntu Mono', monospace",
                fontSize: 14,
                zIndex: 999999,
                overflow: "auto",
                padding: 20,
                boxSizing: "border-box",

            }}
        >
            <div style={{maxWidth: 1200, margin: "0 auto"}}>
                <div
                    style={{
                        background: "#d32f2f",
                        color: "white",
                        padding: "16px 24px",
                        borderRadius: "8px 8px 0 0",
                        fontSize: 18,
                        fontWeight: "bold",

                    }}
                >
                    ⚠️ Compilation Error
                </div>
                <div
                    style={{
                        background: "#1e1e1e",
                        padding: 24,
                        borderRadius: "0 0 8px 8px",

                    }}
                >
                    <div style={{marginBottom: 16}}>
                        <div style={{color: "#888", marginBottom: 8}}>
                            File:
                        </div>
                        <div style={{color: "#64b5f6", fontWeight: "bold"}}>
                            {filePath}
                        </div>
                    </div>
                    <div>
                        <div style={{color: "#888", marginBottom: 8}}>
                            Error:
                        </div>
                        <pre
                            style={{
                                background: "#2d2d2d",
                                padding: 16,
                                borderRadius: 4,
                                overflowX: "auto",
                                margin: 0,
                                borderLeft: "4px solid #d32f2f",
                                lineHeight: 1.6,
                                color: "#ff6b6b",

                            }}
                        >
                            {errors}
                        </pre>
                    </div>
                    <div
                        style={{
                            marginTop: 24,
                            paddingTop: 16,
                            borderTop: "1px solid #444",
                            color: "#888",
                            fontSize: 13,

                        }}
                    >
                        💡 Fix the error and save the file to continue development.
                    </div>
                </div>
            </div>
        </div>
    );
}

impl useJacForm(form_mode: str, schema: any) -> any {
    return useForm(mode=form_mode, resolver=zodResolver(schema));
}

"""Auto-generated JacForm component that can render forms based on Zod schemas with built-in validation and styling.
        Props:
        - schema: Zod schema defining the form fields and validation
        - onSubmit: function to call with form data on submit
        - layout: "vertical" (default), "horizontal", "inline", or "grid"
        - field_config: dict mapping field names to {type, label, placeholder, options, rows, showPasswordToggle, className, inputClassName, labelClassName}
            - type: REQUIRED - field type ("text", "email", "password", "number", "date", "datetime-local", "checkbox", "select", "radio", "textarea", etc.)
            - label: field label (defaults to field name)
            - placeholder: placeholder text
            - options: array of options for radio buttons (e.g., ["option1", "option2"])
            - rows: number of rows for textarea (default 4)
            - showPasswordToggle: boolean - show "Show password" checkbox for password fields (default false)
            - className, inputClassName, labelClassName: CSS classes for styling
        - submitLabel: custom label for the submit button (default "Submit")
        - submitClassName: custom className for submit button
        - gridColumns: number of columns for grid layout (default 2)
        - validateMode: validation mode for react-hook-form (default "onTouched")
        - className: additional CSS class for the form element
"""
impl JacForm(props: dict) -> JsxElement {
    # Destructure props (JSX passes all props as a single object)
    schema = props.schema;
    onSubmit = props.onSubmit;
    layout = props.layout || "vertical";
    field_config = props.field_config || {};
    submitLabel = props.submitLabel || "Submit";
    submitClassName = props.submitClassName || "";
    gridColumns = props.gridColumns || 2;
    validateMode = props.validateMode || "onTouched";
    className = props.className || "";
    # Extract field names from schema
    # Handle ZodEffects (schemas with .refine()) by unwrapping
    actualSchema = schema;
    try {
        if schema._def and schema._def.schema {
            # This is a ZodEffects, unwrap to get the base schema
            actualSchema = schema._def.schema;
        }
    } except Exception as e {
        console.warn("Failed to unwrap schema:", e);
    }
    schemaShape = actualSchema.shape || {};
    fieldNames = Object.keys(schemaShape);
    # Initialize form with the original schema (not the unwrapped one)
    form = useJacForm(validateMode, schema);
    errors = form.formState.errors;
    isSubmitting = form.formState.isSubmitting;
    isDirty = form.formState.isDirty;
    # # State for password visibility (separate state for each field)
    [passwordVisible, setPasswordVisible] = useState({});
    # Helper function to recursively unwrap Zod wrapper types
    def unwrapZodSchema(schema: any, depth: int = 0) -> any {
        maxDepth = 10;  # Prevent infinite recursion
        if not schema._def or depth >= maxDepth {
            return schema;
        }

        typeValue = schema._def.type;

        # Unwrap ZodOptional (.optional())
        if typeValue == "optional" and schema._def.innerType {
            return unwrapZodSchema(schema._def.innerType, depth + 1);
        }

        # Unwrap ZodDefault (.default())
        if typeValue == "default" and schema._def.innerType {
            return unwrapZodSchema(schema._def.innerType, depth + 1);
        }

        # Unwrap ZodEffects (.refine(), .transform(), etc.)
        if schema._def.checks and schema._def.schema {
            return unwrapZodSchema(schema._def.schema, depth + 1);
        }

        # Base case: not a wrapper type
        return schema;
    }
    # Helper: Render error message
    def renderError(error: any) -> JsxElement | None {
        if not error {
            return None;
        }
        return (
            <p style={{color: "#ef4444", fontSize: "0.85rem", marginTop: "0.25rem"}}>
                ⚠️{error.message}
            </p>
        );
    }
    # Helper: Extract enum options from schema
    def getEnumOptions(fieldSchema: any) -> list {
        unwrapped = unwrapZodSchema(fieldSchema);
        if unwrapped._def and unwrapped._def.entries {
            return Object.keys(unwrapped._def.entries);
        } elif unwrapped.def and unwrapped.def.entries {
            return Object.keys(unwrapped.def.entries);
        }
        return [];
    }
    # Helper: Render the actual input element based on type
    def renderInput(
        fieldType: str,
        field: any,
        error: any,
        config: dict,
        fieldSchema: any,
        fieldName: str
    ) -> JsxElement {
        inputClassName = config.inputClassName or "";
        labelClassName = config.labelClassName or "";
        placeholder = config.placeholder or "";
        label = config.label or fieldName;

        # Checkbox
        if fieldType == "checkbox" {
            watchValue = form.watch(fieldName);
            return (
                <label
                    style={{
                        cursor: "pointer",
                        display: "flex",
                        alignItems: "center",
                        gap: "0.5rem"
                    }}
                >
                    <input
                        type="checkbox"
                        name={field.name}
                        ref={field.ref}
                        onChange={field.onChange}
                        onBlur={field.onBlur}
                        checked={watchValue || False}
                        className={inputClassName}
                        style={{cursor: "pointer"}}
                    />
                    <span className={labelClassName}>
                        {label}
                    </span>
                </label>
            );
        }

        # Select dropdown
        if fieldType == "select" {
            options = getEnumOptions(fieldSchema);
            watchValue = form.watch(fieldName);
            return (
                <select
                    name={field.name}
                    ref={field.ref}
                    onChange={field.onChange}
                    onBlur={field.onBlur}
                    value={watchValue || ""}
                    className={inputClassName}
                    style={{width: "100%", boxSizing: "border-box"}}
                >
                    <option value="">
                        {placeholder or f"Select {label}"}
                    </option>
                    {options.map(
                        lambda opt: any -> JsxElement { return
                            <option value={opt} key={opt}>
                                {opt}
                            </option>; }
                    )}
                </select>
            );
        }

        # Radio buttons
        if fieldType == "radio" {
            options = getEnumOptions(fieldSchema);
            watchValue = form.watch(fieldName);
            return (
                <div style={{display: "flex", flexDirection: "column", gap: "0.5rem"}}>
                    {options.map(
                        lambda opt: any -> JsxElement { return (
                            <label
                                key={opt}
                                style={{
                                    cursor: "pointer",
                                    display: "flex",
                                    alignItems: "center",
                                    gap: "0.5rem"
                                }}
                            >
                                <input
                                    type="radio"
                                    name={field.name}
                                    value={opt}
                                    ref={field.ref}
                                    onChange={field.onChange}
                                    onBlur={field.onBlur}
                                    checked={watchValue == opt}
                                    className={inputClassName}
                                    style={{cursor: "pointer"}}
                                />
                                <span>
                                    {opt}
                                </span>
                            </label>
                        ); }
                    )}
                </div>
            );
        }

        # Textarea
        if fieldType == "textarea" {
            rows = config.rows or 4;
            return (
                <textarea
                    placeholder={placeholder}
                    rows={rows}
                    {...field}
                    className={inputClassName}
                    style={{
                        width: "100%",
                        boxSizing: "border-box",
                        border: ("2px solid #ef4444" if error else "2px solid #e5e7eb"),
                        padding: "0.5rem",
                        fontFamily: "inherit",
                        fontSize: "inherit",
                        resize: "vertical"
                    }}
                />
            );
        }

        # Regular input (text, email, password, number, date, datetime-local, tel, url, etc.)
        # Special handling for password fields with visibility toggle
        if fieldType == "password" and config.showPasswordToggle {
            isVisible = passwordVisible[fieldName] || False;
            return (
                <div>
                    <div style={{position: "relative"}}>
                        <input
                            type={"text" if isVisible else "password"}
                            placeholder={placeholder}
                            {...field}
                            className={inputClassName}
                            style={{
                                width: "100%",
                                boxSizing: "border-box",
                                border: (
                                    "2px solid #ef4444"
                                        if error
                                        else "2px solid #e5e7eb"
                                ),
                                paddingRight: "2.5rem"
                            }}
                        />
                    </div>
                    <label
                        style={{
                            cursor: "pointer",
                            display: "flex",
                            alignItems: "center",
                            gap: "0.5rem",
                            marginTop: "0.5rem",
                            fontSize: "0.875rem",
                            color: "#6b7280"
                        }}
                    >
                        <input
                            type="checkbox"
                            checked={isVisible}
                            onChange={lambda e: any { setPasswordVisible(
                                lambda prev: any -> dict { newState = Object.assign(
                                    {}, prev
                                );newState[fieldName] = not isVisible;return newState; }
                            );}}
                            style={{cursor: "pointer"}}
                        />
                        <span>
                            Show password
                        </span>
                    </label>
                </div>
            );
        }

        # Regular input without toggle
        return (
            <input
                type={fieldType}
                placeholder={placeholder}
                {...field}
                className={inputClassName}
                style={{
                    width: "100%",
                    boxSizing: "border-box",
                    border: ("2px solid #ef4444" if error else "2px solid #e5e7eb")
                }}
            />
        );
    }
    # Main field renderer
    def renderField(fieldName: str) -> JsxElement {
        fieldSchema = schemaShape[fieldName];
        config = field_config[fieldName] if field_config[fieldName] else {};

        # Note: "type" gets compiled to "key" in JavaScript to avoid conflicts with React's type prop
        fieldType = config.key or "text";
        label = config.label or fieldName;
        fieldClassName = config.className or "";
        labelClassName = config.labelClassName or "";

        # Register field and get error state
        # valueAsNumber: true is required for number fields because <input type="number">
        registerOptions = {"valueAsNumber": True} if fieldType == "number" else {};
        field = form.register(fieldName, registerOptions);
        error = errors[fieldName];

        # Render: wrapper > input > error
        return (
            <div
                className={fieldClassName}
                style={{marginBottom: "1rem"}}
                key={fieldName}
            >
                <label
                    className={labelClassName}
                    style={{display: "block", marginBottom: "0.5rem"}}
                >
                    {label}
                </label>
                {renderInput(fieldType, field, error, config, fieldSchema, fieldName)}
                {renderError(error)}
            </div>
        );
    }
    # Generate layout styles based on layout prop
    def getLayoutStyle -> dict {
        if layout == "grid" {
            return {
                display: "grid",
                gridTemplateColumns: f"repeat({gridColumns}, 1fr)",
                gap: "1rem"
            };
        } elif layout == "horizontal" {
            return {
                display: "flex",
                gap: "1rem",
                flexWrap: "wrap",
                alignItems: "flex-start"
            };
        } elif layout == "inline" {
            return {display: "flex", gap: "0.5rem", alignItems: "flex-end"};
        } else {
            # vertical (default)
            return {};
        }
    }
    # Render all fields
    fields = [];
    for fieldName in fieldNames {
        fields.push(renderField(fieldName));
    }
    layoutStyle = getLayoutStyle();
    formClassName = className or "";
    buttonClassName = submitClassName or "";
    return (
        <form onSubmit={form.handleSubmit(onSubmit)} className={formClassName}>
            <div style={layoutStyle}>
                {fields}
            </div>
            <button
                type="submit"
                disabled={isSubmitting or not isDirty}
                className={buttonClassName}
                style={{
                    width: "100%",
                    cursor: (
                        "not-allowed" if (isSubmitting or not isDirty) else "pointer"
                    )
                }}
            >
                {isSubmitting and "Submitting..."}{not isSubmitting and submitLabel}
            </button>
        </form>
    );
}

# ============================================================================
# Client Error Reporting
# ============================================================================
"""Report a client-side error to the server via POST /cl/__error__.
Fires asynchronously and silently ignores failures (to avoid error loops).
"""
impl __jacReportError(
    message: str, stack: str = "", url: str = "", source: str = ""
) -> None {
    try {
        baseUrl = __getApiBaseUrl();
        fetch(
            f"{baseUrl}/cl/__error__",
            {
                "method": "POST",
                "headers": {"Content-Type": "application/json"},
                "body": JSON.stringify(
                    {
                        "message": message,
                        "stack": stack,
                        "url": url or window.location.href,
                        "source": source,
                        "timestamp": Reflect.construct(Date, []).toISOString()
                    }
                )
            }
        );
    } except Exception {
    # Intentionally silent - error reporting must never throw, as that
    # could cause infinite loops or mask the original error.
    }
}

"""Install global error handlers to catch unhandled JS errors and rejections.
Called once during app initialization.
"""
impl __jacInstallErrorHandlers -> None {
    __installDebugConsoleHooks();
    if window.__jacErrorHandlersInstalled {
        return;
    }
    window.__jacErrorHandlersInstalled = True;
    # Catch synchronous errors (e.g., TypeError, ReferenceError)
    window.addEventListener(
        "error",
        lambda event: Any {
            message = event.message or "Unknown error";
            stack = event.error.stack if event.error else "";
            __recordDebugEvent("error", "window.onerror", message, stack);
            __jacReportError(
                message,
                stack,
                event.filename or "",
                "window.onerror"
            );
        }
    );
    # Catch unhandled promise rejections (e.g., failed fetch, async errors)
    window.addEventListener(
        "unhandledrejection",
        lambda event: Any {
            reason = event.reason;
            message = "";
            stack = "";
            if reason {
                message = reason.message or str(reason);
                stack = reason.stack or "";
            } else {
                message = "Unhandled promise rejection";
            }
            __recordDebugEvent(
                "error",
                "unhandledrejection",
                message,
                stack
            );
            __jacReportError(message, stack, "", "unhandledrejection");
        }
    );
}
