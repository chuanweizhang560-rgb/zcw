#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DOC_PATH="${DOC_PATH:-docs/17_wind_acceptance_thresholds.md}"
AUDIT_SCRIPT="${AUDIT_SCRIPT:-scripts/audit_wind_rule_baseline_acceptance.sh}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/wind_acceptance_threshold_contract_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/wind_acceptance_threshold_contract_${STAMP}.txt"

mkdir -p "${RESULT_DIR}"

if [[ ! -f "${DOC_PATH}" ]]; then
  echo "Required document missing: ${DOC_PATH}" >&2
  exit 1
fi
if [[ ! -f "${AUDIT_SCRIPT}" ]]; then
  echo "Required audit script missing: ${AUDIT_SCRIPT}" >&2
  exit 1
fi

check_count=0
fail_count=0

check_pair() {
  local name="$1"
  local script_pattern="$2"
  local doc_pattern="$3"
  local script_ok=false
  local doc_ok=false

  check_count=$((check_count + 1))
  if grep -Fq "${script_pattern}" "${AUDIT_SCRIPT}"; then
    script_ok=true
  fi
  if grep -Fq "${doc_pattern}" "${DOC_PATH}"; then
    doc_ok=true
  fi
  if [[ "${script_ok}" != "true" || "${doc_ok}" != "true" ]]; then
    fail_count=$((fail_count + 1))
  fi
  printf '%s script_ok=%s doc_ok=%s\n' "${name}" "${script_ok}" "${doc_ok}" >>"${RESULT_DIR}/threshold_contract_checks_${STAMP}.log"
}

check_pair "MIN_WAYPOINT_ADVANCEMENTS" 'MIN_WAYPOINT_ADVANCEMENTS="${MIN_WAYPOINT_ADVANCEMENTS:-120}"' '| Waypoint progress | `MIN_WAYPOINT_ADVANCEMENTS` | `120` | `145` |'
check_pair "MIN_LOCAL_POSITION_SAMPLES" 'MIN_LOCAL_POSITION_SAMPLES="${MIN_LOCAL_POSITION_SAMPLES:-40000}"' '| PX4 local-position samples | `MIN_LOCAL_POSITION_SAMPLES` | `40000` | `44884` |'
check_pair "MIN_VALID_POSE_SAMPLES" 'MIN_VALID_POSE_SAMPLES="${MIN_VALID_POSE_SAMPLES:-40000}"' '| Converted valid pose samples | `MIN_VALID_POSE_SAMPLES` | `40000` | `43611` |'
check_pair "MIN_CAPTURE_DURATION_SEC" 'MIN_CAPTURE_DURATION_SEC="${MIN_CAPTURE_DURATION_SEC:-300}"' '| Capture duration | `MIN_CAPTURE_DURATION_SEC` | `300` | `348.991111000` |'
check_pair "MIN_CLEARANCE_M" 'MIN_CLEARANCE_M="${MIN_CLEARANCE_M:-1.0}"' '| Conservative clearance | `MIN_CLEARANCE_M` | `1.0m` | `1.688958000m` |'
check_pair "MIN_DYNAMIC_NORMAL_COVERAGE" 'MIN_DYNAMIC_NORMAL_COVERAGE="${MIN_DYNAMIC_NORMAL_COVERAGE:-0.70}"' '| Dynamic normal-filtered coverage | `MIN_DYNAMIC_NORMAL_COVERAGE` | `0.70` | `0.733899000` |'
check_pair "MIN_DYNAMIC_BAND_COVERAGE" 'MIN_DYNAMIC_BAND_COVERAGE="${MIN_DYNAMIC_BAND_COVERAGE:-0.55}"' '| Dynamic weakest height-band coverage | `MIN_DYNAMIC_BAND_COVERAGE` | `0.55` | `0.595682000` |'
check_pair "MIN_OCCLUSION_CLEAR_COVERAGE" 'MIN_OCCLUSION_CLEAR_COVERAGE="${MIN_OCCLUSION_CLEAR_COVERAGE:-0.65}"' '| Occlusion-clear normal-filtered coverage | `MIN_OCCLUSION_CLEAR_COVERAGE` | `0.65` | `0.699828000` |'
check_pair "MIN_OCCLUSION_BAND_COVERAGE" 'MIN_OCCLUSION_BAND_COVERAGE="${MIN_OCCLUSION_BAND_COVERAGE:-0.55}"' '| Occlusion-clear weakest height-band coverage | `MIN_OCCLUSION_BAND_COVERAGE` | `0.55` | `0.615385000` |'
check_pair "MIN_DB_NODES" 'MIN_DB_NODES="${MIN_DB_NODES:-180}"' '| RTAB-Map DB nodes | `MIN_DB_NODES` | `180` | `205` |'
check_pair "MIN_OFFICIAL_GLOBAL_CLOSURES" 'MIN_OFFICIAL_GLOBAL_CLOSURES="${MIN_OFFICIAL_GLOBAL_CLOSURES:-1}"' '| Official global closures | `MIN_OFFICIAL_GLOBAL_CLOSURES` | `1` | `6` |'
check_pair "MAX_P3D_ATE_RMSE_M" 'MAX_P3D_ATE_RMSE_M="${MAX_P3D_ATE_RMSE_M:-0.01}"' '| P3D-aligned ATE RMSE | `MAX_P3D_ATE_RMSE_M` | `0.01m` | `0.000001087m` |'
check_pair "MAX_PX4_CROSSCHECK_P95_M" 'MAX_PX4_CROSSCHECK_P95_M="${MAX_PX4_CROSSCHECK_P95_M:-4.0}"' '| PX4 estimator cross-check p95 | `MAX_PX4_CROSSCHECK_P95_M` | `4.0m` | `2.559375689m` |'

boundary_count=0
for boundary in \
  "does not approve multi-vehicle active Offboard" \
  "does not approve multi-vehicle active Offboard, cable active bridge, learned policy control, image-level defect detection, or final inspection coverage claims" \
  "do not claim:" \
  "independent SLAM localization accuracy" \
  "SLAM output to control PX4"; do
  check_count=$((check_count + 1))
  if grep -Fq "${boundary}" "${DOC_PATH}"; then
    boundary_count=$((boundary_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'boundary "%s" doc_ok=false\n' "${boundary}" >>"${RESULT_DIR}/threshold_contract_checks_${STAMP}.log"
  fi
done

decision="accepted_wind_acceptance_threshold_contract"
reason="wind_threshold_document_matches_audit_defaults"
if (( fail_count > 0 )); then
  decision="rejected_wind_acceptance_threshold_contract"
  reason="wind_threshold_document_or_audit_defaults_mismatch"
fi

{
  echo "scope=wind_acceptance_threshold_contract"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "doc_path=${DOC_PATH}"
  echo "audit_script=${AUDIT_SCRIPT}"
  echo "check_count=${check_count}"
  echo "fail_count=${fail_count}"
  echo "boundary_count=${boundary_count}"
  echo "checks_log=${RESULT_DIR}/threshold_contract_checks_${STAMP}.log"
  echo "claims_active_control_approval=false"
  echo "claims_final_inspection_coverage=false"
} >"${SUMMARY_FILE}"

echo "Wind acceptance threshold contract audit completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_wind_acceptance_threshold_contract" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
