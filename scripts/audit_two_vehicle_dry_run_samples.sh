#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/two_vehicle_dry_run_samples_audit_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/two_vehicle_dry_run_samples_audit_${STAMP}.txt"
SAMPLES_FILE="${SAMPLES_FILE:-}"

mkdir -p "${RESULT_DIR}"

if [[ -z "${SAMPLES_FILE}" ]]; then
  SAMPLES_FILE="$(find "${ROOT_DIR}/data/logs" -maxdepth 1 -type f -name 'two_vehicle_dry_run_samples_*.log' | sort | tail -n 1)"
fi
if [[ -z "${SAMPLES_FILE}" || ! -f "${SAMPLES_FILE}" ]]; then
  echo "two-vehicle dry-run samples log not found" >&2
  exit 1
fi

has_vehicle_1_goal=false
has_vehicle_2_goal=false
has_topology=false
has_safety=false
has_assignment=false
has_rule_baseline=false
has_no_learned_policy=false
has_v1_inspection=false
has_v2_relay=false
has_no_active=false
has_no_fmu_in=false
has_valid_topology_distance=false

if rg -q -- '--- vehicle_1_goal' "${SAMPLES_FILE}"; then has_vehicle_1_goal=true; fi
if rg -q -- '--- vehicle_2_goal' "${SAMPLES_FILE}"; then has_vehicle_2_goal=true; fi
if rg -q -- '--- topology_state' "${SAMPLES_FILE}"; then has_topology=true; fi
if rg -q -- '--- safety_state' "${SAMPLES_FILE}"; then has_safety=true; fi
if rg -q -- '--- assignment_state' "${SAMPLES_FILE}"; then has_assignment=true; fi
if rg -q 'RULE_BASELINE_DRY_RUN' "${SAMPLES_FILE}"; then has_rule_baseline=true; fi
if rg -q 'learned_policy=false' "${SAMPLES_FILE}"; then has_no_learned_policy=true; fi
if rg -q 'vehicle_1_role=inspection_candidate' "${SAMPLES_FILE}"; then has_v1_inspection=true; fi
if rg -q 'vehicle_2_role=relay_candidate' "${SAMPLES_FILE}"; then has_v2_relay=true; fi
if rg -q 'starts_offboard=false.*arms=false' "${SAMPLES_FILE}"; then has_no_active=true; fi
if rg -q 'publishes_fmu_in=false' "${SAMPLES_FILE}"; then has_no_fmu_in=true; fi
if rg -q 'vehicle_distance_m=[0-9]' "${SAMPLES_FILE}" && ! rg -q 'vehicle_distance_m=-1' "${SAMPLES_FILE}"; then
  has_valid_topology_distance=true
fi

accepted=false
if [[ "${has_vehicle_1_goal}" == "true" &&
      "${has_vehicle_2_goal}" == "true" &&
      "${has_topology}" == "true" &&
      "${has_safety}" == "true" &&
      "${has_assignment}" == "true" &&
      "${has_rule_baseline}" == "true" &&
      "${has_no_learned_policy}" == "true" &&
      "${has_v1_inspection}" == "true" &&
      "${has_v2_relay}" == "true" &&
      "${has_no_active}" == "true" &&
      "${has_no_fmu_in}" == "true" &&
      "${has_valid_topology_distance}" == "true" ]]; then
  accepted=true
fi

{
  echo "scope=two_vehicle_dry_run_samples_audit"
  echo "decision=$([[ "${accepted}" == "true" ]] && echo accepted_two_vehicle_dry_run_samples_audit || echo rejected_two_vehicle_dry_run_samples_audit)"
  echo "reason=$([[ "${accepted}" == "true" ]] && echo dry_run_samples_include_rule_assignment_and_no_active_flags || echo dry_run_samples_missing_required_fields)"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "samples_file=${SAMPLES_FILE}"
  echo "has_vehicle_1_goal=${has_vehicle_1_goal}"
  echo "has_vehicle_2_goal=${has_vehicle_2_goal}"
  echo "has_topology=${has_topology}"
  echo "has_safety=${has_safety}"
  echo "has_assignment=${has_assignment}"
  echo "has_rule_baseline=${has_rule_baseline}"
  echo "has_no_learned_policy=${has_no_learned_policy}"
  echo "has_v1_inspection=${has_v1_inspection}"
  echo "has_v2_relay=${has_v2_relay}"
  echo "has_no_active=${has_no_active}"
  echo "has_no_fmu_in=${has_no_fmu_in}"
  echo "has_valid_topology_distance=${has_valid_topology_distance}"
} >"${SUMMARY_FILE}"

if [[ "${accepted}" != "true" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi

echo "Two-vehicle dry-run samples audit completed."
echo "Summary: ${SUMMARY_FILE}"
