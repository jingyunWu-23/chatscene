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
    r"(?P<base>.+?)(?P<side>\._[A-Za-z0-9]*Lane)\.lane(?P<tail>\s*(?:#.*)?)$"
)
SPLIT_LANE_ASSIGN_RE = re.compile(
    r"^(?P<indent>\s*)(?P<section>[A-Za-z_][A-Za-z0-9_]*Sec)\s*=\s*"
    r"(?P<base>.+?)(?P<side>\._laneTo(?:Left|Right))(?P<tail>\s*(?:#.*)?)$"
)
SECTION_LANE_ASSIGN_RE = re.compile(
    r"^(?P<indent>\s*)(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(?P<section>[A-Za-z_][A-Za-z0-9_]*(?:Sec|Section))\.lane(?P<tail>\s*(?:#.*)?)$"
)
REGION_SECTION_LANE_RE = re.compile(
    r"^(?P<indent>\s*)with regionContainedIn "
    r"(?P<section>[A-Za-z_][A-Za-z0-9_]*(?:Sec|Section))\.lane(?P<tail>\s*,?\s*(?:#.*)?)$"
)


def opposite_side(side: str) -> str:
    return "._laneToLeft" if side == "._laneToRight" else "._laneToRight"


def append_lane_section_assignment(output, indent, section_var, base, side, tail):
    output.append(f"{indent}{section_var} = {base}{side}{tail}")
    if side in ("._laneToLeft", "._laneToRight"):
        output.append(f"{indent}if {section_var} is None:")
        output.append(f"{indent}    {section_var} = {base}{opposite_side(side)}")
    output.append(f"{indent}if {section_var} is None:")
    output.append(f"{indent}    {section_var} = {base}")
    output.append(f"{indent}require {section_var} is not None")


def sanitize_text(text: str) -> str:
    lines = text.splitlines()
    output = []
    changed = False
    i = 0
    while i < len(lines):
        line = lines[i]
        region_match = REGION_SECTION_LANE_RE.match(line)
        if region_match:
            output.append(
                f"{region_match.group('indent')}with regionContainedIn "
                f"{region_match.group('section')}{region_match.group('tail')}"
            )
            changed = True
            i += 1
            continue

        split_match = SPLIT_LANE_ASSIGN_RE.match(line)
        if split_match:
            indent = split_match.group("indent")
            section_var = split_match.group("section")
            base = split_match.group("base").strip()
            side = split_match.group("side")
            tail = split_match.group("tail")
            append_lane_section_assignment(output, indent, section_var, base, side, tail)
            changed = True
            i += 1
            while i < len(lines):
                stripped = lines[i].strip()
                if stripped == f"if {section_var} is None:":
                    i += 1
                    while i < len(lines) and lines[i].startswith(f"{indent}    "):
                        i += 1
                    continue
                if stripped == f"require {section_var} is not None":
                    i += 1
                    continue
                break
            continue

        section_lane_match = SECTION_LANE_ASSIGN_RE.match(line)
        if section_lane_match:
            output.append(
                f"{section_lane_match.group('indent')}{section_lane_match.group('target')} = "
                f"{section_lane_match.group('section')}{section_lane_match.group('tail')}"
            )
            changed = True
            i += 1
            continue

        if output and output[-1].lstrip().startswith("require "):
            required_var = output[-1].strip().split()[1]
            if line.strip() == f"require {required_var} is not None":
                changed = True
                i += 1
                continue

        match = LANE_ASSIGN_RE.match(line)
        if not match:
            output.append(line)
            i += 1
            continue

        indent = match.group("indent")
        target = match.group("target")
        base = match.group("base").strip()
        side = match.group("side")
        tail = match.group("tail")
        section_var = f"{target}Sec"

        append_lane_section_assignment(output, indent, section_var, base, side, tail)
        output.append(f"{indent}{target} = {section_var}")
        changed = True
        i += 1

    result = "\n".join(output)
    if text.endswith("\n"):
        result += "\n"
    return result if changed else text


def sanitize_file(path: Path) -> bool:
    path = Path(path)
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
