#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/four_vehicle_dry_run_contract_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/four_vehicle_dry_run_contract_${STAMP}.txt"
DETAIL_LOG="${RESULT_DIR}/four_vehicle_dry_run_contract_detail_${STAMP}.log"

SOURCE_FILE="ros2_ws/src/zcw_px4_baseline/src/four_vehicle_dry_run_planner.cpp"
LAUNCH_FILE="ros2_ws/src/zcw_bringup/launch/four_vehicle_dry_run_planner.launch.py"
CMAKE_FILE="ros2_ws/src/zcw_px4_baseline/CMakeLists.txt"

mkdir -p "${RESULT_DIR}"

for path in "${SOURCE_FILE}" "${LAUNCH_FILE}" "${CMAKE_FILE}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required four-vehicle dry-run contract file missing: ${path}" >&2
    exit 1
  fi
done

{
  echo "Static contract detail"
  echo "--- allowed dry-run topics"
  rg -n '/zcw/multi_vehicle/four_vehicle_dry_run/' "${SOURCE_FILE}" "${LAUNCH_FILE}" || true
  echo "--- px4 out subscriptions"
  rg -n '/px4_[1-4]/fmu/out/' "${SOURCE_FILE}" "${LAUNCH_FILE}" || true
  echo "--- forbidden px4 input topics"
  rg -n '"/(px4_[1-4]/)?fmu/in/|'\''/(px4_[1-4]/)?fmu/in/'\''' "${SOURCE_FILE}" "${LAUNCH_FILE}" "${CMAKE_FILE}" || true
  echo "--- forbidden active control terms"
  rg -n 'OffboardControlMode|TrajectorySetpoint|VehicleCommand|ARMING|arm[(]|Offboard mode|phase_b_user_approved|cable/.*active|/zcw/cable/offboard_gate' "${SOURCE_FILE}" "${LAUNCH_FILE}" "${CMAKE_FILE}" || true
} >"${DETAIL_LOG}" 2>&1

has_source_target=false
has_launch_node=false
has_allowed_outputs=false
has_allowed_inputs=false
forbidden_topics=false
forbidden_active_terms=false

if rg -q 'add_executable\(four_vehicle_dry_run_planner' "${CMAKE_FILE}" &&
   rg -q 'four_vehicle_dry_run_planner' "${CMAKE_FILE}"; then
  has_source_target=true
fi
if rg -q "executable='four_vehicle_dry_run_planner'" "${LAUNCH_FILE}"; then
  has_launch_node=true
fi
if rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_1_goal' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_2_goal' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_3_goal' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_4_goal' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/topology_state' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/safety_state' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/assignment_state' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/scoring_state' "${SOURCE_FILE}" &&
   rg -q '/zcw/multi_vehicle/four_vehicle_dry_run/score_markers' "${SOURCE_FILE}"; then
  has_allowed_outputs=true
fi
has_allowed_inputs=true
for instance in 1 2 3 4; do
  if ! rg -q "/px4_${instance}/fmu/out/" "${SOURCE_FILE}"; then
    has_allowed_inputs=false
  fi
done
if rg -q '"/(px4_[1-4]/)?fmu/in/|'\''/(px4_[1-4]/)?fmu/in/'\''' "${SOURCE_FILE}" "${LAUNCH_FILE}" "${CMAKE_FILE}"; then
  forbidden_topics=true
fi
if rg -q 'OffboardControlMode|TrajectorySetpoint|VehicleCommand|ARMING|arm[(]|Offboard mode|phase_b_user_approved|cable/.*active|/zcw/cable/offboard_gate' "${SOURCE_FILE}" "${LAUNCH_FILE}" "${CMAKE_FILE}"; then
  forbidden_active_terms=true
fi

accepted=false
if [[ "${has_source_target}" == "true" &&
      "${has_launch_node}" == "true" &&
      "${has_allowed_outputs}" == "true" &&
      "${has_allowed_inputs}" == "true" &&
      "${forbidden_topics}" == "false" &&
      "${forbidden_active_terms}" == "false" ]]; then
  accepted=true
fi

{
  echo "scope=four_vehicle_dry_run_contract_static_audit"
  echo "decision=$([[ "${accepted}" == "true" ]] && echo accepted_four_vehicle_dry_run_contract_static_audit || echo rejected_four_vehicle_dry_run_contract_static_audit)"
  echo "reason=$([[ "${accepted}" == "true" ]] && echo dry_run_planner_contract_has_only_allowed_inputs_outputs || echo dry_run_planner_contract_violation)"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "source_file=${SOURCE_FILE}"
  echo "launch_file=${LAUNCH_FILE}"
  echo "cmake_file=${CMAKE_FILE}"
  echo "has_source_target=${has_source_target}"
  echo "has_launch_node=${has_launch_node}"
  echo "has_allowed_outputs=${has_allowed_outputs}"
  echo "has_allowed_inputs=${has_allowed_inputs}"
  echo "forbidden_topics=${forbidden_topics}"
  echo "forbidden_active_terms=${forbidden_active_terms}"
  echo "detail_log=${DETAIL_LOG}"
} >"${SUMMARY_FILE}"

if [[ "${accepted}" != "true" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi

echo "Four-vehicle dry-run contract static audit completed."
echo "Summary: ${SUMMARY_FILE}"
