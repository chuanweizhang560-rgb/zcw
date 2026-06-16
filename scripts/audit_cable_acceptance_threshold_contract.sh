#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DOC_PATH="${DOC_PATH:-docs/18_cable_acceptance_thresholds.md}"
AUDIT_SCRIPT="${AUDIT_SCRIPT:-scripts/audit_cable_dry_run_acceptance.sh}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_acceptance_threshold_contract_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_acceptance_threshold_contract_${STAMP}.txt"
CHECKS_LOG="${RESULT_DIR}/threshold_contract_checks_${STAMP}.log"

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
  printf '%s script_ok=%s doc_ok=%s\n' "${name}" "${script_ok}" "${doc_ok}" >>"${CHECKS_LOG}"
}

check_pair "MIN_GROUPS" 'MIN_GROUPS="${MIN_GROUPS:-5}"' '| Accepted cable groups | `MIN_GROUPS` | `5` | `5` |'
check_pair "MIN_COVERAGE_RATIO" 'MIN_COVERAGE_RATIO="${MIN_COVERAGE_RATIO:-0.80}"' '| Per-group dry-run coverage ratio | `MIN_COVERAGE_RATIO` | `0.80` | `0.840000000` |'
check_pair "MAX_CLEARANCE_ERROR_M" 'MAX_CLEARANCE_ERROR_M="${MAX_CLEARANCE_ERROR_M:-0.001}"' '| Offset clearance error | `MAX_CLEARANCE_ERROR_M` | `0.001m` | `0.000000000m` |'
check_pair "MAX_FRAME_ERROR_M" 'MAX_FRAME_ERROR_M="${MAX_FRAME_ERROR_M:-0.001}"' '| Frame/source/target error | `MAX_FRAME_ERROR_M` | `0.001m` | `0.000000000m` |'
check_pair "MAX_LOOKAHEAD_ERROR_M" 'MAX_LOOKAHEAD_ERROR_M="${MAX_LOOKAHEAD_ERROR_M:-0.01}"' '| Lookahead distance error | `MAX_LOOKAHEAD_ERROR_M` | `0.01m` | `0.001200000m` |'
check_pair "MIN_FORWARD_DOT" 'MIN_FORWARD_DOT="${MIN_FORWARD_DOT:-0.99}"' '| Forward tangent consistency | `MIN_FORWARD_DOT` | `0.99` | `0.999999005` |'

boundary_count=0
for boundary in \
  "does not approve cable Phase B active control" \
  "do not claim:" \
  "setpoint publication" \
  "final cable inspection coverage" \
  "publisher count must remain"; do
  check_count=$((check_count + 1))
  if grep -Fq "${boundary}" "${DOC_PATH}"; then
    boundary_count=$((boundary_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'boundary "%s" doc_ok=false\n' "${boundary}" >>"${CHECKS_LOG}"
  fi
done

decision="accepted_cable_acceptance_threshold_contract"
reason="cable_threshold_document_matches_audit_defaults"
if (( fail_count > 0 )); then
  decision="rejected_cable_acceptance_threshold_contract"
  reason="cable_threshold_document_or_audit_defaults_mismatch"
fi

{
  echo "scope=cable_acceptance_threshold_contract"
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
  echo "checks_log=${CHECKS_LOG}"
  echo "claims_active_control_approval=false"
  echo "claims_final_inspection_coverage=false"
} >"${SUMMARY_FILE}"

echo "Cable acceptance threshold contract audit completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_cable_acceptance_threshold_contract" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
