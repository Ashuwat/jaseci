"""Focused tests for raise-guard type narrowing.

These cases mirror the assert-based narrowing fixture, but use an early-exit
raise guard instead. They should type-check cleanly once raise-based fallthrough
narrowing is implemented.
"""

obj Program {
    has mtir_map: dict[str, str] = {};
}

obj Runtime {
    has program: Program | None = None;
}

def use_program(p: Program) -> dict[str, str] {
    return p.mtir_map;
}

# Baseline: assert narrowing already works for the same shape.
def test_assert_guard_attr(rt: Runtime) -> dict[str, str] {
    assert rt.program is not None;
    return rt.program.mtir_map;
}

# Raise guard should narrow the fallthrough path the same way assert does.
def test_raise_guard_attr(rt: Runtime) -> dict[str, str] {
    if rt.program is None {
        raise ValueError("missing program");
    }
    return rt.program.mtir_map;
}

def test_raise_guard_method_call(rt: Runtime) -> dict[str, str] {
    if rt.program is None {
        raise RuntimeError("runtime not loaded");
    }
    return use_program(rt.program);
}

def test_raise_guard_multiple_uses(rt: Runtime) -> str {
    if rt.program is None {
        raise ValueError("missing program");
    }
    data = rt.program.mtir_map;
    return str(len(data));
}

def test_raise_guard_elif(rt: Runtime, key: str) -> str {
    if rt.program is None {
        raise ValueError("missing program");
    } elif key == "" {
        raise ValueError("missing key");
    }
    return rt.program.mtir_map.get(key, "");
}

test "raise guard narrowing works in test blocks" {
    program: Program | None = Program();
    if program is None {
        raise ValueError("missing program");
    }
    program.mtir_map;
}
