#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_active_control_review_package_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_active_control_review_package_${STAMP}.txt"
STATIC_LOG="${RESULT_DIR}/static_checks_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

PACKAGE_DOC="docs/25_cable_active_control_review_package.md"
REQUIRED_DOCS=(
  "docs/14_current_status_and_next_steps.md"
  "docs/19_current_evidence_matrix.md"
  "docs/20_active_control_review_entry.md"
  "docs/21_future_cable_active_bridge_design.md"
  "docs/22_cable_inspection_surface_coverage_model.md"
  "docs/23_cable_multiview_surface_observation_plan.md"
  "docs/24_cable_surface_current_acceptance.md"
  "docs/10_evidence_inventory.md"
)

REQUIRED_EVIDENCE=(
  "data/results/cable_surface_current_acceptance_20260617_163650/cable_surface_current_acceptance_20260617_163650.txt"
  "data/results/current_evidence_matrix_20260617_163839/current_evidence_matrix_20260617_163839.txt"
  "data/results/evidence_inventory_20260617_163850/evidence_inventory_20260617_163850.txt"
  "data/screenshots/px4_aerialcore_danube_wires_gui_20260617_162903.png"
)

{
  echo "scope=cable_active_control_review_package"
  echo "package_doc=${PACKAGE_DOC}"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "publishes_fmu_in=false"
  echo "rate_hz=20"
  echo "single_vehicle_cable_only=true"
} >"${SUMMARY_FILE}"

{
  echo "[check] package document exists"
  [[ -f "${PACKAGE_DOC}" ]] || fail "missing package doc: ${PACKAGE_DOC}"
  echo "ok"

  echo "[check] package document contains required boundary text"
  rg -n 'active_control_approved=false|phase_b_user_approved=false|single_vehicle_cable_only|rate_hz=20|/fmu/in/\*|PROCESS_LOG.md' "${PACKAGE_DOC}" >/dev/null \
    || fail "package doc missing required boundary markers"
  echo "ok"

  echo "[check] package document references required input docs"
  for doc in "${REQUIRED_DOCS[@]}"; do
    rg -n "${doc}" "${PACKAGE_DOC}" >/dev/null || fail "package doc does not reference ${doc}"
  done
  echo "ok"

  echo "[check] review package does not imply an active bridge implementation"
  if rg -n 'cable_active_bridge|phase_b_user_approved:=true|phase_b_user_approved=true' \
    ros2_ws/src/zcw_px4_baseline ros2_ws/src/zcw_bringup \
    >"${RESULT_DIR}/active_bridge_refs_${STAMP}.log"; then
    cat "${RESULT_DIR}/active_bridge_refs_${STAMP}.log"
    fail "source tree already contains active bridge implementation references"
  fi
  echo "ok"

  echo "[check] required evidence files are present"
  for path in "${REQUIRED_EVIDENCE[@]}"; do
    [[ -f "${path}" ]] || fail "missing required evidence: ${path}"
  done
  echo "ok"

  echo "[check] accepted evidence markers are present"
  rg -n 'decision=accepted_cable_surface_current_acceptance|claims_cable_surface_progression_current_acceptance_pass=true|claims_final_cable_inspection_coverage=false' \
    data/results/cable_surface_current_acceptance_20260617_163650/cable_surface_current_acceptance_20260617_163650.txt >/dev/null \
    || fail "surface acceptance evidence missing accepted markers"
  rg -n 'decision=accepted_current_evidence_matrix|positive_capability_count=6|accepted_positive_capability_count=6' \
    data/results/current_evidence_matrix_20260617_163839/current_evidence_matrix_20260617_163839.txt >/dev/null \
    || fail "current evidence matrix missing accepted markers"
  rg -n 'decision=accepted_evidence_inventory|required_evidence_count=30|missing_count=0' \
    data/results/evidence_inventory_20260617_163850/evidence_inventory_20260617_163850.txt >/dev/null \
    || fail "evidence inventory missing accepted markers"
  echo "ok"
} >"${STATIC_LOG}" 2>&1 || {
  cat "${STATIC_LOG}" >&2
  exit 1
}

pass "static review-package checks accepted"

{
  echo "decision=accepted_cable_active_control_review_package"
  echo "package_prepared=true"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "publishes_fmu_in=false"
  echo "static_log=${STATIC_LOG}"
} >>"${SUMMARY_FILE}"

echo "Cable active control review package audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Static log: ${STATIC_LOG}"
