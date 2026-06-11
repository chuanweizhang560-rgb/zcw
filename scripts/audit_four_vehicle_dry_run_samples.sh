#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/four_vehicle_dry_run_samples_audit_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/four_vehicle_dry_run_samples_audit_${STAMP}.txt"
SAMPLES_FILE="${SAMPLES_FILE:-}"

mkdir -p "${RESULT_DIR}"

if [[ -z "${SAMPLES_FILE}" ]]; then
  SAMPLES_FILE="$(find "${ROOT_DIR}/data/logs" -maxdepth 1 -type f -name 'four_vehicle_dry_run_samples_*.log' | sort | tail -n 1)"
fi
if [[ -z "${SAMPLES_FILE}" || ! -f "${SAMPLES_FILE}" ]]; then
  echo "four-vehicle dry-run samples log not found" >&2
  exit 1
fi

has_all_goals=true
for instance in 1 2 3 4; do
  if ! rg -q -- "--- vehicle_${instance}_goal" "${SAMPLES_FILE}"; then
    has_all_goals=false
  fi
done

has_topology=false
has_safety=false
has_assignment=false
has_scoring=false
has_score_markers=false
has_rule_baseline=false
has_rule_score=false
has_marker_text=false
has_no_learned_policy=false
has_no_active=false
has_no_fmu_in=false
has_valid_topology_distance=false
has_score_terms=false
has_roles=true

if rg -q -- '--- topology_state' "${SAMPLES_FILE}" && rg -q 'FOUR_TOPOLOGY_READY' "${SAMPLES_FILE}"; then has_topology=true; fi
if rg -q -- '--- safety_state' "${SAMPLES_FILE}" && rg -q 'FOUR_SAFETY_READY_DRY_RUN' "${SAMPLES_FILE}"; then has_safety=true; fi
if rg -q -- '--- assignment_state' "${SAMPLES_FILE}"; then has_assignment=true; fi
if rg -q -- '--- scoring_state' "${SAMPLES_FILE}"; then has_scoring=true; fi
if rg -q -- '--- score_markers' "${SAMPLES_FILE}"; then has_score_markers=true; fi
if rg -q 'FOUR_RULE_BASELINE_DRY_RUN' "${SAMPLES_FILE}"; then has_rule_baseline=true; fi
if rg -q 'FOUR_RULE_SCORE_DRY_RUN' "${SAMPLES_FILE}"; then has_rule_score=true; fi
if rg -q 'V1 wind' "${SAMPLES_FILE}" &&
   rg -q 'V2 cable' "${SAMPLES_FILE}" &&
   rg -q 'V3 relay' "${SAMPLES_FILE}" &&
   rg -q 'V4 relay' "${SAMPLES_FILE}"; then
  has_marker_text=true
fi
if rg -q 'learned_policy=false' "${SAMPLES_FILE}"; then has_no_learned_policy=true; fi
if rg -q 'starts_offboard=false.*arms=false' "${SAMPLES_FILE}"; then has_no_active=true; fi
if rg -q 'publishes_fmu_in=false' "${SAMPLES_FILE}"; then has_no_fmu_in=true; fi
if rg -q 'chain_max_distance_m=[0-9]' "${SAMPLES_FILE}" && ! rg -q 'chain_max_distance_m=-1' "${SAMPLES_FILE}"; then
  has_valid_topology_distance=true
fi
if rg -q 'topology_score=[0-9]' "${SAMPLES_FILE}" &&
   rg -q 'state_score=[0-9]' "${SAMPLES_FILE}" &&
   rg -q 'task_distance_score=[0-9]' "${SAMPLES_FILE}" &&
   rg -q 'rule_total_score=[0-9]' "${SAMPLES_FILE}"; then
  has_score_terms=true
fi

for role in \
  'vehicle_1_role=wind_inspection_candidate' \
  'vehicle_2_role=cable_inspection_candidate' \
  'vehicle_3_role=relay_candidate' \
  'vehicle_4_role=relay_candidate'; do
  if ! rg -q "${role}" "${SAMPLES_FILE}"; then
    has_roles=false
  fi
done

accepted=false
if [[ "${has_all_goals}" == "true" &&
      "${has_topology}" == "true" &&
      "${has_safety}" == "true" &&
      "${has_assignment}" == "true" &&
      "${has_scoring}" == "true" &&
      "${has_score_markers}" == "true" &&
      "${has_rule_baseline}" == "true" &&
      "${has_rule_score}" == "true" &&
      "${has_marker_text}" == "true" &&
      "${has_no_learned_policy}" == "true" &&
      "${has_no_active}" == "true" &&
      "${has_no_fmu_in}" == "true" &&
      "${has_valid_topology_distance}" == "true" &&
      "${has_score_terms}" == "true" &&
      "${has_roles}" == "true" ]]; then
  accepted=true
fi

{
  echo "scope=four_vehicle_dry_run_samples_audit"
  echo "decision=$([[ "${accepted}" == "true" ]] && echo accepted_four_vehicle_dry_run_samples_audit || echo rejected_four_vehicle_dry_run_samples_audit)"
  echo "reason=$([[ "${accepted}" == "true" ]] && echo dry_run_samples_include_four_vehicle_rule_assignment_and_no_active_flags || echo dry_run_samples_missing_required_fields)"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "samples_file=${SAMPLES_FILE}"
  echo "has_all_goals=${has_all_goals}"
  echo "has_topology=${has_topology}"
  echo "has_safety=${has_safety}"
  echo "has_assignment=${has_assignment}"
  echo "has_scoring=${has_scoring}"
  echo "has_score_markers=${has_score_markers}"
  echo "has_rule_baseline=${has_rule_baseline}"
  echo "has_rule_score=${has_rule_score}"
  echo "has_marker_text=${has_marker_text}"
  echo "has_no_learned_policy=${has_no_learned_policy}"
  echo "has_no_active=${has_no_active}"
  echo "has_no_fmu_in=${has_no_fmu_in}"
  echo "has_valid_topology_distance=${has_valid_topology_distance}"
  echo "has_score_terms=${has_score_terms}"
  echo "has_roles=${has_roles}"
} >"${SUMMARY_FILE}"

if [[ "${accepted}" != "true" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi

echo "Four-vehicle dry-run samples audit completed."
echo "Summary: ${SUMMARY_FILE}"
