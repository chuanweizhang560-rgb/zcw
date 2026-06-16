#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/evidence_inventory_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/evidence_inventory_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/evidence_inventory_${STAMP}.csv"
REGEN_FILE="${RESULT_DIR}/evidence_regeneration_${STAMP}.txt"

mkdir -p "${RESULT_DIR}"

required_evidence=(
  "phase_a_bridge_state|data/logs/px4_bridge_dry_run_state_echo_20260608_091305.log|scripts/verify_px4_bridge_dry_run_isolation.sh"
  "phase_a_bridge_rviz|data/screenshots/px4_bridge_dry_run_rviz_overlay_20260608_102352.png|scripts/capture_px4_bridge_dry_run_rviz_overlay.sh"
  "readonly_frame_alignment|data/results/px4_gazebo_frame_alignment_20260608_102532/px4_gazebo_frame_alignment_20260608_102532.txt|scripts/verify_px4_gazebo_readonly_frame_alignment.sh"
  "offboard_gate_summary|data/results/cable_offboard_gate_dry_run_20260608_101325/cable_offboard_gate_dry_run_20260608_101325.txt|scripts/verify_cable_offboard_gate_dry_run.sh"
  "offboard_gate_forbidden_publishers|data/logs/cable_offboard_gate_forbidden_publishers_20260608_101325.log|scripts/verify_cable_offboard_gate_dry_run.sh"
  "offboard_gate_rviz_summary|data/results/cable_offboard_gate_rviz_overlay_20260608_101949/cable_offboard_gate_rviz_overlay_20260608_101949.txt|scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh"
  "offboard_gate_rviz_screenshot|data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260608_101949.png|scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh"
  "offset_path_csv|data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv|scripts/audit_catenary_fit.sh then scripts/audit_offset_path.sh"
  "lookahead_targets_csv|data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv|scripts/audit_lookahead_target.sh"
  "cable_acceptance_threshold_contract|data/results/cable_acceptance_threshold_contract_20260616_152304/cable_acceptance_threshold_contract_20260616_152304.txt|scripts/audit_cable_acceptance_threshold_contract.sh"
  "cable_all_groups_rviz_summary|data/results/cable_all_groups_rviz_overlay_20260616_093252/cable_all_groups_rviz_overlay_20260616_093252.txt|scripts/capture_cable_all_groups_rviz_overlay.sh"
  "cable_all_groups_rviz_screenshot|data/screenshots/cable_all_groups_rviz_overlay_20260616_093252.png|scripts/capture_cable_all_groups_rviz_overlay.sh"
  "gate_rviz_state_echo|data/logs/cable_offboard_gate_rviz_state_echo_20260608_101949.log|scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh"
  "gate_rviz_approved_ned_echo|data/logs/cable_offboard_gate_rviz_approved_ned_echo_20260608_101949.log|scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh"
  "wind_multilevel_static_summary|data/results/wind_turbine_multilevel_orbit_launch_20260604_135831/wind_turbine_multilevel_orbit_launch_20260604_135831.txt|scripts/audit_wind_turbine_multilevel_orbit_launch.sh"
  "wind_multilevel_static_csv|data/results/wind_turbine_multilevel_orbit_launch_20260604_135831/wind_turbine_multilevel_orbit_launch_20260604_135831.csv|scripts/audit_wind_turbine_multilevel_orbit_launch.sh"
  "wind_multilevel_headless_control_log|data/logs/waypoints_control_20260604_132205.log|scripts/verify_wind_turbine_multilevel_orbit.sh"
  "wind_multilevel_headless_status|data/logs/waypoints_vehicle_status_20260604_132205.log|scripts/verify_wind_turbine_multilevel_orbit.sh"
  "wind_multilevel_headless_position|data/logs/waypoints_vehicle_local_position_20260604_132205.log|scripts/verify_wind_turbine_multilevel_orbit.sh"
  "wind_multilevel_gui_screenshot|data/screenshots/wind_turbine_multilevel_orbit_gui_20260604_134640.png|scripts/capture_wind_turbine_multilevel_orbit_gui.sh"
  "wind_multilevel_gui_window_id|data/screenshots/wind_turbine_multilevel_orbit_gui_20260604_134640.png.window_id.txt|scripts/capture_wind_turbine_multilevel_orbit_gui.sh"
  "wind_multilevel_gui_offboard_log|data/logs/wind_multilevel_gui_offboard_20260604_134640.log|scripts/capture_wind_turbine_multilevel_orbit_gui.sh"
  "wind_multilevel_gui_status|data/logs/wind_multilevel_gui_vehicle_status_20260604_134640.log|scripts/capture_wind_turbine_multilevel_orbit_gui.sh"
  "wind_multilevel_gui_position|data/logs/wind_multilevel_gui_vehicle_local_position_20260604_134640.log|scripts/capture_wind_turbine_multilevel_orbit_gui.sh"
  "wind_acceptance_threshold_contract|data/results/wind_acceptance_threshold_contract_20260616_094206/wind_acceptance_threshold_contract_20260616_094206.txt|scripts/audit_wind_acceptance_threshold_contract.sh"
)

