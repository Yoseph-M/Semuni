#!/usr/bin/env python3
"""Phase 9 evidence tool: reconcile the Flutter API client against NestJS routes.

Reads every HTTP call made by lib/services/api/*.dart and every route declared by
backend/src/**/*.controller.ts, then reports:

  * client calls with no matching backend route  (broken runtime path)
  * backend routes never called by the client    (unused surface)

Run from the repository root:  python3 backend/tools/phase9-endpoint-reconciliation.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

CLIENT_CALL = re.compile(r"\.(get|post|patch|put|delete)\(")
STRING_LITERAL = re.compile(r"'(/[^']*)'|\"(/[^\"]*)\"")
CONTROLLER = re.compile(r"@Controller\(\s*'([^']*)'\s*\)")
ROUTE_DECORATOR = re.compile(r"@(Get|Post|Patch|Put|Delete|All)\(\s*(?:'([^']*)')?\s*\)")

METHODS = {"get": "GET", "post": "POST", "patch": "PATCH", "put": "PUT", "delete": "DELETE"}


def norm(path: str) -> str:
    """Collapse interpolated ids and query strings so paths compare equal."""
    path = path.split("?", 1)[0]
    path = re.sub(r"\$\{[^}]*\}", "{id}", path)
    path = re.sub(r"\$[A-Za-z_][A-Za-z0-9_]*", "{id}", path)
    path = re.sub(r":[A-Za-z_][A-Za-z0-9_]*", "{id}", path)
    path = re.sub(r"\{[^}]*\}", "{id}", path)
    path = "/" + path.strip("/")
    return path.rstrip("/") or "/"


def client_endpoints() -> set[tuple[str, str]]:
    found: set[tuple[str, str]] = set()
    for dart in sorted((ROOT / "lib" / "services" / "api").glob("*.dart")):
        lines = dart.read_text().splitlines()
        for index, line in enumerate(lines):
            for match in CLIENT_CALL.finditer(line):
                method = METHODS[match.group(1)]
                # The concrete path may be on this line or the next few.
                for offset in range(0, 4):
                    if index + offset >= len(lines):
                        break
                    literal = STRING_LITERAL.search(lines[index + offset])
                    if literal:
                        raw = literal.group(1) or literal.group(2)
                        found.add((method, norm(raw)))
                        break
    return found


def server_endpoints() -> set[tuple[str, str]]:
    found: set[tuple[str, str]] = set()
    for controller in sorted((ROOT / "backend" / "src").rglob("*.controller.ts")):
        text = controller.read_text()
        prefix = CONTROLLER.search(text)
        base = norm(prefix.group(1)) if prefix else "/"
        for decorator in ROUTE_DECORATOR.finditer(text):
            verb = decorator.group(1).upper()
            sub = decorator.group(2) or ""
            verb = "GET" if verb == "ALL" else verb
            found.add((verb, norm(f"{base}/{sub}")))
    return found


def main() -> int:
    client = client_endpoints()
    server = server_endpoints()

    # main.ts sets the global prefix 'api/v1'; controllers declare the rest.
    global_prefix = norm("/api/v1")
    server_no_prefix = {
        (verb, path[len(global_prefix):] if path.startswith(global_prefix) else path)
        for verb, path in server
    }

    missing = sorted(client - server_no_prefix)
    unused = sorted(server_no_prefix - client)

    print(f"client endpoints: {len(client)}")
    print(f"server endpoints: {len(server_no_prefix)}")
    print()

    print("client calls with NO backend route:")
    if not missing:
        print("  (none)")
    for verb, path in missing:
        print(f"  {verb} {path}")
    print()

    print("backend routes not called by lib/services/api:")
    if not unused:
        print("  (none)")
    for verb, path in unused:
        print(f"  {verb} {path}")

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
