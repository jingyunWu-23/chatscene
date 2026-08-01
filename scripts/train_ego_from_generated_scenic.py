#!/usr/bin/env python3
"""Train an ego PPO policy directly from generated Scenic files."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SCENIC_DIR = ROOT_DIR / "safebench" / "scenario" / "scenario_data" / "scenic_data" / "dynamic_scenario"
SCENIC_SRC = ROOT_DIR / "Scenic" / "src"


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenic-dir", default=str(DEFAULT_SCENIC_DIR), help="Directory containing generated .scenic files.")
    parser.add_argument("--layout", choices=["dynamic", "scenario"], default="dynamic")
    parser.add_argument("--agent-cfg", default="ppo.yaml")
    parser.add_argument("--scenario-cfg", default="dynamic_scenic.yaml")
    parser.add_argument("--run-name", default="generated_scenic_ego")
    parser.add_argument("--train-episodes", type=int, default=2000)
    parser.add_argument("--max-episode-step", type=int, default=200)
    parser.add_argument("--save-freq", type=int, default=50)
    parser.add_argument("--sample-num", type=int, default=50)
    parser.add_argument("--opt-step", type=int, default=10)
    parser.add_argument("--select-num", type=int, default=10)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--device", default=None)
    parser.add_argument("--port", type=int, default=2000)
    parser.add_argument("--tm-port", type=int, default=8000)
    parser.add_argument("--fixed-delta-seconds", type=float, default=0.1)
    parser.add_argument("--render", action="store_true", default=False)
    parser.add_argument("--continue-agent-training", action="store_true", default=False)
    parser.add_argument("--force-param-json", action="store_true", default=False)
    parser.add_argument("--carla-python-egg", default=os.environ.get("CARLA_PYTHON_EGG", ""))
    parser.add_argument("--dry-run", action="store_true", default=False)
    return parser.parse_args()


def add_carla_egg(path: str):
    if SCENIC_SRC.exists():
        sys.path.insert(0, str(SCENIC_SRC))
    if not path:
        return
    egg = Path(path).expanduser()
    if not egg.exists():
        raise FileNotFoundError(f"CARLA Python egg not found: {egg}")
    paths = [egg]
    if egg.parent.name == "dist" and egg.parent.parent.name == "carla":
        paths.append(egg.parent.parent)
    for item in reversed(paths):
        sys.path.insert(0, str(item))
    prefix = os.pathsep.join(str(item) for item in paths)
    os.environ["PYTHONPATH"] = f"{prefix}{os.pathsep}{os.environ.get('PYTHONPATH', '')}".rstrip(os.pathsep)


def scenic_files(scenic_dir: Path):
    files = sorted(path for path in scenic_dir.glob("*.scenic") if path.is_file())
    if not files:
        raise FileNotFoundError(f"No .scenic files found under {scenic_dir}")
    return files


def parse_opt_ranges(scenic_file: Path):
    text = scenic_file.read_text(encoding="utf-8")
    pattern = re.compile(
        r"^\s*param\s+(OPT_[A-Za-z0-9_]+)\s*=\s*Range\(\s*([-+]?\d+(?:\.\d+)?)\s*,\s*([-+]?\d+(?:\.\d+)?)\s*\)",
        re.MULTILINE,
    )
    ranges = {}
    for name, low, high in pattern.findall(text):
        ranges[name] = {"low": float(low), "high": float(high)}
    return ranges


def ensure_dynamic_param_json(scenic_dir: Path, files, sample_num: int, opt_step: int, select_num: int, force: bool):
    json_path = scenic_dir / "dynamic_scenario.json"
    existing = {}
    if json_path.exists() and not force:
        with json_path.open("r", encoding="utf-8") as f:
            existing = json.load(f)

    block_count = int(math.ceil(float(sample_num) / max(int(opt_step), 1)))
    changed = bool(force) or not json_path.exists()
    for scenic_file in files:
        key = f"OPT_{scenic_file.stem}"
        ranges = parse_opt_ranges(scenic_file)
        entry = existing.get(key, {}) if not force else {}
        for idx in range(block_count):
            entry.setdefault(f"opt_time_{idx}", ranges)
        entry["select_id"] = list(range(min(int(select_num), int(sample_num))))
        existing[key] = entry
        changed = True

    if changed:
        with json_path.open("w", encoding="utf-8") as f:
            json.dump(existing, f, ensure_ascii=False, indent=4)
    return json_path


def relative_to_root(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT_DIR.resolve()))
    except ValueError:
        return str(path.resolve())


def main():
    args = parse_args()
    if not args.render:
        os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
    add_carla_egg(args.carla_python_egg)

    from safebench.util.run_util import load_config

    scenic_dir = Path(args.scenic_dir).expanduser().resolve()
    files = scenic_files(scenic_dir)
    param_json = None
    if args.layout == "dynamic":
        param_json = ensure_dynamic_param_json(
            scenic_dir,
            files,
            sample_num=args.sample_num,
            opt_step=args.opt_step,
            select_num=args.select_num,
            force=bool(args.force_param_json),
        )

    if args.device:
        device = args.device
    else:
        try:
            import torch
            device = "cuda:0" if torch.cuda.is_available() else "cpu"
        except ModuleNotFoundError:
            device = "cpu"
            torch = None
    agent_config = load_config(str(ROOT_DIR / "safebench" / "agent" / "config" / args.agent_cfg))
    scenario_config = load_config(str(ROOT_DIR / "safebench" / "scenario" / "config" / args.scenario_cfg))

    model_path = ROOT_DIR / "safebench" / "agent" / "model_ckpt" / "ego_train" / args.run_name
    output_dir = ROOT_DIR / "log" / "ego_train" / args.run_name

    common = {
        "ROOT_DIR": str(ROOT_DIR),
        "mode": "train_agent",
        "exp_name": args.run_name,
        "output_dir": str(output_dir),
        "seed": int(args.seed),
        "threads": int(args.threads),
        "device": device,
        "num_scenario": 1,
        "save_video": False,
        "render": bool(args.render),
        "frame_skip": 1,
        "port": int(args.port),
        "tm_port": int(args.tm_port),
        "fixed_delta_seconds": float(args.fixed_delta_seconds),
        "max_episode_step": int(args.max_episode_step),
        "auto_ego": False,
        "continue_agent_training": bool(args.continue_agent_training),
        "continue_scenario_training": False,
    }
    agent_config.update(common)
    agent_config.update({
        "train_episode": int(args.train_episodes),
        "save_freq": int(args.save_freq),
        "model_path": relative_to_root(model_path),
    })
    scenario_config.update(common)
    scenario_config.update({
        "policy_type": "scenic",
        "scenario_category": "scenic",
        "scenic_dir": str(scenic_dir),
        "sample_num": int(args.sample_num),
        "opt_step": int(args.opt_step),
        "select_num": int(args.select_num),
        "method": "scenic",
        "scenario_id": None,
        "ego_action_dim": 2,
        "ego_state_dim": 4,
        "ego_action_limit": 1.0,
    })

    print(f"Scenic dir: {scenic_dir}")
    print(f"Scenic files: {len(files)}")
    if param_json:
        print(f"Param json: {param_json}")
    print(f"Model dir: {model_path}")
    print(f"Log dir: {output_dir}")
    print(f"Device: {device}")
    if args.dry_run:
        return

    import torch

    from safebench.scenic_runner import ScenicRunner as ScenarioScenicRunner
    from safebench.scenic_runner_dynamic import ScenicRunner as DynamicScenicRunner
    from safebench.util.torch_util import set_seed, set_torch_variable

    set_torch_variable(device)
    torch.set_num_threads(int(args.threads))
    set_seed(int(args.seed))
    runner_cls = DynamicScenicRunner if args.layout == "dynamic" else ScenarioScenicRunner
    runner = runner_cls(agent_config, scenario_config)
    try:
        runner.run()
    finally:
        runner.close()


if __name__ == "__main__":
    main()
