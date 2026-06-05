#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/rtabmap_depth_camera_smoke_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_depth_camera_smoke_${STAMP}.txt"
PX4_LOG="${LOG_DIR}/rtabmap_depth_camera_px4_${STAMP}.log"
BRIDGE_LOG="${LOG_DIR}/rtabmap_depth_camera_odom_bridge_${STAMP}.log"
RTABMAP_LOG="${LOG_DIR}/rtabmap_depth_camera_node_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/rtabmap_depth_camera_topics_${STAMP}.log"
POINTS_SAMPLE_LOG="${LOG_DIR}/rtabmap_depth_camera_points_sample_${STAMP}.log"
ODOM_SAMPLE_LOG="${LOG_DIR}/rtabmap_depth_camera_odom_sample_${STAMP}.log"
DATABASE_PATH="${RESULT_DIR}/rtabmap_depth_camera_${STAMP}.db"
PX4_WAIT_SEC="${PX4_WAIT_SEC:-90}"
TOPIC_WAIT_SEC="${TOPIC_WAIT_SEC:-60}"
GUI_SETTLE_SEC="${GUI_SETTLE_SEC:-8}"

runner_pid=""
bridge_pid=""
rtabmap_pid=""

cleanup() {
  for pid in "${rtabmap_pid}" "${bridge_pid}" "${runner_pid}"; do
    if [[ -n "${pid}" ]]; then
      kill -TERM -- "-${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  pkill -TERM -f "rtabmap_slam.*rtabmap" >/dev/null 2>&1 || true
  pkill -TERM -f "odom_child_frame_bridge" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "rtabmap_slam.*rtabmap" >/dev/null 2>&1 || true
  pkill -KILL -f "odom_child_frame_bridge" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${RESULT_DIR}" "${LOG_DIR}/ros"

source_workspace() {
  set +u
  source /opt/ros/humble/setup.bash
  source "${ROOT_DIR}/install/setup.bash"
  set -u
}

if [[ -z "${PX4_HEADLESS-}" && -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; depth camera rendering requires Gazebo GUI mode." >&2
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

if ! grep -q '^/camera/points$' "${TOPICS_LOG}"; then
  echo "Missing /camera/points topic." >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi

if ! grep -q '^/zcw/depth_camera/pose$' "${TOPICS_LOG}"; then
  echo "Missing /zcw/depth_camera/pose topic." >&2
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

for _ in $(seq 1 20); do
  if timeout 5s ros2 topic echo --once /zcw/rtabmap/odom_camera_link >"${ODOM_SAMPLE_LOG}" 2>/dev/null; then
    break
  fi
  sleep 1
done

if ! grep -q "child_frame_id: camera_link" "${ODOM_SAMPLE_LOG}"; then
  echo "Bridged odometry did not use child_frame_id=camera_link." >&2
  cat "${ODOM_SAMPLE_LOG}" >&2 || true
  exit 1
fi

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 run rtabmap_slam rtabmap --ros-args \
    -p database_path:='${DATABASE_PATH}' \
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
  if grep -Eq '^/rtabmap/(mapData|cloud_map|info|mapGraph)$' "${TOPICS_LOG}" ||
     grep -q '^/map$' "${TOPICS_LOG}"; then
    outputs_ok=true
  fi

  if [[ "${rtabmap_ok}" == "true" && "${outputs_ok}" == "true" ]]; then
    break
  fi
  sleep 1
done

timeout 20s ros2 topic echo --qos-reliability best_effort --qos-durability volatile --once /camera/points >"${POINTS_SAMPLE_LOG}"

points_ok=false
if grep -q "frame_id: camera_link" "${POINTS_SAMPLE_LOG}" &&
   grep -q "^width:" "${POINTS_SAMPLE_LOG}" &&
   grep -q "^height:" "${POINTS_SAMPLE_LOG}"; then
  points_ok=true
fi

decision="accepted_rtabmap_depth_camera_smoke"
reason="rtabmap_started_with_gazebo_depth_camera_topics_and_frame_bridge"
if [[ "${rtabmap_ok}" != "true" || "${outputs_ok}" != "true" || "${points_ok}" != "true" ]]; then
  decision="rejected_rtabmap_depth_camera_smoke"
  reason="rtabmap_depth_camera_smoke_missing_expected_topic_or_log_evidence"
fi

{
  echo "scope=rtabmap_depth_camera_smoke"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "uses_gazebo_sensor_topics=true"
  echo "uses_gazebo_pose_as_debug_odom=true"
  echo "claims_slam_quality=false"
  echo "rtabmap_ok=${rtabmap_ok}"
  echo "outputs_ok=${outputs_ok}"
  echo "points_ok=${points_ok}"
  echo "database_path=${DATABASE_PATH}"
  echo "px4_log=${PX4_LOG}"
  echo "bridge_log=${BRIDGE_LOG}"
  echo "rtabmap_log=${RTABMAP_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "points_sample_log=${POINTS_SAMPLE_LOG}"
  echo "odom_sample_log=${ODOM_SAMPLE_LOG}"
} >"${SUMMARY_FILE}"

echo "RTAB-Map depth camera smoke completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_rtabmap_depth_camera_smoke" ]]; then
  tail -n 120 "${RTABMAP_LOG}" >&2 || true
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
