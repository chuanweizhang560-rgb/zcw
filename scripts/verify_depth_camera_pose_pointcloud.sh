#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/depth_camera_pose_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/depth_camera_pose_topics_${STAMP}.log"
TYPES_LOG="${LOG_DIR}/depth_camera_pose_types_${STAMP}.log"
POINTS_SAMPLE_LOG="${LOG_DIR}/depth_camera_pose_points_sample_${STAMP}.log"
POSE_SAMPLE_LOG="${LOG_DIR}/depth_camera_pose_pose_sample_${STAMP}.log"
SCREENSHOT_FILE="${SCREENSHOT_DIR}/depth_camera_pose_gui_${STAMP}.png"
runner_pid=""

cleanup() {
  if [[ -n "${runner_pid}" ]]; then
    kill -TERM -- "-${runner_pid}" >/dev/null 2>&1 || true
    sleep 2
    kill -KILL -- "-${runner_pid}" >/dev/null 2>&1 || true
    wait "${runner_pid}" >/dev/null 2>&1 || true
  fi
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${SCREENSHOT_DIR}"

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

for _ in $(seq 1 "${PX4_WAIT_SEC:-90}"); do
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
  tail -n 80 "${PX4_LOG}" >&2 || true
  exit 1
fi

sleep "${GUI_SETTLE_SEC:-8}"

if [[ -z "${PX4_HEADLESS-}" ]]; then
  screenshot_ok=0
  set +o pipefail
  window_id="$(
    env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      xwininfo -root -tree 2>/dev/null | awk '/"Gazebo"/ {print $1; exit}'
  )"
  set -o pipefail
  if [[ -n "${window_id}" ]] &&
     env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
       import -window "${window_id}" "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  elif env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      gnome-screenshot -f "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  elif env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      import -window root "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  fi

  if [[ "${screenshot_ok}" != "1" || ! -s "${SCREENSHOT_FILE}" ]]; then
    echo "Screenshot capture failed." >&2
    exit 1
  fi

  if [[ -n "${window_id}" ]]; then
    echo "Gazebo window id: ${window_id}" >"${SCREENSHOT_FILE}.window_id.txt"
  fi
fi

set +u
source /opt/ros/humble/setup.bash
set -u

points_topic="/camera/points"
pose_topic="/zcw/depth_camera/pose"

for _ in $(seq 1 "${TOPIC_WAIT_SEC:-45}"); do
  if ! kill -0 "${runner_pid}" >/dev/null 2>&1; then
    echo "PX4/Gazebo runner exited before depth camera topics became available." >&2
    tail -n 120 "${PX4_LOG}" >&2 || true
    exit 1
  fi

  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  : >"${TYPES_LOG}"
  while IFS= read -r topic; do
    [[ -z "${topic}" ]] && continue
    echo "${topic} $(ros2 topic type "${topic}" 2>/dev/null || true)" >>"${TYPES_LOG}"
  done <"${TOPICS_LOG}"

  if grep -q "^${points_topic} sensor_msgs/msg/PointCloud2$" "${TYPES_LOG}" &&
     grep -q "^${pose_topic} nav_msgs/msg/Odometry$" "${TYPES_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -q "^${points_topic} sensor_msgs/msg/PointCloud2$" "${TYPES_LOG}"; then
  echo "Depth camera PointCloud2 topic was not found: ${points_topic}" >&2
  cat "${TYPES_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "^${pose_topic} nav_msgs/msg/Odometry$" "${TYPES_LOG}"; then
  echo "Depth camera pose topic was not found: ${pose_topic}" >&2
  cat "${TYPES_LOG}" >&2 || true
  exit 1
fi

timeout 20s ros2 topic echo --qos-reliability best_effort --qos-durability volatile --once "${points_topic}" >"${POINTS_SAMPLE_LOG}"
timeout 20s ros2 topic echo --once "${pose_topic}" >"${POSE_SAMPLE_LOG}"

if ! grep -q "^width:" "${POINTS_SAMPLE_LOG}" ||
   ! grep -q "^height:" "${POINTS_SAMPLE_LOG}" ||
   ! grep -q "^point_step:" "${POINTS_SAMPLE_LOG}" ||
   ! grep -q "^data:" "${POINTS_SAMPLE_LOG}"; then
  echo "Depth PointCloud2 sample did not contain expected fields." >&2
  sed -n '1,120p' "${POINTS_SAMPLE_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "frame_id: world" "${POSE_SAMPLE_LOG}" ||
   ! grep -q "child_frame_id:" "${POSE_SAMPLE_LOG}" ||
   ! grep -q "pose:" "${POSE_SAMPLE_LOG}"; then
  echo "Depth pose sample did not contain expected odometry fields." >&2
  sed -n '1,120p' "${POSE_SAMPLE_LOG}" >&2 || true
  exit 1
fi

cleanup
runner_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "Depth camera PointCloud2 + pose verified."
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Topics log: ${TOPICS_LOG}"
echo "Types log: ${TYPES_LOG}"
echo "Points sample log: ${POINTS_SAMPLE_LOG}"
echo "Pose sample log: ${POSE_SAMPLE_LOG}"
if [[ -s "${SCREENSHOT_FILE}" ]]; then
  echo "Screenshot: ${SCREENSHOT_FILE}"
fi
