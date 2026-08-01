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
CENTERLINE_CHAIN_RE = re.compile(
    r"(?P<expr>(?P<base>[A-Za-z_][A-Za-z0-9_]*)\.(?P<field>startLane|endLane|connectingLane))\.centerline"
)
CENTERLINE_SIMPLE_RE = re.compile(r"\b(?P<obj>[A-Za-z_][A-Za-z0-9_]*)\.centerline")
SCALAR_OFFSET_ALONG_RE = re.compile(
    r"^(?P<prefix>.*\boffset along .+ by )(?P<value>globalParameters\.OPT_[A-Za-z0-9_]+)(?P<tail>\s*,?\s*(?:#.*)?)$"
)
UNPARENTHESIZED_OFFSET_VECTOR_RE = re.compile(
    r"^(?P<prefix>.*\boffset along .+ by )(?P<value>globalParameters\.OPT_[A-Za-z0-9_]+)\s*@\s*0(?P<tail>\s*,?\s*(?:#.*)?)$"
)
OFFSET_ASSIGN_RE = re.compile(
    r"^\s*(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*.*\boffset along\b"
)
WALKING_DIRECTION_FROM_RE = re.compile(
    r"SetWalkingDirectionAction\(direction from (?P<source>[^)]+?) to (?P<target>[^)]+?)\)"
)
ROAD_DIRECTION_ROTATE_ASSIGN_RE = re.compile(
    r"^(?P<indent>\s*)(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"rotateVector\(roadDirection,\s*(?P<angle>[-+]?\d+)\s*deg\)(?P<tail>\s*(?:#.*)?)$"
)
ROAD_DIRECTION_ROTATE_HEADING_RE = re.compile(
    r"(?P<prefix>with heading\s+)rotateVector\(roadDirection,\s*(?P<angle>[-+]?\d+)\s*deg\)"
)
OBJECT_WITH_POSITION_RE = re.compile(
    r"^\s*[A-Za-z_][A-Za-z0-9_]*\s*=\s*[A-Za-z_][A-Za-z0-9_]*\s+"
    r"(?:at|on|in|left of|right of|front of|back of|following)\b.*,\s*(?:#.*)?$"
)
WITH_POSITION_RE = re.compile(r"^\s*with position\b")
NETWORK_ROADS_AT_ASSIGN_RE = re.compile(
    r"^\s*(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*network\.roadsAt\(.+\)\s*(?:#.*)?$"
)
RANDOM_LEN_FALLBACK_RE = re.compile(
    r"^(?P<indent>\s*)if len\((?P<target>[A-Za-z_][A-Za-z0-9_]*)\) == 0:\s*(?:#.*)?$"
)
UNIFORM_LIST_ASSIGN_RE = re.compile(
    r"^(?P<indent>\s*)(?P<target>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"Uniform\(\*(?P<source>[A-Za-z_][A-Za-z0-9_]*)\)(?P<tail>\s*(?:#.*)?)$"
)
PARAM_DEF_RE = re.compile(r"^\s*param\s+(OPT_[A-Za-z0-9_]+)\s*=")
OPT_REF_RE = re.compile(r"globalParameters\.(OPT_[A-Za-z0-9_]+)")
MODEL_DEF_RE = re.compile(r"^\s*([A-Z_]*MODEL)\s*=")
BLUEPRINT_MODEL_REF_RE = re.compile(r"\bwith blueprint\s+([A-Z_]*MODEL)\b")
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


def default_model_value(name: str) -> str:
    if "PEDESTRIAN" in name or "WALKER" in name:
        return '"walker.pedestrian.0001"'
    if "MOTOR" in name or "BIKE" in name:
        return '"vehicle.yamaha.yzf"'
    return '"vehicle.audi.tt"'


def missing_model_defs(lines):
    refs = set()
    defs = set()
    for line in lines:
        code = line.split("#", 1)[0]
        match = MODEL_DEF_RE.match(code)
        if match:
            defs.add(match.group(1))
        refs.update(BLUEPRINT_MODEL_REF_RE.findall(code))
    return sorted(refs - defs)


def offset_vector_vars(lines):
    vars_ = set()
    for line in lines:
        code = line.split("#", 1)[0]
        match = OFFSET_ASSIGN_RE.match(code)
        if match:
            vars_.add(match.group("target"))
    return vars_


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


def strip_random_len_fallbacks(lines):
    output = []
    changed = False
    i = 0
    while i < len(lines):
        line = lines[i]
        match = RANDOM_LEN_FALLBACK_RE.match(line)
        if match:
            indent = match.group("indent")
            target = match.group("target")
            j = i + 1
            if (
                j < len(lines)
                and lines[j].startswith(f"{indent}    ")
                and lines[j].strip().startswith(f"{target} = ")
            ):
                changed = True
                i = j + 1
                continue
        output.append(line)
        i += 1
    return output, changed


def strip_generated_angle_between_filters(lines):
    output = []
    changed = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if (
            " = [lane for lane in network.lanesAt(" in line
            and i + 1 < len(lines)
            and "angleBetween(" in lines[i + 1]
        ):
            output.append(line.split(" = ", 1)[0] + " = network.lanesAt(IntSpawnPt.position)")
            changed = True
            i += 2
            continue
        output.append(line)
        i += 1
    return output, changed


def fallback_lane_value(has_ego_lane_sec, var_name=None):
    if has_ego_lane_sec and var_name != "egoLaneSec":
        return "egoLaneSec"
    return "Uniform(*network.laneSections)"


def temp_name_for_lane_expr(expr: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in expr.split("."))


def append_none_guard(output, indent, var_name, has_ego_lane_sec):
    output.append(f"{indent}if {var_name} is None:")
    output.append(f"{indent}    {var_name} = {fallback_lane_value(has_ego_lane_sec, var_name)}")
    output.append(f"{indent}require {var_name} is not None")


def append_lane_section_assignment(output, indent, section_var, base, side, tail, has_ego_lane_sec):
    output.append(f"{indent}{section_var} = {base}{side}{tail}")
    if side in ("._laneToLeft", "._laneToRight"):
        output.append(f"{indent}if {section_var} is None:")
        output.append(f"{indent}    {section_var} = {base}{opposite_side(side)}")
    if has_ego_lane_sec and base == "network.laneSectionAt(ego)":
        output.append(f"{indent}if {section_var} is None:")
        output.append(f"{indent}    {section_var} = egoLaneSec")
        output.append(f"{indent}require {section_var} is not None")
    else:
        append_none_guard(output, indent, section_var, has_ego_lane_sec)


def sanitize_text(text: str) -> str:
    original_text = text
    lines = text.splitlines()
    lines, pre_changed = strip_random_len_fallbacks(lines)
    lines, angle_filter_changed = strip_generated_angle_between_filters(lines)
    pre_changed = pre_changed or angle_filter_changed
    if pre_changed:
        text = "\n".join(lines)
        if original_text.endswith("\n"):
            text += "\n"
    output = []
    changed = pre_changed
    has_ego_lane_sec = any(re.match(r"^\s*egoLaneSec\s*=", line) for line in lines)
    local_behaviors = behavior_signatures(lines)
    offset_vars = offset_vector_vars(lines)
    missing_params = missing_opt_params(lines)
    missing_models = missing_model_defs(lines)
    inserted_missing_params = False
    inserted_missing_models = False
    object_position_spec_indent = None
    i = 0
    while i < len(lines):
        line = lines[i]
        current_indent = len(line) - len(line.lstrip())
        if object_position_spec_indent is not None and line.strip():
            if current_indent <= object_position_spec_indent:
                object_position_spec_indent = None

        if OBJECT_WITH_POSITION_RE.match(line):
            output.append(line)
            object_position_spec_indent = current_indent
            i += 1
            continue

        if object_position_spec_indent is not None and WITH_POSITION_RE.match(line):
            changed = True
            i += 1
            continue

        roads_at_match = NETWORK_ROADS_AT_ASSIGN_RE.match(line)
        if roads_at_match:
            target = roads_at_match.group("target")
            later_text = "\n".join(lines[i + 1:])
            if not re.search(rf"\b{re.escape(target)}\b", later_text):
                changed = True
                i += 1
                continue

        random_len_fallback = RANDOM_LEN_FALLBACK_RE.match(line)
        if random_len_fallback:
            indent = random_len_fallback.group("indent")
            target = random_len_fallback.group("target")
            j = i + 1
            if (
                j < len(lines)
                and lines[j].startswith(f"{indent}    ")
                and lines[j].strip().startswith(f"{target} = ")
            ):
                changed = True
                i = j + 1
                continue

        if (
            (missing_params and not inserted_missing_params)
            or (missing_models and not inserted_missing_models)
        ) and line.startswith("EGO_MODEL"):
            output.append(line)
            if missing_models and not inserted_missing_models:
                for name in missing_models:
                    output.append(f"{name} = {default_model_value(name)}")
                inserted_missing_models = True
            if missing_params and not inserted_missing_params:
                for name in missing_params:
                    output.append(f"param {name} = {default_param_value(name)}")
                inserted_missing_params = True
            changed = True
            i += 1
            continue

        rotate_assign_match = ROAD_DIRECTION_ROTATE_ASSIGN_RE.match(line)
        if rotate_assign_match:
            angle = int(rotate_assign_match.group("angle"))
            output.append(
                f"{rotate_assign_match.group('indent')}{rotate_assign_match.group('target')} = "
                f"Vector(cos(egoSpawnPt.heading + {angle} deg), "
                f"sin(egoSpawnPt.heading + {angle} deg)){rotate_assign_match.group('tail')}"
            )
            changed = True
            i += 1
            continue

        rotate_heading_match = ROAD_DIRECTION_ROTATE_HEADING_RE.search(line)
        if rotate_heading_match:
            angle = int(rotate_heading_match.group("angle"))
            output.append(
                ROAD_DIRECTION_ROTATE_HEADING_RE.sub(
                    f"{rotate_heading_match.group('prefix')}egoSpawnPt.heading + {angle} deg",
                    line,
                )
            )
            changed = True
            i += 1
            continue

        walking_direction_match = WALKING_DIRECTION_FROM_RE.search(line)
        if walking_direction_match:
            source = walking_direction_match.group("source").strip()
            target = walking_direction_match.group("target").strip()
            if source == "self":
                source = "self.position"
            output.append(
                WALKING_DIRECTION_FROM_RE.sub(
                    f"SetWalkingDirectionAction(angle from {source} to {target})",
                    line,
                )
            )
            changed = True
            i += 1
            continue

        rewritten_position_line = line
        for var_name in sorted(offset_vars, key=len, reverse=True):
            rewritten_position_line = re.sub(
                rf"\b{re.escape(var_name)}\.position\b",
                var_name,
                rewritten_position_line,
            )
        if rewritten_position_line != line:
            output.append(rewritten_position_line)
            changed = True
            i += 1
            continue

        scalar_offset_match = SCALAR_OFFSET_ALONG_RE.match(line)
        if scalar_offset_match:
            output.append(
                f"{scalar_offset_match.group('prefix')}"
                f"({scalar_offset_match.group('value')} @ 0)"
                f"{scalar_offset_match.group('tail')}"
            )
            changed = True
            i += 1
            continue

        offset_vector_match = UNPARENTHESIZED_OFFSET_VECTOR_RE.match(line)
        if offset_vector_match:
            output.append(
                f"{offset_vector_match.group('prefix')}"
                f"({offset_vector_match.group('value')} @ 0)"
                f"{offset_vector_match.group('tail')}"
            )
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
            if source.lower().endswith("maneuvers"):
                output.append(line)
                i += 1
                continue
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
            section = section_alias_match.group("section")
            if target == section:
                output.append(line)
                i += 1
                continue
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

        chain_matches = list(CENTERLINE_CHAIN_RE.finditer(line))
        if chain_matches:
            indent = re.match(r"^\s*", line).group(0)
            rewritten = line
            for match in chain_matches:
                expr = match.group("expr")
                temp_var = temp_name_for_lane_expr(expr)
                rewritten = rewritten.replace(f"{expr}.centerline", f"{temp_var}.centerline")
                output.append(f"{indent}{temp_var} = {expr}")
                append_none_guard(output, indent, temp_var, has_ego_lane_sec)
            output.append(rewritten)
            changed = True
            i += 1
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

        simple_centerline_match = CENTERLINE_SIMPLE_RE.search(line)
        if simple_centerline_match:
            indent = re.match(r"^\s*", line).group(0)
            obj = simple_centerline_match.group("obj")
            expected_fallback = fallback_lane_value(has_ego_lane_sec, obj)
            already_guarded = (
                len(output) >= 3
                and output[-3].strip() == f"if {obj} is None:"
                and output[-1].strip() == f"require {obj} is not None"
            )
            if already_guarded:
                expected_assignment = f"{obj} = {expected_fallback}"
                if output[-2].strip() != expected_assignment:
                    guard_indent = output[-2][: len(output[-2]) - len(output[-2].lstrip())]
                    output[-2] = f"{guard_indent}{expected_assignment}"
                    changed = True
            else:
                append_none_guard(output, indent, obj, has_ego_lane_sec)
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
    if missing_models and not inserted_missing_models:
        prefix = [f"{name} = {default_model_value(name)}" for name in missing_models]
        result = "\n".join(prefix + [result])
    if not result.endswith("\n"):
        result += "\n"
    return result if changed or (missing_params and not inserted_missing_params) or (missing_models and not inserted_missing_models) else original_text


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
