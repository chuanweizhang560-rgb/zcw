#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/depth_camera_rgbd_imu_contract_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/depth_camera_rgbd_imu_contract_topics_${STAMP}.log"
SUMMARY_DIR="${ROOT_DIR}/data/results/depth_camera_rgbd_imu_contract_${STAMP}"
SUMMARY_FILE="${SUMMARY_DIR}/depth_camera_rgbd_imu_contract_${STAMP}.txt"
runner_pid=""

REQUIRED_TOPICS=(
  "/camera/image_raw"
  "/camera/camera_info"
  "/camera/depth/image_raw"
  "/camera/depth/camera_info"
  "/camera/points"
  "/imu"
)

cleanup() {
  if [[ -n "${runner_pid}" ]]; then
    kill -TERM -- "-${runner_pid}" >/dev/null 2>&1 || true
    sleep 2
    kill -KILL -- "-${runner_pid}" >/dev/null 2>&1 || true
    wait "${runner_pid}" >/dev/null 2>&1 || true
  fi
  pkill -TERM -f "make px4_sitl gazebo-classic_iris_depth_camera" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  pkill -TERM -f gzclient >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "make px4_sitl gazebo-classic_iris_depth_camera" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  pkill -KILL -f gzclient >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${SUMMARY_DIR}"

setsid env \
  ROS_VERSION=2 \
  PX4_MODEL=iris_depth_camera \
  AERIALCORE_WORLD=danube_wires \
  PX4_DIRECT_MODEL=1 \
  PX4_SYS_AUTOSTART=10015 \
  PX4_HEADLESS="${PX4_HEADLESS-}" \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-180}" \
  LOG_FILE="${PX4_LOG}" \
  "${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh" >/dev/null 2>&1 &
runner_pid=$!

for _ in $(seq 1 "${PX4_WAIT_SEC:-120}"); do
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

set +u
source /opt/ros/humble/setup.bash
set -u

for _ in $(seq 1 "${TOPIC_WAIT_SEC:-60}"); do
  ros2 topic list -t --no-daemon | sort >"${TOPICS_LOG}" || true
  all_present=true
  for topic in "${REQUIRED_TOPICS[@]}"; do
    if ! grep -q "^${topic} " "${TOPICS_LOG}"; then
      all_present=false
      break
    fi
  done
  if [[ "${all_present}" == "true" ]]; then
    break
  fi
  sleep 1
done

all_present=true
for topic in "${REQUIRED_TOPICS[@]}"; do
  if ! grep -q "^${topic} " "${TOPICS_LOG}"; then
    all_present=false
    break
  fi
done

decision="rejected_depth_camera_rgbd_imu_contract"
reason="required_rgbd_or_imu_topics_missing"
if [[ "${all_present}" == "true" ]]; then
  decision="accepted_depth_camera_rgbd_imu_contract"
  reason="rgbd_and_native_imu_topics_present"
fi

{
  echo "decision=${decision}"
  echo "reason=${reason}"
  for topic in "${REQUIRED_TOPICS[@]}"; do
    if grep -q "^${topic} " "${TOPICS_LOG}"; then
      echo "${topic}=$(grep -E "^${topic} " "${TOPICS_LOG}" | awk '{print $2}')"
    else
      echo "${topic}=missing"
    fi
  done
  echo "px4_log=${PX4_LOG}"
  echo "topics_log=${TOPICS_LOG}"
} >"${SUMMARY_FILE}"

cleanup
runner_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "Depth camera RGB-D + IMU contract verified."
echo "Summary: ${SUMMARY_FILE}"
