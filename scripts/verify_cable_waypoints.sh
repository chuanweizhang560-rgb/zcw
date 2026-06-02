#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PX4_SCRIPT="${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh" \
AERIALCORE_WORLD="danube_wires" \
OFFBOARD_LAUNCH_FILE="single_vehicle_cable_inspection.launch.py" \
OFFBOARD_RUN_SEC="${OFFBOARD_RUN_SEC:-85}" \
PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-130}" \
  "${ROOT_DIR}/scripts/verify_px4_offboard_waypoints.sh"
