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
LANE_SECTION_AT_EGO_RE = re.compile(
    r"^(?P<indent>\s*)(?P<section>[A-Za-z_][A-Za-z0-9_]*(?:Sec|Section))\s*=\s*"
    r"network\.laneSectionAt\(ego\)(?P<tail>\s*(?:#.*)?)$"
)
SECTION_ALIAS_ASSIGN_RE = re.compile(
    r"^(?P<indent>\s*)(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(?P<section>[A-Za-z_][A-Za-z0-9_]*(?:Sec|Section))(?P<tail>\s*(?:#.*)?)$"
)
ORIENTATION_ACCESS_RE = re.compile(
    r"^(?P<indent>\s*)(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(?P<obj>[A-Za-z_][A-Za-z0-9_]*)\.orientation\["
)
UNIFORM_LIST_ASSIGN_RE = re.compile(
    r"^(?P<indent>\s*)(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"Uniform\(\*(?P<source>[A-Za-z_][A-Za-z0-9_]*)\)(?P<tail>\s*(?:#.*)?)$"
)
PARAM_DEF_RE = re.compile(r"^\s*param\s+(OPT_[A-Za-z0-9_]+)\s*=")
OPT_REF_RE = re.compile(r"globalParameters\.(OPT_[A-Za-z0-9_]+)")
BEHAVIOR_DEF_RE = re.compile(
    r"^\s*behavior\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\((?P<params>[^)]*)\):"
)
BEHAVIOR_CALL_SINGLE_RE = re.compile(
    r"^(?P<indent>\s*)with behavior (?P<name>[A-Za-z_][A-Za-z0-9_]*)\((?P<args>.*)\)(?P<tail>\s*,?\s*(?:#.*)?)$"
)
BEHAVIOR_CALL_START_RE = re.compile(
    r"^(?P<indent>\s*)with behavior (?P<name>[A-Za-z_][A-Za-z0-9_]*)\(\s*$"
)
KWARG_LINE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<value>.*?)(?P<comma>,?)\s*(?P<comment>#.*)?$"
)


def opposite_side(side: str) -> str:
    return "._laneToLeft" if side == "._laneToRight" else "._laneToRight"


def default_param_value(name: str) -> str:
    if "SPEED" in name:
        return "Range(1, 8)"
    if "THROTTLE" in name:
        return "Range(0.5, 1.0)"
    if "BRAKE" in name or "STOP" in name:
        return "Range(0, 1)"
    if "STEER" in name or "SWERVE" in name:
        return "Range(-1.0, 1.0)"
    if "COUNT" in name or "STEPS" in name or "WAIT" in name or "DURATION" in name:
        return "Range(1, 5)"
    if "OFFSET" in name or "GEO_X" in name:
        return "Range(-2, 2)"
    if "DISTANCE" in name or "GEO_Y" in name:
        return "Range(0, 30)"
    return "Range(0, 1)"


def missing_opt_params(lines):
    refs = set()
    defs = set()
    for line in lines:
        code = line.split("#", 1)[0]
        match = PARAM_DEF_RE.match(code)
        if match:
            defs.add(match.group(1))
        refs.update(OPT_REF_RE.findall(code))
    return sorted(refs - defs)


def behavior_signatures(lines):
    signatures = {}
    for line in lines:
        match = BEHAVIOR_DEF_RE.match(line)
        if not match:
            continue
        params = []
        for param in match.group("params").split(","):
            name = param.strip().split("=", 1)[0].strip()
            if name:
                params.append(name)
        signatures[match.group("name")] = set(params)
    return signatures


def split_top_level_args(args: str):
    parts = []
    current = []
    depth = 0
    for char in args:
        if char in "([{":
            depth += 1
        elif char in ")]}" and depth:
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    tail = "".join(current).strip()
    if tail:
        parts.append(tail)
    return parts


def filter_behavior_args(args: str, allowed_params):
    if not args.strip():
        return args, False
    kept = []
    changed = False
    for part in split_top_level_args(args):
        if "=" not in part:
            kept.append(part)
            continue
        name = part.split("=", 1)[0].strip()
        if name in allowed_params:
            kept.append(part)
        else:
            changed = True
    return ", ".join(kept), changed


def filter_behavior_kwarg_lines(arg_lines, allowed_params):
    kept = []
    changed = False
    for line in arg_lines:
        match = KWARG_LINE_RE.match(line)
        if not match:
            kept.append(line)
            continue
        if match.group("name") in allowed_params:
            kept.append(line)
        else:
            changed = True
    return kept, changed


def append_lane_section_assignment(output, indent, section_var, base, side, tail, has_ego_lane_sec):
    output.append(f"{indent}{section_var} = {base}{side}{tail}")
    if side in ("._laneToLeft", "._laneToRight"):
        output.append(f"{indent}if {section_var} is None:")
        output.append(f"{indent}    {section_var} = {base}{opposite_side(side)}")
    output.append(f"{indent}if {section_var} is None:")
    if has_ego_lane_sec and base == "network.laneSectionAt(ego)":
        output.append(f"{indent}    {section_var} = egoLaneSec")
    else:
        output.append(f"{indent}    {section_var} = {base}")
    output.append(f"{indent}require {section_var} is not None")


def sanitize_text(text: str) -> str:
    lines = text.splitlines()
    output = []
    changed = False
    has_ego_lane_sec = any(re.match(r"^\s*egoLaneSec\s*=", line) for line in lines)
    local_behaviors = behavior_signatures(lines)
    missing_params = missing_opt_params(lines)
    inserted_missing_params = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if missing_params and not inserted_missing_params and line.startswith("EGO_MODEL"):
            output.append(line)
            for name in missing_params:
                output.append(f"param {name} = {default_param_value(name)}")
            inserted_missing_params = True
            changed = True
            i += 1
            continue

        behavior_single = BEHAVIOR_CALL_SINGLE_RE.match(line)
        if behavior_single and behavior_single.group("name") in local_behaviors:
            allowed_params = local_behaviors[behavior_single.group("name")]
            filtered_args, args_changed = filter_behavior_args(behavior_single.group("args"), allowed_params)
            if args_changed:
                output.append(
                    f"{behavior_single.group('indent')}with behavior "
                    f"{behavior_single.group('name')}({filtered_args}){behavior_single.group('tail')}"
                )
                changed = True
                i += 1
                continue

        behavior_start = BEHAVIOR_CALL_START_RE.match(line)
        if behavior_start and behavior_start.group("name") in local_behaviors:
            arg_lines = []
            j = i + 1
            while j < len(lines) and lines[j].strip() != ")":
                arg_lines.append(lines[j])
                j += 1
            if j < len(lines):
                allowed_params = local_behaviors[behavior_start.group("name")]
                filtered_lines, args_changed = filter_behavior_kwarg_lines(arg_lines, allowed_params)
                if args_changed:
                    if filtered_lines:
                        output.append(line)
                        output.extend(filtered_lines)
                        output.append(lines[j])
                    else:
                        output.append(
                            f"{behavior_start.group('indent')}with behavior {behavior_start.group('name')}()"
                        )
                    changed = True
                    i = j + 1
                    continue

        uniform_list_match = UNIFORM_LIST_ASSIGN_RE.match(line)
        if uniform_list_match:
            indent = uniform_list_match.group("indent")
            source = uniform_list_match.group("source")
            while output and (
                output[-1].startswith(f"{indent}    ")
                or output[-1].strip() in {
                    f"if len({source}) == 0:",
                    f"{source} = network.laneSections",
                }
            ):
                output.pop()
            output.append(f"{indent}if len({source}) == 0:")
            output.append(f"{indent}    {source} = network.laneSections")
            output.append(line)
            changed = True
            i += 1
            while i < len(lines):
                stripped = lines[i].strip()
                if stripped == f"if len({source}) == 0:":
                    i += 1
                    while i < len(lines) and lines[i].startswith(f"{indent}    "):
                        i += 1
                    continue
                break
            continue

        lane_section_at_ego = LANE_SECTION_AT_EGO_RE.match(line)
        if lane_section_at_ego and has_ego_lane_sec:
            indent = lane_section_at_ego.group("indent")
            section_var = lane_section_at_ego.group("section")
            output.append(line)
            output.append(f"{indent}if {section_var} is None:")
            output.append(f"{indent}    {section_var} = egoLaneSec")
            output.append(f"{indent}require {section_var} is not None")
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
            append_lane_section_assignment(output, indent, section_var, base, side, tail, has_ego_lane_sec)
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

        section_alias_match = SECTION_ALIAS_ASSIGN_RE.match(line)
        if section_alias_match and has_ego_lane_sec:
            indent = section_alias_match.group("indent")
            target = section_alias_match.group("target")
            output.append(line)
            output.append(f"{indent}if {target} is None:")
            output.append(f"{indent}    {target} = egoLaneSec")
            output.append(f"{indent}require {target} is not None")
            changed = True
            i += 1
            while i < len(lines):
                stripped = lines[i].strip()
                if stripped == f"if {target} is None:":
                    i += 1
                    while i < len(lines) and lines[i].startswith(f"{indent}    "):
                        i += 1
                    continue
                if stripped == f"require {target} is not None":
                    i += 1
                    continue
                break
            continue

        orientation_match = ORIENTATION_ACCESS_RE.match(line)
        if orientation_match and has_ego_lane_sec:
            indent = orientation_match.group("indent")
            obj = orientation_match.group("obj")
            while output and (
                output[-1].startswith(f"{indent}    ")
                or output[-1].strip() in {
                    f"if {obj} is None:",
                    f"{obj} = egoLaneSec",
                    f"require {obj} is not None",
                }
            ):
                output.pop()
            already_guarded = (
                len(output) >= 3
                and output[-3].strip() == f"if {obj} is None:"
                and output[-2].strip() == f"{obj} = egoLaneSec"
                and output[-1].strip() == f"require {obj} is not None"
            )
            if not already_guarded:
                output.append(f"{indent}if {obj} is None:")
                output.append(f"{indent}    {obj} = egoLaneSec")
                output.append(f"{indent}require {obj} is not None")
                changed = True
            output.append(line)
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

        append_lane_section_assignment(output, indent, section_var, base, side, tail, has_ego_lane_sec)
        output.append(f"{indent}{target} = {section_var}")
        changed = True
        i += 1

    result = "\n".join(output)
    if missing_params and not inserted_missing_params:
        prefix = [f"param {name} = {default_param_value(name)}" for name in missing_params]
        result = "\n".join(prefix + [result])
    if not result.endswith("\n"):
        result += "\n"
    return result if changed or (missing_params and not inserted_missing_params) else text


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