regeneration_commands=(
  "scripts/verify_px4_bridge_dry_run_isolation.sh"
  "scripts/capture_px4_bridge_dry_run_rviz_overlay.sh"
  "scripts/capture_cable_all_groups_rviz_overlay.sh"
  "scripts/audit_cable_acceptance_threshold_contract.sh"
  "scripts/verify_px4_gazebo_readonly_frame_alignment.sh"
  "scripts/verify_cable_offboard_gate_dry_run.sh"
  "scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh"
  "scripts/audit_cable_setpoint_thresholds.sh"
  "scripts/audit_phase_b_active_preflight_boundary.sh"
  "scripts/audit_active_bridge_review_template.sh"
  "scripts/audit_dry_run_readiness.sh"
  "scripts/audit_wind_turbine_multilevel_orbit_launch.sh"
  "scripts/audit_wind_acceptance_threshold_contract.sh"
  "scripts/verify_wind_turbine_multilevel_orbit.sh"
  "scripts/capture_wind_turbine_multilevel_orbit_gui.sh"
)

missing_count=0
not_ignored_count=0
present_count=0

{
  echo "name,path,status,git_ignore_status,regeneration"
  for item in "${required_evidence[@]}"; do
    IFS='|' read -r name path regen <<<"${item}"
    status="present"
    if [[ ! -f "${path}" ]]; then
      status="missing"
      missing_count=$((missing_count + 1))
    else
      present_count=$((present_count + 1))
    fi

    git_ignore_status="ignored"
    if ! git check-ignore -q "${path}"; then
      git_ignore_status="not_ignored"
      not_ignored_count=$((not_ignored_count + 1))
    fi

    printf '%s,%s,%s,%s,"%s"\n' "${name}" "${path}" "${status}" "${git_ignore_status}" "${regen}"
  done
} >"${CSV_FILE}"

{
  echo "Evidence regeneration commands"
  echo
  echo "These commands may start ROS, PX4, Gazebo or RViz depending on the script."
  echo "Run them only when the corresponding evidence needs to be regenerated."
  echo "They remain forbidden from publishing /fmu/in/* unless the individual script explicitly says otherwise and Phase B has been approved."
  echo
  for command in "${regeneration_commands[@]}"; do
    echo "- ${command}"
  done
} >"${REGEN_FILE}"

decision="accepted_evidence_inventory"
reason="all_required_evidence_present_and_ignored"
if (( missing_count > 0 )); then
  decision="rejected_evidence_inventory"
  reason="required_evidence_missing"
elif (( not_ignored_count > 0 )); then
  decision="rejected_evidence_inventory"
  reason="evidence_not_ignored_by_git"
fi

{
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "required_evidence_count=${#required_evidence[@]}"
  echo "present_count=${present_count}"
  echo "missing_count=${missing_count}"
  echo "not_ignored_count=${not_ignored_count}"
  echo "inventory_csv=${CSV_FILE}"
  echo "regeneration_file=${REGEN_FILE}"
} >"${SUMMARY_FILE}"

echo "Evidence inventory audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Inventory CSV: ${CSV_FILE}"
echo "Regeneration file: ${REGEN_FILE}"

if [[ "${decision}" != "accepted_evidence_inventory" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
