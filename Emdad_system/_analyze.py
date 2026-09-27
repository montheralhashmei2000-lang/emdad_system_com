"""Ad-hoc structural comparison (temporary; deleted after use)."""
import ast
import io
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))


def members(path):
    """Return (classes, functions, methods-per-class, imports) for a .py file."""
    src = io.open(path, encoding="utf-8-sig").read()
    classes, funcs, meths, imports = [], [], {}, []
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return None, None, None, f"SYNTAX ERROR: {e}"
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            classes.append(node.name)
            meths[node.name] = [n.name for n in node.body
                                if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            funcs.append(node.name)
        elif isinstance(node, ast.ImportFrom):
            imports.append("." * node.level + (node.module or ""))
        elif isinstance(node, ast.Import):
            imports.extend(a.name for a in node.names)
    return classes, funcs, meths, imports


def brief(path):
    c, f, m, imp = members(path)
    if c is None:
        return f"!! {imp}"
    nlines = len(io.open(path, encoding="utf-8").read().splitlines())
    nmeth = sum(len(v) for v in m.values())
    return (f"lines={nlines:<5} classes={len(c):<3} funcs={len(f):<3} "
            f"methods={nmeth:<4}")


names = sorted(set(
    [f[:-3] for f in os.listdir("views") if f.endswith(".py")] +
    [f[:-3] for f in os.listdir("ui/views") if f.endswith(".py")]))

print(f"{'screen':<32} {'ROOT views/':<42} {'ui/views/':<42} verdict")
print("-" * 130)
for n in names:
    rp = os.path.join("views", n + ".py")
    up = os.path.join("ui", "views", n + ".py")
    rc, rf, rm, rimp = (members(rp) if os.path.exists(rp) else ([], [], {}, "MISSING"))
    uc, uf, um, uimp = (members(up) if os.path.exists(up) else ([], [], {}, "MISSING"))
    rex = os.path.exists(rp)
    uex = os.path.exists(up)

    def score(classes, funcs, meths):
        if not isinstance(classes, list):
            return -1
        return len(classes) * 10 + len(funcs) + sum(len(v) for v in meths.values())

    rs, us = score(rc, rf, rm), score(uc, uf, um)
    if not rex and not uex:
        continue
    if rex and not uex:
        verdict = "only in root views/  -> needs copy to ui/"
    elif uex and not rex:
        verdict = "only in ui/views/   (ui-only, keep)"
    else:
        if rs > us:
            verdict = f"ROOT is richer by {rs-us}  -> replace ui/ with root"
        elif us > rs:
            verdict = f"ui/ is richer by {us-rs}  -> keep ui/ as-is"
        else:
            verdict = "structural tie (import-style only)"

    print(f"{n:<32} {brief(rp) if rex else '-- MISSING --':<42} "
          f"{brief(up) if uex else '-- MISSING --':<42} {verdict}")

print()
print("=" * 130)
print("EXTRA: root main_window vs ui main_window (which one does main.py use?)")
print("=" * 130)
print(io.open("main.py", encoding="utf-8").read().count("ui.main_window") and
      "main.py -> ui.main_window  (ui/ tree is the LIVE tree)")
