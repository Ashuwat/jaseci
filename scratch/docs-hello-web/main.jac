"""Small web LLM playground for exercising the debug panel."""

import from byllm.lib { Model }

glob configured_llm = Model(model_name="gpt-4o-mini"),
     broken_llm = Model(model_name="openai/not-a-real-model"),
     mock_llm = Model(
         model_name="mockllm",
         config={
             "outputs": [
                 "Mock mode says hello from Jac.",
                 "Mock mode summarized your request without leaving localhost.",
                 "Mock mode generated another answer for the trace viewer.",
                 "Mock mode is useful when you want prompt visibility without provider setup.",
                 "Mock mode exhausted fewer assumptions than a real provider call."
             ]
         }
     );

def run_configured_llm(prompt: str) -> str by configured_llm();
def run_broken_llm(prompt: str) -> str by broken_llm();
def run_mock_llm(prompt: str) -> str by mock_llm();

def:pub ask_configured_llm(prompt: str) -> str {
    return run_configured_llm(prompt);
}

def:pub ask_broken_llm(prompt: str) -> str {
    return run_broken_llm(prompt);
}

def:pub ask_mock_llm(prompt: str) -> str {
    return run_mock_llm(prompt);
}

cl {
    def:pub app() -> JsxElement {
        has prompt: str = "Write a two-sentence welcome for the Jac debug panel.",
            output: str = "",
            statusText: str = "Ready",
            isLoading: bool = False,
            lastMode: str = "",
            helperText: str = "Configured model calls surface prompt, tokens, latency, and provider errors in the panel.";

        def resetRun(mode: str, helper: str) {
            isLoading = True;
            lastMode = mode;
            statusText = "Running...";
            helperText = helper;
            output = "";
        }

        def finishRun(message: str) {
            isLoading = False;
            statusText = message;
        }

        async def askConfigured {
            resetRun(
                "Configured model",
                "If your provider is configured, the debug panel will show the exact prompt, token usage, call count, and final response."
            );
            try {
                output = await ask_configured_llm(prompt.trim());
                finishRun("Configured model finished.");
            } except Exception as e {
                output = String(e);
                finishRun("Configured model failed. Open the debug panel for the trace.");
            }
        }

        async def askBroken {
            resetRun(
                "Broken model",
                "This intentionally uses a bad model id so the debug panel has a predictable LLM failure to inspect."
            );
            try {
                output = await ask_broken_llm(prompt.trim());
                finishRun("Broken model unexpectedly succeeded.");
            } except Exception as e {
                output = String(e);
                finishRun("Broken model failed as expected. Inspect the red trace entry.");
            }
        }

        async def askMock {
            resetRun(
                "Mock model",
                "Mock mode runs locally and still emits the agent-level LLM trace, which is useful when you do not want to depend on an external provider."
            );
            try {
                output = await ask_mock_llm(prompt.trim());
                finishRun("Mock model finished.");
            } except Exception as e {
                output = String(e);
                finishRun("Mock model failed.");
            }
        }

        return
            <main
                style={{
                    "minHeight": "100vh",
                    "padding": "3rem 1.5rem 6rem 1.5rem",
                    "fontFamily": "system-ui, sans-serif",
                    "background": "linear-gradient(160deg, #eff6ff 0%, #f8fafc 55%, #fff7ed 100%)",
                    "color": "#0f172a"
                }}
            >
                <section
                    style={{
                        "maxWidth": "980px",
                        "margin": "0 auto",
                        "display": "grid",
                        "gap": "1.25rem"
                    }}
                >
                    <div
                        style={{
                            "padding": "1.5rem",
                            "borderRadius": "24px",
                            "background": "rgba(255,255,255,0.86)",
                            "backdropFilter": "blur(18px)",
                            "border": "1px solid rgba(148,163,184,0.18)",
                            "boxShadow": "0 20px 50px rgba(15, 23, 42, 0.10)"
                        }}
                    >
                        <div
                            style={{
                                "display": "flex",
                                "justifyContent": "space-between",
                                "gap": "1rem",
                                "flexWrap": "wrap",
                                "marginBottom": "1rem"
                            }}
                        >
                            <div>
                                <div
                                    style={{
                                        "display": "inline-block",
                                        "padding": "0.35rem 0.7rem",
                                        "borderRadius": "999px",
                                        "background": "#dbeafe",
                                        "color": "#1d4ed8",
                                        "fontSize": "0.8rem",
                                        "fontWeight": "700",
                                        "letterSpacing": "0.04em",
                                        "textTransform": "uppercase",
                                        "marginBottom": "0.75rem"
                                    }}
                                >
                                    LLM Trace Playground
                                </div>
                                <h1
                                    style={{
                                        "margin": "0 0 0.55rem 0",
                                        "fontSize": "3rem",
                                        "lineHeight": "1.05"
                                    }}
                                >
                                    Exercise prompts, errors, and LLM trace detail.
                                </h1>
                                <p
                                    style={{
                                        "margin": "0",
                                        "maxWidth": "58ch",
                                        "color": "#475569",
                                        "fontSize": "1rem"
                                    }}
                                >
                                    Use the actions below, then open the bottom-right debug panel.
                                    Successful configured calls should show prompt, tokens, cost, latency,
                                    and the per-call payload. Broken calls should show the full failure path.
                                </p>
                            </div>
                            <div
                                style={{
                                    "minWidth": "220px",
                                    "padding": "1rem",
                                    "borderRadius": "18px",
                                    "background": "#0f172a",
                                    "color": "#e2e8f0"
                                }}
                            >
                                <div style={{"fontSize": "0.8rem", "textTransform": "uppercase", "letterSpacing": "0.05em", "color": "#93c5fd"}}>
                                    Current run
                                </div>
                                <div style={{"fontSize": "1.15rem", "fontWeight": "700", "marginTop": "0.4rem"}}>
                                    {lastMode or "None yet"}
                                </div>
                                <div style={{"marginTop": "0.55rem", "color": "#cbd5e1"}}>
                                    {statusText}
                                </div>
                            </div>
                        </div>

                        <label
                            style={{
                                "display": "block",
                                "fontWeight": "700",
                                "marginBottom": "0.6rem"
                            }}
                        >
                            Prompt
                        </label>
                        <textarea
                            value={prompt}
                            onChange={lambda e: Any { prompt = e.target.value;}}
                            rows={5}
                            style={{
                                "width": "100%",
                                "padding": "1rem",
                                "borderRadius": "18px",
                                "border": "1px solid #cbd5e1",
                                "background": "#ffffff",
                                "fontSize": "1rem",
                                "lineHeight": "1.5",
                                "resize": "vertical",
                                "boxSizing": "border-box"
                            }}
                        />

                        <div
                            style={{
                                "display": "flex",
                                "gap": "0.75rem",
                                "flexWrap": "wrap",
                                "marginTop": "1rem"
                            }}
                        >
                            <button
                                onClick={lambda { askConfigured();}}
                                disabled={isLoading or not prompt.trim()}
                                style={{
                                    "padding": "0.9rem 1.2rem",
                                    "borderRadius": "14px",
                                    "border": "none",
                                    "background": "#2563eb",
                                    "color": "white",
                                    "fontWeight": "700",
                                    "cursor": "pointer",
                                    "opacity": (0.65 if isLoading else 1)
                                }}
                            >
                                Run Configured Model
                            </button>
                            <button
                                onClick={lambda { askBroken();}}
                                disabled={isLoading or not prompt.trim()}
                                style={{
                                    "padding": "0.9rem 1.2rem",
                                    "borderRadius": "14px",
                                    "border": "none",
                                    "background": "#dc2626",
                                    "color": "white",
                                    "fontWeight": "700",
                                    "cursor": "pointer",
                                    "opacity": (0.65 if isLoading else 1)
                                }}
                            >
                                Trigger LLM Error
                            </button>
                            <button
                                onClick={lambda { askMock();}}
                                disabled={isLoading or not prompt.trim()}
                                style={{
                                    "padding": "0.9rem 1.2rem",
                                    "borderRadius": "14px",
                                    "border": "1px solid #cbd5e1",
                                    "background": "white",
                                    "color": "#0f172a",
                                    "fontWeight": "700",
                                    "cursor": "pointer",
                                    "opacity": (0.65 if isLoading else 1)
                                }}
                            >
                                Run Mock Model
                            </button>
                        </div>
                    </div>

                    <div
                        style={{
                            "display": "grid",
                            "gridTemplateColumns": "repeat(auto-fit, minmax(220px, 1fr))",
                            "gap": "1rem"
                        }}
                    >
                        <article
                            style={{
                                "padding": "1rem 1.1rem",
                                "borderRadius": "20px",
                                "background": "rgba(255,255,255,0.9)",
                                "border": "1px solid rgba(148,163,184,0.16)"
                            }}
                        >
                            <h2 style={{"margin": "0 0 0.45rem 0", "fontSize": "1rem"}}>
                                Configured model
                            </h2>
                            <p style={{"margin": "0", "color": "#475569"}}>
                                Uses your provider config. This is the path that should show prompt,
                                tokens, latency, cost, and full call payloads in the debug panel.
                            </p>
                        </article>
                        <article
                            style={{
                                "padding": "1rem 1.1rem",
                                "borderRadius": "20px",
                                "background": "rgba(255,255,255,0.9)",
                                "border": "1px solid rgba(148,163,184,0.16)"
                            }}
                        >
                            <h2 style={{"margin": "0 0 0.45rem 0", "fontSize": "1rem"}}>
                                Broken model
                            </h2>
                            <p style={{"margin": "0", "color": "#475569"}}>
                                Purposely points at a bad model id so the panel has a deterministic
                                LLM error to inspect.
                            </p>
                        </article>
                        <article
                            style={{
                                "padding": "1rem 1.1rem",
                                "borderRadius": "20px",
                                "background": "rgba(255,255,255,0.9)",
                                "border": "1px solid rgba(148,163,184,0.16)"
                            }}
                        >
                            <h2 style={{"margin": "0 0 0.45rem 0", "fontSize": "1rem"}}>
                                Mock model
                            </h2>
                            <p style={{"margin": "0", "color": "#475569"}}>
                                Works without any external API key. It still gives you a browser-side
                                LLM trace entry, but it will not have provider token accounting.
                            </p>
                        </article>
                    </div>

                    <section
                        style={{
                            "padding": "1.35rem",
                            "borderRadius": "22px",
                            "background": "#ffffff",
                            "border": "1px solid rgba(148,163,184,0.16)",
                            "boxShadow": "0 10px 30px rgba(15, 23, 42, 0.06)"
                        }}
                    >
                        <div style={{"fontWeight": "700", "marginBottom": "0.5rem"}}>
                            What to look for in the debug panel
                        </div>
                        <p style={{"margin": "0 0 0.8rem 0", "color": "#475569"}}>
                            {helperText}
                        </p>
                        <pre
                            style={{
                                "margin": "0",
                                "padding": "1rem",
                                "borderRadius": "16px",
                                "background": "#0f172a",
                                "color": "#e2e8f0",
                                "whiteSpace": "pre-wrap",
                                "wordBreak": "break-word",
                                "minHeight": "140px"
                            }}
                        >
                            {output or "The most recent response or error will show up here after you run a prompt."}
                        </pre>
                    </section>
                </section>
            </main>;
    }
}
