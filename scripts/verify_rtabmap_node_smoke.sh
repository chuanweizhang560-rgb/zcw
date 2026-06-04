#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_node_smoke_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_node_smoke_${STAMP}.txt"
RTABMAP_LOG="${LOG_DIR}/rtabmap_node_smoke_${STAMP}.log"
NODE_LIST_LOG="${LOG_DIR}/rtabmap_node_list_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/rtabmap_topic_list_${STAMP}.log"
DATABASE_PATH="${RESULT_DIR}/rtabmap_node_smoke_${STAMP}.db"

rtabmap_pid=""

cleanup() {
  if [[ -n "${rtabmap_pid}" ]]; then
    kill -TERM -- "-${rtabmap_pid}" >/dev/null 2>&1 || true
    wait "${rtabmap_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
mkdir -p "${LOG_DIR}/ros"

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && ros2 run rtabmap_slam rtabmap --ros-args \
  -p database_path:='${DATABASE_PATH}' \
  -p subscribe_depth:=false \
  -p subscribe_rgb:=false \
  -p subscribe_scan_cloud:=false" >"${RTABMAP_LOG}" 2>&1 &
rtabmap_pid=$!

node_ok=false
slam_mode_ok=false
for _ in $(seq 1 15); do
  if grep -q "SLAM mode" "${RTABMAP_LOG}" && grep -q "Setup callbacks" "${RTABMAP_LOG}"; then
    slam_mode_ok=true
  fi

  set +e
  timeout 5s bash -lc "source /opt/ros/humble/setup.bash && ros2 node list --no-daemon" >"${NODE_LIST_LOG}" 2>&1
  node_status=$?
  set -e

  if [[ "${node_status}" -eq 0 ]] && grep -q '^/rtabmap$' "${NODE_LIST_LOG}"; then
    node_ok=true
    break
  fi
  sleep 1
done

if grep -q "SLAM mode" "${RTABMAP_LOG}" && grep -q "Setup callbacks" "${RTABMAP_LOG}"; then
  slam_mode_ok=true
fi

set +e
timeout 5s bash -lc "source /opt/ros/humble/setup.bash && ros2 topic list --no-daemon | sort" >"${TOPIC_LIST_LOG}" 2>&1
topic_status=$?
set -e

topic_list_ok=false
if [[ "${topic_status}" -eq 0 ]]; then
  topic_list_ok=true
fi

decision="accepted_rtabmap_node_smoke"
reason="rtabmap_slam_node_started_in_readonly_no_sensor_smoke"
if [[ "${node_ok}" != "true" || "${slam_mode_ok}" != "true" || "${topic_list_ok}" != "true" ]]; then
  decision="rejected_rtabmap_node_smoke"
  reason="rtabmap_slam_node_did_not_reach_expected_readonly_smoke_state"
fi

{
  echo "scope=rtabmap_node_smoke"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "node_ok=${node_ok}"
  echo "slam_mode_ok=${slam_mode_ok}"
  echo "topic_list_ok=${topic_list_ok}"
  echo "database_path=${DATABASE_PATH}"
  echo "rtabmap_log=${RTABMAP_LOG}"
  echo "node_list_log=${NODE_LIST_LOG}"
  echo "topic_list_log=${TOPIC_LIST_LOG}"
} >"${SUMMARY_FILE}"

echo "RTAB-Map node smoke completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_rtabmap_node_smoke" ]]; then
  tail -n 80 "${RTABMAP_LOG}" >&2 || true
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
