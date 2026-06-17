#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_active_approval_manifest_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_active_approval_manifest_${STAMP}.txt"
STATIC_LOG="${RESULT_DIR}/static_checks_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

MANIFEST_DOC="docs/28_cable_active_approval_manifest.md"
REQUIRED_DOCS=(
  "docs/25_cable_active_control_review_package.md"
  "docs/26_cable_single_vehicle_active_scenario.md"
  "docs/27_cable_active_readiness_snapshot.md"
  "docs/19_current_evidence_matrix.md"
  "docs/10_evidence_inventory.md"
  "docs/21_future_cable_active_bridge_design.md"
)

APPROVAL_PHRASE='single_vehicle_cable_short_active.*active_control_approved=true.*phase_b_user_approved=true.*cable_phase_b_active_bridge_approved=true'

{
  echo "scope=cable_active_approval_manifest"
  echo "approval_manifest=present"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "cable_phase_b_active_bridge_approved=false"
  echo "publishes_fmu_in=false"
} >"${SUMMARY_FILE}"

{
  echo "[check] manifest document exists"
  [[ -f "${MANIFEST_DOC}" ]] || fail "missing manifest doc: ${MANIFEST_DOC}"
  echo "ok"

  echo "[check] manifest references required prerequisite docs"
  for doc in "${REQUIRED_DOCS[@]}"; do
    rg -n "${doc}" "${MANIFEST_DOC}" >/dev/null || fail "manifest doc does not reference ${doc}"
  done
  echo "ok"

  echo "[check] approval text is not present in PROCESS_LOG yet"
  if rg -n "${APPROVAL_PHRASE}" PROCESS_LOG.md >/dev/null; then
    fail "approval phrase already present in PROCESS_LOG"
  fi
  echo "ok"

  echo "[check] manifest keeps approval blocked"
  rg -n 'It is not approval|does not permit `/fmu/in/\*` publication|If the required approval text is absent' "${MANIFEST_DOC}" >/dev/null \
    || fail "manifest missing blocking language"
  echo "ok"
} >"${STATIC_LOG}" 2>&1 || {
  cat "${STATIC_LOG}" >&2
  exit 1
}

pass "static approval-manifest checks accepted"

{
  echo "decision=accepted_cable_active_approval_manifest"
  echo "approval_manifest=present"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "cable_phase_b_active_bridge_approved=false"
  echo "publishes_fmu_in=false"
  echo "static_log=${STATIC_LOG}"
} >>"${SUMMARY_FILE}"

echo "Cable active approval manifest audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Static log: ${STATIC_LOG}"
