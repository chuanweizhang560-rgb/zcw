#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AERIALCORE_DIR="${AERIALCORE_DIR:-${ROOT_DIR}/third_party/aerialcore_simulation}"
AERIALCORE_WORLD="${AERIALCORE_WORLD:-wind_turbine}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
STAMP="$(date +%Y%m%d_%H%M%S)"
ZCW_MODEL_PATH="${ZCW_MODEL_PATH:-${ROOT_DIR}/assets/gazebo/models}"

case "${AERIALCORE_WORLD}" in
  wind_turbine)
    WORLD_PATH="${AERIALCORE_DIR}/worlds/wind_turbine_autospawn.world"
    ;;
  danube_wires)
    WORLD_PATH="${AERIALCORE_DIR}/worlds/power_towers_danube_wires_rescaled_autospawn.world"
    ;;
  *)
    echo "Unsupported AERIALCORE_WORLD=${AERIALCORE_WORLD}" >&2
    echo "Supported values: wind_turbine, danube_wires" >&2
    exit 1
    ;;
esac

MODEL_PATH="${AERIALCORE_DIR}/models"
if [[ -d "${ZCW_MODEL_PATH}" ]]; then
  MODEL_PATH="${ZCW_MODEL_PATH}:${MODEL_PATH}"
fi
if [[ -n "${EXTRA_GAZEBO_MODEL_PATH:-}" ]]; then
  MODEL_PATH="${MODEL_PATH}:${EXTRA_GAZEBO_MODEL_PATH}"
fi

PX4_SITL_WORLD="${WORLD_PATH}" \
GAZEBO_MODEL_PATH="${MODEL_PATH}" \
GAZEBO_RESOURCE_PATH="/usr/share/gazebo-11:${AERIALCORE_DIR}" \
VERBOSE_SIM="${VERBOSE_SIM:-1}" \
LOG_FILE="${LOG_DIR}/px4_aerialcore_${AERIALCORE_WORLD}_gui_${STAMP}.log" \
SCREENSHOT_FILE="${SCREENSHOT_DIR}/px4_aerialcore_${AERIALCORE_WORLD}_gui_${STAMP}.png" \
  "${ROOT_DIR}/scripts/capture_px4_gazebo_classic_gui.sh"
