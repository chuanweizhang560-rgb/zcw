#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
PX4_SCRIPT="${PX4_SCRIPT:-${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
RVIZ_CONFIG="${RVIZ_CONFIG:-${ROOT_DIR}/ros2_ws/src/zcw_cable_perception/rviz/rtabmap_depth_camera_overlay.rviz}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/rtabmap_depth_camera_motion_rviz_overlay_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_depth_camera_motion_rviz_overlay_${STAMP}.txt"
AGENT_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_agent_${STAMP}.log"
PX4_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_px4_${STAMP}.log"
PX4_WRAPPER_LOG="${PX4_LOG}.wrapper"
OFFBOARD_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_offboard_${STAMP}.log"
BRIDGE_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_odom_bridge_${STAMP}.log"
RTABMAP_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_rtabmap_${STAMP}.log"
RVIZ_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_rviz_${STAMP}.log"
STATUS_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_vehicle_status_${STAMP}.log"
LOCAL_POSITION_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_vehicle_local_position_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_topics_${STAMP}.log"
POINTS_SAMPLE_LOG="${LOG_DIR}/rtabmap_depth_camera_motion_points_sample_${STAMP}.log"
SCREENSHOT_FILE="${SCREENSHOT_DIR}/rtabmap_depth_camera_motion_rviz_overlay_${STAMP}.png"
VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-95}"
PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-190}"
MOTION_SETTLE_SEC="${MOTION_SETTLE_SEC:-70}"
GUI_SETTLE_SEC="${GUI_SETTLE_SEC:-10}"

agent_pid=""
px4_pid=""
offboard_pid=""
bridge_pid=""
rtabmap_pid=""
rviz_pid=""
tf_pid=""

source_workspace() {
  set +u
  source /opt/ros/humble/setup.bash
  source "${ROOT_DIR}/install/setup.bash"
  set -u
}

cleanup() {
  for pid in "${rviz_pid}" "${rtabmap_pid}" "${bridge_pid}" "${offboard_pid}" "${tf_pid}" "${px4_pid}" "${agent_pid}"; do
    if [[ -n "${pid}" ]]; then
      kill -TERM -- "-${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  pkill -TERM -f "rviz2.*rtabmap_depth_camera_overlay.rviz" >/dev/null 2>&1 || true
  pkill -TERM -f "rtabmap_slam.*rtabmap" >/dev/null 2>&1 || true
  pkill -TERM -f "odom_child_frame_bridge" >/dev/null 2>&1 || true
  pkill -TERM -f "static_transform_publisher 0 0 0 0 0 0 world map" >/dev/null 2>&1 || true
  pkill -TERM -f "single_vehicle_cable_inspection.launch.py" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "rviz2.*rtabmap_depth_camera_overlay.rviz" >/dev/null 2>&1 || true
  pkill -KILL -f "rtabmap_slam.*rtabmap" >/dev/null 2>&1 || true
  pkill -KILL -f "odom_child_frame_bridge" >/dev/null 2>&1 || true
  pkill -KILL -f "static_transform_publisher 0 0 0 0 0 0 world map" >/dev/null 2>&1 || true
  pkill -KILL -f "single_vehicle_cable_inspection.launch.py" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${RESULT_DIR}" "${SCREENSHOT_DIR}" "${LOG_DIR}/ros"

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; cannot capture RTAB-Map motion RViz screenshot." >&2
  exit 1
fi
if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi
if [[ ! -x "${PX4_SCRIPT}" ]]; then
  echo "PX4 script not found: ${PX4_SCRIPT}" >&2
  exit 1
fi
if [[ ! -f "${RVIZ_CONFIG}" ]]; then
  echo "RViz config does not exist: ${RVIZ_CONFIG}" >&2
  exit 1
fi

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  LD_LIBRARY_PATH="${AGENT_LIB_DIR}:/opt/ros/humble/lib" \
  "${AGENT_BIN}" udp4 -p 8888 >"${AGENT_LOG}" 2>&1 &
agent_pid=$!

for _ in $(seq 1 10); do
  if grep -q "running.*port: 8888" "${AGENT_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -q "running.*port: 8888" "${AGENT_LOG}"; then
  echo "MicroXRCEAgent did not report UDP readiness." >&2
  tail -n 80 "${AGENT_LOG}" >&2 || true
  exit 1
fi

setsid env \
  ROS_VERSION=2 \
  PX4_DIRECT_MODEL=1 \
  PX4_HEADLESS="${PX4_HEADLESS-}" \
  PX4_SYS_AUTOSTART=10015 \
  PX4_MODEL=iris_depth_camera \
  AERIALCORE_WORLD=danube_wires \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC}" \
  LOG_FILE="${PX4_LOG}" \
  "${PX4_SCRIPT}" >"${PX4_WRAPPER_LOG}" 2>&1 &
px4_pid=$!

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  if [[ -f "${PX4_LOG}" ]] &&
     grep -q "Simulator connected on TCP port 4560" "${PX4_LOG}" &&
     grep -q "Startup script returned successfully" "${PX4_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -q "Simulator connected on TCP port 4560" "${PX4_LOG}" ||
   ! grep -q "Startup script returned successfully" "${PX4_LOG}"; then
  echo "PX4/Gazebo did not reach ready state." >&2
  tail -n 120 "${PX4_LOG}" >&2 || true
  exit 1
fi

