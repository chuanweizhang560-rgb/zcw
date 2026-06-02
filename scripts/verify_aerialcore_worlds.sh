#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AERIALCORE_DIR="${AERIALCORE_DIR:-${ROOT_DIR}/third_party/aerialcore_simulation}"
TIMEOUT_SEC="${TIMEOUT_SEC:-20}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"

if [[ ! -d "${AERIALCORE_DIR}" ]]; then
  echo "AerialCore simulation repo not found: ${AERIALCORE_DIR}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

verify_world() {
  local label="$1"
  local world_path="$2"
  local port="$3"
  local log_file="${LOG_DIR}/aerialcore_${label}_${STAMP}.log"

  set +e
  timeout "${TIMEOUT_SEC}s" env \
    GAZEBO_MASTER_URI="http://127.0.0.1:${port}" \
    GAZEBO_MODEL_PATH="${AERIALCORE_DIR}/models" \
    GAZEBO_RESOURCE_PATH="/usr/share/gazebo-11:${AERIALCORE_DIR}" \
    gzserver --verbose "${world_path}" >"${log_file}" 2>&1
  local status=$?
  set -e

  if [[ "${status}" -ne 124 ]]; then
    echo "World ${label} exited before timeout with status ${status}." >&2
    tail -n 80 "${log_file}" >&2 || true
    exit 1
  fi

  if grep -q "Unable to start server" "${log_file}"; then
    echo "World ${label} failed to bind Gazebo master." >&2
    tail -n 80 "${log_file}" >&2 || true
    exit 1
  fi

  if ! grep -q "Loading world file" "${log_file}" ||
     ! grep -q "Connected to gazebo master" "${log_file}"; then
    echo "World ${label} did not reach Gazebo running state." >&2
    tail -n 80 "${log_file}" >&2 || true
    exit 1
  fi

  echo "AerialCore world ${label} verified with expected timeout."
  echo "Log: ${log_file}"
}

verify_world \
  "wind_turbine" \
  "${AERIALCORE_DIR}/worlds/wind_turbine_autospawn.world" \
  "11346"

verify_world \
  "danube_wires" \
  "${AERIALCORE_DIR}/worlds/power_towers_danube_wires_rescaled_autospawn.world" \
  "11347"
