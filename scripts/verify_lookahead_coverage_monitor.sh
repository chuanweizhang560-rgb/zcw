#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_TARGETS="data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
GROUP_ID="${GROUP_ID:-y8_z20}"
FRAME_ID="${FRAME_ID:-map}"
PUBLISH_HZ="${PUBLISH_HZ:-10.0}"
MIN_COVERAGE_RATIO="${MIN_COVERAGE_RATIO:-0.80}"
MAX_TARGET_TO_PATH_M="${MAX_TARGET_TO_PATH_M:-2.0}"
MAX_DATA_AGE_SEC="${MAX_DATA_AGE_SEC:-3.0}"
SETTLE_SEC="${SETTLE_SEC:-5}"
TOPIC_WAIT_SEC="${TOPIC_WAIT_SEC:-15}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-data/logs}"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/lookahead_coverage_monitor_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/lookahead_coverage_monitor_${STAMP}.txt"
PUBLISHER_LOG="${LOG_DIR}/lookahead_coverage_publisher_${STAMP}.log"
SAFETY_LOG="${LOG_DIR}/lookahead_coverage_safety_${STAMP}.log"
COVERAGE_LOG="${LOG_DIR}/lookahead_coverage_monitor_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/lookahead_coverage_topic_list_${STAMP}.log"
COVERAGE_ECHO_LOG="${LOG_DIR}/lookahead_coverage_state_echo_${STAMP}.log"
FORBIDDEN_LOG="${LOG_DIR}/lookahead_coverage_forbidden_topics_${STAMP}.log"

write_summary() {
  local decision="$1"
  local reason="$2"
  local coverage_ok="$3"
  {
    echo "scope=lookahead_coverage_monitor"
    echo "decision=${decision}"
    echo "reason=${reason}"
    echo "starts_ros=true"
    echo "starts_px4=false"
    echo "starts_gazebo=false"
    echo "starts_rviz=false"
    echo "starts_offboard=false"
    echo "arms=false"
    echo "publishes_fmu_in=false"
    echo "offset_path_csv=${OFFSET_PATH_CSV}"
    echo "targets_csv=${TARGETS_CSV}"
    echo "group_id=${GROUP_ID}"
    echo "min_coverage_ratio=${MIN_COVERAGE_RATIO}"
    echo "max_target_to_path_m=${MAX_TARGET_TO_PATH_M}"
    echo "topic_list_log=${TOPIC_LIST_LOG}"
    echo "forbidden_log=${FORBIDDEN_LOG}"
    echo "coverage_echo_log=${COVERAGE_ECHO_LOG}"
    echo "publisher_log=${PUBLISHER_LOG}"
    echo "safety_log=${SAFETY_LOG}"
    echo "coverage_log=${COVERAGE_LOG}"
    echo "coverage_ok=${coverage_ok}"
  } >"${SUMMARY_FILE}"
}

if [[ ! -f "${OFFSET_PATH_CSV}" ]]; then
  echo "Offset path CSV does not exist: ${OFFSET_PATH_CSV}" >&2
  exit 1
fi
if [[ ! -f "${TARGETS_CSV}" ]]; then
  echo "Targets CSV does not exist: ${TARGETS_CSV}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${RESULT_DIR}"
export ROS_LOG_DIR="${LOG_DIR}/ros"
mkdir -p "${ROS_LOG_DIR}"

source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

cleanup() {
  for pid in "${COVERAGE_PID:-}" "${SAFETY_PID:-}" "${PUBLISHER_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

ros2 run zcw_cable_perception lookahead_path_publisher \
  --ros-args \
  -p "offset_path_csv:=${OFFSET_PATH_CSV}" \
  -p "targets_csv:=${TARGETS_CSV}" \
  -p "group_id:=${GROUP_ID}" \
  -p "frame_id:=${FRAME_ID}" \
  -p "publish_hz:=${PUBLISH_HZ}" \
  >"${PUBLISHER_LOG}" 2>&1 &
PUBLISHER_PID=$!

ros2 run zcw_cable_perception lookahead_safety_monitor \
  --ros-args \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${SAFETY_LOG}" 2>&1 &
SAFETY_PID=$!

ros2 run zcw_cable_perception lookahead_coverage_monitor \
  --ros-args \
  -p "min_coverage_ratio:=${MIN_COVERAGE_RATIO}" \
  -p "max_target_to_path_m:=${MAX_TARGET_TO_PATH_M}" \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${COVERAGE_LOG}" 2>&1 &
COVERAGE_PID=$!

sleep "${SETTLE_SEC}"

topic_ready=0
for _ in $(seq 1 "${TOPIC_WAIT_SEC}"); do
  ros2 topic list --no-daemon | sort >"${TOPIC_LIST_LOG}"
  if grep -q '^/zcw/cable/dry_run/coverage_state$' "${TOPIC_LIST_LOG}"; then
    topic_ready=1
    break
  fi
  sleep 1
done

if [[ "${topic_ready}" -ne 1 ]]; then
  write_summary "rejected_lookahead_coverage_monitor" "coverage_state_topic_missing" "false"
  echo "Lookahead coverage monitor smoke completed."
  echo "Summary: ${SUMMARY_FILE}"
  echo "Coverage echo log: ${COVERAGE_ECHO_LOG}"
  exit 1
fi

grep '^/fmu/in/' "${TOPIC_LIST_LOG}" >"${FORBIDDEN_LOG}" || true
if [[ -s "${FORBIDDEN_LOG}" ]]; then
  echo "Forbidden PX4 input topics are present:" >&2
  cat "${FORBIDDEN_LOG}" >&2
  write_summary "rejected_lookahead_coverage_monitor" "forbidden_px4_input_topic_present" "false"
  exit 1
fi

coverage_ok=0
for _ in $(seq 1 3); do
  timeout 8s ros2 topic echo --full-length /zcw/cable/dry_run/coverage_state >"${COVERAGE_ECHO_LOG}" || true
  if grep -q 'coverage_ready=true' "${COVERAGE_ECHO_LOG}"; then
    coverage_ok=1
    break
  fi
  sleep 1
done

decision="accepted_lookahead_coverage_monitor"
reason="coverage_monitor_reaches_ready_without_px4_inputs"
if [[ "${coverage_ok}" -ne 1 ]]; then
  decision="rejected_lookahead_coverage_monitor"
  reason="coverage_monitor_did_not_reach_ready"
fi

write_summary "${decision}" "${reason}" "$([[ "${coverage_ok}" -eq 1 ]] && echo true || echo false)"

echo "Lookahead coverage monitor smoke completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Coverage echo log: ${COVERAGE_ECHO_LOG}"

if [[ "${decision}" != "accepted_lookahead_coverage_monitor" ]]; then
  exit 1
fi
