#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
RVIZ_CONFIG="${RVIZ_CONFIG:-${ROOT_DIR}/ros2_ws/src/zcw_cable_perception/rviz/rtabmap_depth_camera_overlay.rviz}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/rtabmap_depth_camera_rviz_overlay_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_depth_camera_rviz_overlay_${STAMP}.txt"
PX4_LOG="${LOG_DIR}/rtabmap_depth_camera_rviz_px4_${STAMP}.log"
BRIDGE_LOG="${LOG_DIR}/rtabmap_depth_camera_rviz_odom_bridge_${STAMP}.log"
RTABMAP_LOG="${LOG_DIR}/rtabmap_depth_camera_rviz_node_${STAMP}.log"
RVIZ_LOG="${LOG_DIR}/rtabmap_depth_camera_rviz_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/rtabmap_depth_camera_rviz_topics_${STAMP}.log"
POINTS_SAMPLE_LOG="${LOG_DIR}/rtabmap_depth_camera_rviz_points_sample_${STAMP}.log"
SCREENSHOT_FILE="${SCREENSHOT_DIR}/rtabmap_depth_camera_rviz_overlay_${STAMP}.png"
PX4_WAIT_SEC="${PX4_WAIT_SEC:-90}"
TOPIC_WAIT_SEC="${TOPIC_WAIT_SEC:-60}"
GUI_SETTLE_SEC="${GUI_SETTLE_SEC:-10}"

runner_pid=""
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
  for pid in "${rviz_pid}" "${rtabmap_pid}" "${bridge_pid}" "${tf_pid}" "${runner_pid}"; do
    if [[ -n "${pid}" ]]; then
      kill -TERM -- "-${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  pkill -TERM -f "rviz2.*rtabmap_depth_camera_overlay.rviz" >/dev/null 2>&1 || true
  pkill -TERM -f "rtabmap_slam.*rtabmap" >/dev/null 2>&1 || true
  pkill -TERM -f "odom_child_frame_bridge" >/dev/null 2>&1 || true
  pkill -TERM -f "static_transform_publisher 0 0 0 0 0 0 world map" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "rviz2.*rtabmap_depth_camera_overlay.rviz" >/dev/null 2>&1 || true
  pkill -KILL -f "rtabmap_slam.*rtabmap" >/dev/null 2>&1 || true
  pkill -KILL -f "odom_child_frame_bridge" >/dev/null 2>&1 || true
  pkill -KILL -f "static_transform_publisher 0 0 0 0 0 0 world map" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${RESULT_DIR}" "${SCREENSHOT_DIR}" "${LOG_DIR}/ros"

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; cannot capture RTAB-Map RViz screenshot." >&2
  exit 1
fi
if [[ ! -f "${RVIZ_CONFIG}" ]]; then
  echo "RViz config does not exist: ${RVIZ_CONFIG}" >&2
  exit 1
fi

setsid env \
  ROS_VERSION=2 \
  PX4_DIRECT_MODEL=1 \
  PX4_HEADLESS="${PX4_HEADLESS-}" \
  PX4_SYS_AUTOSTART=10015 \
  PX4_MODEL=iris_depth_camera \
  AERIALCORE_WORLD=danube_wires \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-180}" \
  LOG_FILE="${PX4_LOG}" \
  "${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh" >/dev/null 2>&1 &
runner_pid=$!

for _ in $(seq 1 "${PX4_WAIT_SEC}"); do
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
  tail -n 100 "${PX4_LOG}" >&2 || true
  exit 1
fi

sleep "${GUI_SETTLE_SEC}"
source_workspace

for _ in $(seq 1 "${TOPIC_WAIT_SEC}"); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  if grep -q '^/camera/points$' "${TOPICS_LOG}" &&
     grep -q '^/zcw/depth_camera/pose$' "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -q '^/camera/points$' "${TOPICS_LOG}" ||
   ! grep -q '^/zcw/depth_camera/pose$' "${TOPICS_LOG}"; then
  echo "Missing depth camera input topics." >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi

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
    -p database_path:='${RESULT_DIR}/rtabmap_depth_camera_rviz_${STAMP}.db' \
    -p frame_id:=camera_link \
    -p subscribe_depth:=false \
    -p subscribe_rgb:=false \
    -p subscribe_scan_cloud:=true \
    -p approx_sync:=false \
    -p wait_for_transform:=0.5 \
    -r scan_cloud:=/camera/points \
    -r odom:=/zcw/rtabmap/odom_camera_link" >"${RTABMAP_LOG}" 2>&1 &
rtabmap_pid=$!

rtabmap_ok=false
outputs_ok=false
for _ in $(seq 1 "${TOPIC_WAIT_SEC}"); do
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
  if [[ "${rtabmap_ok}" == "true" && "${outputs_ok}" == "true" ]]; then
    break
  fi
  sleep 1
done

timeout 20s ros2 topic echo --qos-reliability best_effort --qos-durability volatile --once /camera/points >"${POINTS_SAMPLE_LOG}"

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 world map" >/dev/null 2>&1 &
tf_pid=$!

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

decision="accepted_rtabmap_depth_camera_rviz_overlay"
reason="rtabmap_map_cloud_octomap_rendered_in_rviz_capture"
if [[ "${rtabmap_ok}" != "true" || "${outputs_ok}" != "true" || "${screenshot_ok}" != "1" || ! -s "${SCREENSHOT_FILE}" ]]; then
  decision="rejected_rtabmap_depth_camera_rviz_overlay"
  reason="rviz_capture_missing_topic_or_screenshot_evidence"
fi

{
  echo "scope=rtabmap_depth_camera_rviz_overlay"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=true"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "uses_gazebo_sensor_topics=true"
  echo "uses_gazebo_pose_as_debug_odom=true"
  echo "claims_slam_quality=false"
  echo "rtabmap_ok=${rtabmap_ok}"
  echo "outputs_ok=${outputs_ok}"
  echo "screenshot_ok=${screenshot_ok}"
  echo "rviz_window_id=${RVIZ_WINDOW_ID}"
  echo "px4_log=${PX4_LOG}"
  echo "bridge_log=${BRIDGE_LOG}"
  echo "rtabmap_log=${RTABMAP_LOG}"
  echo "rviz_log=${RVIZ_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "points_sample_log=${POINTS_SAMPLE_LOG}"
  echo "screenshot=${SCREENSHOT_FILE}"
} >"${SUMMARY_FILE}"

echo "RTAB-Map depth camera RViz overlay capture completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_rtabmap_depth_camera_rviz_overlay" ]]; then
  tail -n 120 "${RTABMAP_LOG}" >&2 || true
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
