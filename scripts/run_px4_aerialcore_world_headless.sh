#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AERIALCORE_DIR="${AERIALCORE_DIR:-${ROOT_DIR}/third_party/aerialcore_simulation}"
AERIALCORE_WORLD="${AERIALCORE_WORLD:-wind_turbine}"
TIMEOUT_SEC="${TIMEOUT_SEC:-60}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/px4_aerialcore_${AERIALCORE_WORLD}_${STAMP}.log}"
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

if [[ ! -f "${WORLD_PATH}" ]]; then
  echo "AerialCore world not found: ${WORLD_PATH}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

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
TIMEOUT_SEC="${TIMEOUT_SEC}" \
LOG_FILE="${LOG_FILE}" \
  "${ROOT_DIR}/scripts/run_px4_gazebo_classic_headless.sh"