source_workspace

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  if grep -q '^/fmu/out/vehicle_status$' "${TOPICS_LOG}" &&
     grep -q '^/fmu/out/vehicle_local_position$' "${TOPICS_LOG}" &&
     grep -q '^/camera/points$' "${TOPICS_LOG}" &&
     grep -q '^/zcw/depth_camera/pose$' "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -q '^/fmu/out/vehicle_local_position$' "${TOPICS_LOG}" ||
   ! grep -q '^/camera/points$' "${TOPICS_LOG}" ||
   ! grep -q '^/zcw/depth_camera/pose$' "${TOPICS_LOG}"; then
  echo "Required motion and depth-camera topics were not found." >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 launch zcw_bringup single_vehicle_cable_inspection.launch.py" >"${OFFBOARD_LOG}" 2>&1 &
offboard_pid=$!

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 run zcw_cable_perception odom_child_frame_bridge --ros-args \
    -p input_topic:=/zcw/depth_camera/pose \
    -p output_topic:=/zcw/rtabmap/odom_camera_link \
    -p target_child_frame:=camera_link \
    -p publish_tf:=true" >"${BRIDGE_LOG}" 2>&1 &
bridge_pid=$!

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 run rtabmap_slam rtabmap --ros-args \
    -p database_path:='${RESULT_DIR}/rtabmap_depth_camera_motion_${STAMP}.db' \
    -p frame_id:=camera_link \
    -p subscribe_depth:=false \
    -p subscribe_rgb:=false \
    -p subscribe_scan_cloud:=true \
    -p approx_sync:=false \
    -p wait_for_transform:=0.5 \
    -r scan_cloud:=/camera/points \
    -r odom:=/zcw/rtabmap/odom_camera_link" >"${RTABMAP_LOG}" 2>&1 &
rtabmap_pid=$!

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 world map" >/dev/null 2>&1 &
tf_pid=$!

sleep "${MOTION_SETTLE_SEC}"

timeout 8s ros2 topic echo --once /fmu/out/vehicle_status >"${STATUS_LOG}" 2>&1
timeout 8s ros2 topic echo --once /fmu/out/vehicle_local_position >"${LOCAL_POSITION_LOG}" 2>&1
timeout 20s ros2 topic echo --qos-reliability best_effort --qos-durability volatile --once /camera/points >"${POINTS_SAMPLE_LOG}"

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && rviz2 -d '${RVIZ_CONFIG}'" >"${RVIZ_LOG}" 2>&1 &
rviz_pid=$!

sleep "${GUI_SETTLE_SEC}"
set +o pipefail
RVIZ_WINDOW_ID="$(env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" xwininfo -root -tree 2>/dev/null | awk '/RViz/ {print $1; exit}')"
set -o pipefail

screenshot_ok=0
if [[ -n "${RVIZ_WINDOW_ID}" ]] &&
   env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" import -window "${RVIZ_WINDOW_ID}" "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
  screenshot_ok=1
elif env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" gnome-screenshot -f "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
  screenshot_ok=1
elif env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" import -window root "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
  screenshot_ok=1
fi

rtabmap_ok=false
outputs_ok=false
motion_ok=false
if grep -q "SLAM mode" "${RTABMAP_LOG}" &&
   grep -q "subscribe_scan_cloud = true" "${RTABMAP_LOG}"; then
  rtabmap_ok=true
fi
ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
if grep -q '^/cloud_map$' "${TOPICS_LOG}" &&
   grep -q '^/map$' "${TOPICS_LOG}" &&
   grep -q '^/octomap_occupied_space$' "${TOPICS_LOG}"; then
  outputs_ok=true
fi
if grep -q "arming_state: 2" "${STATUS_LOG}" &&
   grep -q "nav_state: 14" "${STATUS_LOG}" &&
   grep -q "Advancing to waypoint" "${OFFBOARD_LOG}"; then
  motion_ok=true
fi

decision="accepted_rtabmap_depth_camera_motion_rviz_overlay"
reason="rtabmap_motion_backed_rviz_capture_completed"
if [[ "${rtabmap_ok}" != "true" || "${outputs_ok}" != "true" || "${motion_ok}" != "true" || "${screenshot_ok}" != "1" || ! -s "${SCREENSHOT_FILE}" ]]; then
  decision="rejected_rtabmap_depth_camera_motion_rviz_overlay"
  reason="motion_rviz_capture_missing_motion_topic_or_screenshot_evidence"
fi

{
  echo "scope=rtabmap_depth_camera_motion_rviz_overlay"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=true"
  echo "starts_offboard=true"
  echo "arms=true"
  echo "publishes_fmu_in=true"
  echo "uses_gazebo_sensor_topics=true"
  echo "uses_gazebo_pose_as_debug_odom=true"
  echo "claims_slam_quality=false"
  echo "rtabmap_ok=${rtabmap_ok}"
  echo "outputs_ok=${outputs_ok}"
  echo "motion_ok=${motion_ok}"
  echo "screenshot_ok=${screenshot_ok}"
  echo "rviz_window_id=${RVIZ_WINDOW_ID}"
  echo "agent_log=${AGENT_LOG}"
  echo "px4_log=${PX4_LOG}"
  echo "offboard_log=${OFFBOARD_LOG}"
  echo "bridge_log=${BRIDGE_LOG}"
  echo "rtabmap_log=${RTABMAP_LOG}"
  echo "rviz_log=${RVIZ_LOG}"
  echo "status_log=${STATUS_LOG}"
  echo "local_position_log=${LOCAL_POSITION_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "points_sample_log=${POINTS_SAMPLE_LOG}"
  echo "screenshot=${SCREENSHOT_FILE}"
} >"${SUMMARY_FILE}"

echo "RTAB-Map depth camera motion RViz overlay capture completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_rtabmap_depth_camera_motion_rviz_overlay" ]]; then
  tail -n 120 "${OFFBOARD_LOG}" >&2 || true
  tail -n 120 "${RTABMAP_LOG}" >&2 || true
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
