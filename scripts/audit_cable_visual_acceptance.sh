#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_CABLE_DRY_RUN_SUMMARY="data/results/cable_dry_run_acceptance_20260616_152304/cable_dry_run_acceptance_20260616_152304.txt"
DEFAULT_ALL_GROUPS_RVIZ_SUMMARY="data/results/cable_all_groups_rviz_overlay_20260616_093252/cable_all_groups_rviz_overlay_20260616_093252.txt"
CABLE_DRY_RUN_SUMMARY="${CABLE_DRY_RUN_SUMMARY:-${DEFAULT_CABLE_DRY_RUN_SUMMARY}}"
ALL_GROUPS_RVIZ_SUMMARY="${ALL_GROUPS_RVIZ_SUMMARY:-${DEFAULT_ALL_GROUPS_RVIZ_SUMMARY}}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_visual_acceptance_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_visual_acceptance_${STAMP}.txt"

mkdir -p "${RESULT_DIR}"

read_field() {
  local file="$1"
  local key="$2"
  awk -F= -v key="${key}" '$1 == key {print substr($0, length(key) + 2); exit}' "${file}"
}

require_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    echo "Required evidence missing: ${file}" >&2
    exit 1
  fi
}

require_file "${CABLE_DRY_RUN_SUMMARY}"
require_file "${ALL_GROUPS_RVIZ_SUMMARY}"

dry_run_claim="$(read_field "${CABLE_DRY_RUN_SUMMARY}" "claims_cable_dry_run_acceptance_pass")"
dry_run_boundary="$(read_field "${CABLE_DRY_RUN_SUMMARY}" "boundary_ok")"
dry_run_coverage="$(read_field "${CABLE_DRY_RUN_SUMMARY}" "coverage_ok")"
overlay_decision="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "decision")"
overlay_starts_px4="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "starts_px4")"
overlay_starts_gazebo="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "starts_gazebo")"
overlay_starts_offboard="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "starts_offboard")"
overlay_arms="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "arms")"
overlay_publishes_fmu_in="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "publishes_fmu_in")"
overlay_group_count="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "group_count")"
overlay_target_group_count="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "target_group_count")"
overlay_marker_alive="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "marker_alive")"
overlay_screenshot="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "screenshot")"
overlay_screenshot_ok="$(read_field "${ALL_GROUPS_RVIZ_SUMMARY}" "screenshot_ok")"

dry_run_ok=false
if [[ "${dry_run_claim}" == "true" && "${dry_run_boundary}" == "true" && "${dry_run_coverage}" == "true" ]]; then
  dry_run_ok=true
fi

overlay_boundary_ok=false
if [[ "${overlay_decision}" == "accepted_cable_all_groups_rviz_overlay" \
  && "${overlay_starts_px4}" == "false" \
  && "${overlay_starts_gazebo}" == "false" \
  && "${overlay_starts_offboard}" == "false" \
  && "${overlay_arms}" == "false" \
  && "${overlay_publishes_fmu_in}" == "false" ]]; then
  overlay_boundary_ok=true
fi

overlay_content_ok=false
if [[ "${overlay_group_count}" == "5" \
  && "${overlay_target_group_count}" == "5" \
  && "${overlay_marker_alive}" == "true" \
  && "${overlay_screenshot_ok}" == "true" \
  && -f "${overlay_screenshot}" ]]; then
  overlay_content_ok=true
fi

decision="accepted_cable_visual_acceptance"
reason="cable_dry_run_and_all_groups_rviz_visual_evidence_pass"
if [[ "${dry_run_ok}" != "true" ]]; then
  decision="rejected_cable_visual_acceptance"
  reason="cable_dry_run_acceptance_not_passed"
elif [[ "${overlay_boundary_ok}" != "true" ]]; then
  decision="rejected_cable_visual_acceptance"
  reason="all_groups_rviz_boundary_not_passed"
elif [[ "${overlay_content_ok}" != "true" ]]; then
  decision="rejected_cable_visual_acceptance"
  reason="all_groups_rviz_content_not_passed"
fi

{
  echo "scope=cable_visual_acceptance"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "cable_dry_run_summary=${CABLE_DRY_RUN_SUMMARY}"
  echo "all_groups_rviz_summary=${ALL_GROUPS_RVIZ_SUMMARY}"
  echo "dry_run_ok=${dry_run_ok}"
  echo "overlay_boundary_ok=${overlay_boundary_ok}"
  echo "overlay_content_ok=${overlay_content_ok}"
  echo "overlay_group_count=${overlay_group_count}"
  echo "overlay_target_group_count=${overlay_target_group_count}"
  echo "overlay_screenshot=${overlay_screenshot}"
  echo "claims_cable_visual_acceptance_pass=$([[ "${decision}" == "accepted_cable_visual_acceptance" ]] && echo true || echo false)"
} >"${SUMMARY_FILE}"

echo "Cable visual acceptance audit completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_cable_visual_acceptance" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
