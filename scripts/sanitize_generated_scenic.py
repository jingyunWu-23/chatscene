#!/usr/bin/env python3
"""Patch generated Scenic files for SafeBench compatibility."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


DEFAULT_SCENIC_DIR = (
    Path(__file__).resolve().parents[1]
    / "safebench"
    / "scenario"
    / "scenario_data"
    / "scenic_data"
    / "dynamic_scenario"
)

LANE_ASSIGN_RE = re.compile(
    r"^(?P<indent>\s*)(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(?P<base>.+?)(?P<side>\._laneTo(?:Left|Right))\.lane(?P<tail>\s*(?:#.*)?)$"
)


def sanitize_text(text: str) -> str:
    lines = text.splitlines()
    output = []
    changed = False
    for line in lines:
        match = LANE_ASSIGN_RE.match(line)
        if not match:
            output.append(line)
            continue

        indent = match.group("indent")
        target = match.group("target")
        base = match.group("base").strip()
        side = match.group("side")
        tail = match.group("tail")
        section_var = f"{target}Sec"

        output.append(f"{indent}{section_var} = {base}{side}{tail}")
        output.append(f"{indent}require {section_var} is not None")
        output.append(f"{indent}{target} = {section_var}.lane")
        changed = True

    result = "\n".join(output)
    if text.endswith("\n"):
        result += "\n"
    return result if changed else text


def sanitize_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    sanitized = sanitize_text(text)
    if sanitized == text:
        return False
    path.write_text(sanitized, encoding="utf-8")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenic-dir", default=str(DEFAULT_SCENIC_DIR))
    parser.add_argument("--recursive", action="store_true", help="Patch .scenic files below scenic-dir recursively.")
    parser.add_argument("--check", action="store_true", help="Report files which would change without writing.")
    args = parser.parse_args()

    scenic_dir = Path(args.scenic_dir).expanduser().resolve()
    files = sorted(scenic_dir.rglob("*.scenic") if args.recursive else scenic_dir.glob("*.scenic"))
    changed = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        sanitized = sanitize_text(text)
        if sanitized == text:
            continue
        changed.append(path)
        if not args.check:
            path.write_text(sanitized, encoding="utf-8")

    for path in changed:
        print(path)
    if args.check and changed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
