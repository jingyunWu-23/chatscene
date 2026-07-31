#!/usr/bin/env bash
set -euo pipefail

CARLA_EVOLUTION_ROOT="${CARLA_EVOLUTION_ROOT:-/home/chenyuanwan/download/co-training/code-migration/模型/carla_evolution}"
PYTHON_BIN="${PYTHON_BIN:-/home/chenyuanwan/anaconda3/envs/cav-carla/bin/python}"

if [[ -n "${CARLA_PYTHON_EGG:-}" ]]; then
  export PYTHONPATH="${CARLA_PYTHON_EGG}${PYTHONPATH:+:${PYTHONPATH}}"
fi

cd "$CARLA_EVOLUTION_ROOT"
exec "$PYTHON_BIN" scripts/run_ego_scratch_four_scenario_workflow.py "$@"
