#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PX4_SCRIPT="${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh" \
AERIALCORE_WORLD="wind_turbine" \
OFFBOARD_LAUNCH_FILE="single_vehicle_wind_turbine_multilevel_orbit.launch.py" \
OFFBOARD_RUN_SEC="${OFFBOARD_RUN_SEC:-95}" \
PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-120}" \
VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-70}" \
  "${ROOT_DIR}/scripts/verify_px4_offboard_waypoints.sh"
