#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export OFFBOARD_LAUNCH_FILE="${OFFBOARD_LAUNCH_FILE:-single_vehicle_wind_turbine_slow_loop_closure_smoke.launch.py}"
export MIN_WAYPOINT_ADVANCEMENTS="${MIN_WAYPOINT_ADVANCEMENTS:-72}"
export MOTION_SETTLE_SEC="${MOTION_SETTLE_SEC:-240}"
export PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-360}"
export GUI_SETTLE_SEC="${GUI_SETTLE_SEC:-10}"
export RTABMAP_LOOP_PARAMS_FILE="${RTABMAP_LOOP_PARAMS_FILE:-${ROOT_DIR}/install/zcw_bringup/share/zcw_bringup/config/rtabmap_loop_closure_smoke.yaml}"
export RTABMAP_EXTRA_ROS_ARGS="${RTABMAP_EXTRA_ROS_ARGS:---params-file ${RTABMAP_LOOP_PARAMS_FILE}}"

exec "${ROOT_DIR}/scripts/capture_rtabmap_depth_camera_rgbd_wind_rviz_overlay.sh"
