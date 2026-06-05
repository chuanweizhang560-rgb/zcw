#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/rtabmap_depth_camera_rgbd_consistency_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_depth_camera_rgbd_consistency_${STAMP}.txt"
RUNS="${RUNS:-3}"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"

success_count=0
failure_count=0
accepted_count=0
run_summaries=()

for i in $(seq 1 "${RUNS}"); do
  echo "=== RTAB-Map RGB-D consistency run ${i}/${RUNS} ==="
  if output="$("${ROOT_DIR}/scripts/verify_rtabmap_depth_camera_rgbd_smoke.sh" 2>&1)"; then
    echo "${output}"
    summary_path="$(printf '%s\n' "${output}" | awk -F'Summary: ' '/^Summary: / {print $2}' | tail -n 1)"
    if [[ -z "${summary_path}" || ! -f "${summary_path}" ]]; then
      echo "Missing summary path after successful run ${i}." >&2
      failure_count=$((failure_count + 1))
      run_summaries+=("run_${i}=missing_summary")
      continue
    fi
    run_summaries+=("run_${i}=${summary_path}")
    success_count=$((success_count + 1))
    if grep -q '^decision=accepted_rtabmap_depth_camera_rgbd_smoke$' "${summary_path}"; then
      accepted_count=$((accepted_count + 1))
    fi
  else
    echo "${output}" >&2
    failure_count=$((failure_count + 1))
    run_summaries+=("run_${i}=failed")
  fi
done

decision="rejected_rtabmap_depth_camera_rgbd_consistency"
reason="at_least_one_rgbd_smoke_run_failed_or_was_not_accepted"
if [[ "${success_count}" -eq "${RUNS}" && "${accepted_count}" -eq "${RUNS}" ]]; then
  decision="accepted_rtabmap_depth_camera_rgbd_consistency"
  reason="all_rgbd_smoke_runs_succeeded_and_were_accepted"
fi

{
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "runs=${RUNS}"
  echo "success_count=${success_count}"
  echo "failure_count=${failure_count}"
  echo "accepted_count=${accepted_count}"
  printf '%s\n' "${run_summaries[@]}"
} >"${SUMMARY_FILE}"

echo "RTAB-Map RGB-D consistency audit completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_rtabmap_depth_camera_rgbd_consistency" ]]; then
  exit 1
fi
