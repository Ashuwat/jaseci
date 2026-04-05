"""Minimal browser app following the docs full-stack pattern."""

cl {
    def:pub app() -> JsxElement {
        return <main style={{
            "minHeight": "100vh",
            "display": "grid",
            "placeItems": "center",
            "fontFamily": "system-ui, sans-serif",
            "background": "#f8fafc"
        }}>
            <section style={{
                "padding": "2rem 2.5rem",
                "borderRadius": "18px",
                "background": "white",
                "boxShadow": "0 10px 30px rgba(15, 23, 42, 0.08)",
                "textAlign": "center"
            }}>
                <h1 style={{
                    "margin": "0 0 0.5rem 0",
                    "fontSize": "3rem",
                    "color": "#0f172a"
                }}>
                    Hello, World!
                </h1>
                <p style={{
                    "margin": "0",
                    "fontSize": "1rem",
                    "color": "#475569"
                }}>
                    This page is rendered from Jac at <code>/cl/app</code>.
                </p>
            </section>
        </main>;
    }
}
