#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/rtabmap_depth_camera_rgbd_smoke_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_depth_camera_rgbd_smoke_${STAMP}.txt"
PX4_LOG="${LOG_DIR}/rtabmap_depth_camera_rgbd_px4_${STAMP}.log"
BRIDGE_LOG="${LOG_DIR}/rtabmap_depth_camera_rgbd_odom_bridge_${STAMP}.log"
RTABMAP_LOG="${LOG_DIR}/rtabmap_depth_camera_rgbd_node_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/rtabmap_depth_camera_rgbd_topics_${STAMP}.log"
RGB_SAMPLE_LOG="${LOG_DIR}/rtabmap_depth_camera_rgbd_rgb_sample_${STAMP}.log"
DEPTH_SAMPLE_LOG="${LOG_DIR}/rtabmap_depth_camera_rgbd_depth_sample_${STAMP}.log"
ODOM_SAMPLE_LOG="${LOG_DIR}/rtabmap_depth_camera_rgbd_odom_sample_${STAMP}.log"
DATABASE_PATH="${RESULT_DIR}/rtabmap_depth_camera_rgbd_${STAMP}.db"
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
  pkill -TERM -f gzclient >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "rtabmap_slam.*rtabmap" >/dev/null 2>&1 || true
  pkill -KILL -f "odom_child_frame_bridge" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  pkill -KILL -f gzclient >/dev/null 2>&1 || true
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
  if grep -q '^/camera/image_raw$' "${TOPICS_LOG}" &&
     grep -q '^/camera/depth/image_raw$' "${TOPICS_LOG}" &&
     grep -q '^/camera/camera_info$' "${TOPICS_LOG}" &&
     grep -q '^/zcw/depth_camera/pose$' "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done

for topic in /camera/image_raw /camera/depth/image_raw /camera/camera_info /zcw/depth_camera/pose; do
  if ! grep -q "^${topic}$" "${TOPICS_LOG}"; then
    echo "Missing required topic: ${topic}" >&2
    cat "${TOPICS_LOG}" >&2 || true
    exit 1
  fi
done

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
    -p subscribe_depth:=true \
    -p subscribe_rgb:=true \
    -p subscribe_scan_cloud:=false \
    -p approx_sync:=true \
    -p wait_for_transform:=0.5 \
    -r rgb/image:=/camera/image_raw \
    -r depth/image:=/camera/depth/image_raw \
    -r rgb/camera_info:=/camera/camera_info \
    -r odom:=/zcw/rtabmap/odom_camera_link" >"${RTABMAP_LOG}" 2>&1 &
rtabmap_pid=$!

rtabmap_ok=false
outputs_ok=false
for _ in $(seq 1 "${TOPIC_WAIT_SEC}"); do
  if grep -q "subscribe_depth = true" "${RTABMAP_LOG}" &&
     grep -q "subscribe_rgb = true" "${RTABMAP_LOG}"; then
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

if [[ "${rtabmap_ok}" != "true" ]]; then
  echo "RTAB-Map RGB-D node did not report expected RGB-D subscription mode." >&2
  cat "${RTABMAP_LOG}" >&2 || true
  exit 1
fi

if [[ "${outputs_ok}" != "true" ]]; then
  echo "RTAB-Map RGB-D node did not expose expected output topics." >&2
  cat "${TOPICS_LOG}" >&2 || true
  cat "${RTABMAP_LOG}" >&2 || true
  exit 1
fi

timeout 20s ros2 topic echo --once /camera/image_raw >"${RGB_SAMPLE_LOG}"
timeout 20s ros2 topic echo --once /camera/depth/image_raw >"${DEPTH_SAMPLE_LOG}"

if ! grep -q '^encoding:' "${RGB_SAMPLE_LOG}" ||
   ! grep -q '^height:' "${RGB_SAMPLE_LOG}" ||
   ! grep -q '^width:' "${RGB_SAMPLE_LOG}"; then
  echo "RGB image sample did not contain expected fields." >&2
  cat "${RGB_SAMPLE_LOG}" >&2 || true
  exit 1
fi

if ! grep -q '^encoding:' "${DEPTH_SAMPLE_LOG}" ||
   ! grep -q '^height:' "${DEPTH_SAMPLE_LOG}" ||
   ! grep -q '^width:' "${DEPTH_SAMPLE_LOG}"; then
  echo "Depth image sample did not contain expected fields." >&2
  cat "${DEPTH_SAMPLE_LOG}" >&2 || true
  exit 1
fi

{
  echo "decision=accepted_rtabmap_depth_camera_rgbd_smoke"
  echo "reason=rtabmap_rgbd_mode_started_with_depth_camera_contract"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "rtabmap_rgbd_mode=true"
  echo "rgb_topic=/camera/image_raw"
  echo "depth_topic=/camera/depth/image_raw"
  echo "camera_info_topic=/camera/camera_info"
  echo "odom_topic=/zcw/rtabmap/odom_camera_link"
  echo "database_path=${DATABASE_PATH}"
  echo "px4_log=${PX4_LOG}"
  echo "bridge_log=${BRIDGE_LOG}"
  echo "rtabmap_log=${RTABMAP_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "rgb_sample_log=${RGB_SAMPLE_LOG}"
  echo "depth_sample_log=${DEPTH_SAMPLE_LOG}"
  echo "odom_sample_log=${ODOM_SAMPLE_LOG}"
} >"${SUMMARY_FILE}"

cleanup
runner_pid=""
bridge_pid=""
rtabmap_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "RTAB-Map RGB-D smoke verified."
echo "Summary: ${SUMMARY_FILE}"
