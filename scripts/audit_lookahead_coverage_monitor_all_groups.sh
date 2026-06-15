#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

GROUPS_CSV="${GROUPS_CSV:-data/results/cable_tracking_envelope_20260615_093659/cable_tracking_envelope_groups_20260615_093659.csv}"
MIN_COVERAGE_RATIO="${MIN_COVERAGE_RATIO:-0.80}"
MAX_TARGET_TO_PATH_M="${MAX_TARGET_TO_PATH_M:-2.0}"
SETTLE_SEC="${SETTLE_SEC:-5}"
TOPIC_WAIT_SEC="${TOPIC_WAIT_SEC:-15}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
LOG_DIR="${LOG_DIR:-data/logs}"
RESULT_DIR="${RESULT_ROOT}/lookahead_coverage_monitor_all_groups_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/lookahead_coverage_monitor_all_groups_${STAMP}.txt"
GROUP_RESULT_CSV="${RESULT_DIR}/lookahead_coverage_monitor_all_groups_${STAMP}.csv"
RUN_LOG="${LOG_DIR}/lookahead_coverage_monitor_all_groups_${STAMP}.log"

if [[ ! -f "${GROUPS_CSV}" ]]; then
  echo "Group CSV does not exist: ${GROUPS_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"

mapfile -t GROUP_IDS < <(tail -n +2 "${GROUPS_CSV}" | cut -d, -f1 | awk 'NF' | sort -u)
if [[ "${#GROUP_IDS[@]}" -eq 0 ]]; then
  echo "No group ids found in ${GROUPS_CSV}" >&2
  exit 1
fi

echo "group_id,ros_domain_id,decision,coverage_ok,coverage_ratio,path_points,covered_points,target_samples,summary_file,coverage_echo_log" >"${GROUP_RESULT_CSV}"

accepted_count=0
group_index=0
for group_id in "${GROUP_IDS[@]}"; do
  domain_id=$((80 + group_index))
  echo "Running coverage monitor smoke for ${group_id}" | tee -a "${RUN_LOG}"
  set +e
  run_output="$(
    GROUP_ID="${group_id}" \
    ROS_DOMAIN_ID="${domain_id}" \
    MIN_COVERAGE_RATIO="${MIN_COVERAGE_RATIO}" \
    MAX_TARGET_TO_PATH_M="${MAX_TARGET_TO_PATH_M}" \
    SETTLE_SEC="${SETTLE_SEC}" \
    TOPIC_WAIT_SEC="${TOPIC_WAIT_SEC}" \
    scripts/verify_lookahead_coverage_monitor.sh 2>&1
  )"
  run_status=$?
  set -e
  echo "${run_output}" >>"${RUN_LOG}"

  summary_file="$(echo "${run_output}" | awk '/^Summary: / {print $2}' | tail -1)"
  if [[ -z "${summary_file}" || ! -f "${summary_file}" ]]; then
    echo "${group_id},${domain_id},missing_summary,false,nan,0,0,0,," >>"${GROUP_RESULT_CSV}"
    echo "Missing per-group summary for ${group_id}; run status ${run_status}" | tee -a "${RUN_LOG}"
    continue
  fi

  decision="$(awk -F= '/^decision=/ {print $2}' "${summary_file}" | tail -1)"
  coverage_ok="$(awk -F= '/^coverage_ok=/ {print $2}' "${summary_file}" | tail -1)"
  coverage_echo_log="$(awk -F= '/^coverage_echo_log=/ {print $2}' "${summary_file}" | tail -1)"

  coverage_ratio="nan"
  path_points="0"
  covered_points="0"
  target_samples="0"
  if [[ -f "${coverage_echo_log}" ]]; then
    coverage_ratio="$(grep -o '; coverage_ratio=[^;]*' "${coverage_echo_log}" | tail -1 | cut -d= -f2 | tr -d ' ')"
    path_points="$(grep -o 'path_points=[^;]*' "${coverage_echo_log}" | tail -1 | cut -d= -f2 | tr -d ' ')"
    covered_points="$(grep -o 'covered_points=[^;]*' "${coverage_echo_log}" | tail -1 | cut -d= -f2 | tr -d ' ')"
    target_samples="$(grep -o 'target_samples=[^;]*' "${coverage_echo_log}" | tail -1 | cut -d= -f2 | tr -d ' ')"
  fi

  if [[ "${decision}" == "accepted_lookahead_coverage_monitor" && "${coverage_ok}" == "true" ]]; then
    accepted_count=$((accepted_count + 1))
  fi

  echo "${group_id},${domain_id},${decision},${coverage_ok},${coverage_ratio},${path_points},${covered_points},${target_samples},${summary_file},${coverage_echo_log}" >>"${GROUP_RESULT_CSV}"

  if [[ "${run_status}" -ne 0 ]]; then
    echo "Group ${group_id} returned non-zero status ${run_status}" | tee -a "${RUN_LOG}"
  fi
  group_index=$((group_index + 1))
  sleep 2
done

decision="accepted_lookahead_coverage_monitor_all_groups"
reason="all_groups_reach_dry_run_coverage_ready_without_px4_inputs"
if [[ "${accepted_count}" -ne "${#GROUP_IDS[@]}" ]]; then
  decision="rejected_lookahead_coverage_monitor_all_groups"
  reason="one_or_more_groups_failed_dry_run_coverage_ready"
fi

{
  echo "scope=lookahead_coverage_monitor_all_groups"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "groups_csv=${GROUPS_CSV}"
  echo "group_count=${#GROUP_IDS[@]}"
  echo "accepted_group_count=${accepted_count}"
  echo "min_coverage_ratio=${MIN_COVERAGE_RATIO}"
  echo "max_target_to_path_m=${MAX_TARGET_TO_PATH_M}"
  echo "topic_wait_sec=${TOPIC_WAIT_SEC}"
  echo "ros_domain_id_start=80"
  echo "group_result_csv=${GROUP_RESULT_CSV}"
  echo "run_log=${RUN_LOG}"
} >"${SUMMARY_FILE}"

echo "Lookahead coverage monitor all-groups audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_RESULT_CSV}"

if [[ "${decision}" != "accepted_lookahead_coverage_monitor_all_groups" ]]; then
  exit 1
fi
