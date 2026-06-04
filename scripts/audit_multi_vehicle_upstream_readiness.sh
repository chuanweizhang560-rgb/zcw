#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/multi_vehicle_upstream_readiness_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/multi_vehicle_upstream_readiness_${STAMP}.txt"

PX4_ROOT="${PX4_ROOT:-third_party/PX4-Autopilot-release-1.14}"
MULTI_SCRIPT="${PX4_ROOT}/Tools/simulation/gazebo-classic/sitl_multiple_run.sh"
RCS_FILE="${PX4_ROOT}/ROMFS/px4fmu_common/init.d-posix/rcS"
MAVLINK_FILE="${PX4_ROOT}/ROMFS/px4fmu_common/init.d-posix/px4-rc.mavlink"

mkdir -p "${RESULT_DIR}"

for path in "${MULTI_SCRIPT}" "${RCS_FILE}" "${MAVLINK_FILE}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required PX4 upstream file missing: ${path}" >&2
    exit 1
  fi
done

has_pattern() {
  local name="$1"
  local pattern="$2"
  local file="$3"
  if rg -q "${pattern}" "${file}"; then
    echo "${name}=true"
    return 0
  fi
  echo "${name}=false"
  return 1
}

multi_script_supported=true
rcs_namespace_supported=true
mavlink_ports_supported=true

{
  echo "scope=multi_vehicle_upstream_readiness"
  echo "decision=accepted_multi_vehicle_upstream_static_audit"
  echo "reason=px4_release_1_14_contains_gazebo_classic_multi_instance_and_dds_namespace_support"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "px4_root=${PX4_ROOT}"
  echo "multi_script=${MULTI_SCRIPT}"
  echo "rcs_file=${RCS_FILE}"
  echo "mavlink_file=${MAVLINK_FILE}"

  has_pattern "has_gazebo_classic_multi_script" "run multiple instances.*gazebo SITL" "${MULTI_SCRIPT}" || multi_script_supported=false
  has_pattern "has_spawn_model_function" "function spawn_model" "${MULTI_SCRIPT}" || multi_script_supported=false
  has_pattern "has_instance_tcp_port_offset" "4560\\+\\$\\{N\\}" "${MULTI_SCRIPT}" || multi_script_supported=false
  has_pattern "has_instance_udp_port_offset" "14560\\+\\$\\{N\\}" "${MULTI_SCRIPT}" || multi_script_supported=false
  has_pattern "has_supported_iris_model" "SUPPORTED_MODELS=.*iris" "${MULTI_SCRIPT}" || multi_script_supported=false

  has_pattern "has_mav_sys_id_per_instance" "param set MAV_SYS_ID \\$\\(\\(px4_instance\\+1\\)\\)" "${RCS_FILE}" || rcs_namespace_supported=false
  has_pattern "has_uxrce_key_per_instance" "param set UXRCE_DDS_KEY \\$\\(\\(px4_instance\\+1\\)\\)" "${RCS_FILE}" || rcs_namespace_supported=false
  has_pattern "has_nonzero_px4_namespace" 'uxrce_dds_ns="-n px4_\$px4_instance"' "${RCS_FILE}" || rcs_namespace_supported=false
  has_pattern "has_uxrce_udp_default_port" "uxrce_dds_port=8888" "${RCS_FILE}" || rcs_namespace_supported=false
  has_pattern "has_uxrce_start_udp" "uxrce_dds_client start -t udp" "${RCS_FILE}" || rcs_namespace_supported=false

  has_pattern "has_mavlink_offboard_local_port_offset" "udp_offboard_port_local=\\$\\(\\(14580\\+px4_instance\\)\\)" "${MAVLINK_FILE}" || mavlink_ports_supported=false
  has_pattern "has_mavlink_offboard_remote_port_offset" "udp_offboard_port_remote=\\$\\(\\(14540\\+px4_instance\\)\\)" "${MAVLINK_FILE}" || mavlink_ports_supported=false
  has_pattern "has_mavlink_gcs_local_port_offset" "udp_gcs_port_local=\\$\\(\\(18570\\+px4_instance\\)\\)" "${MAVLINK_FILE}" || mavlink_ports_supported=false

  echo "multi_script_supported=${multi_script_supported}"
  echo "rcs_namespace_supported=${rcs_namespace_supported}"
  echo "mavlink_ports_supported=${mavlink_ports_supported}"
  echo "recommended_next_script=scripts/verify_px4_gazebo_classic_multi_vehicle_readonly.sh"
  echo "recommended_next_scope=two_vehicle_headless_readonly_topics_before_any_multi_offboard"
} >"${SUMMARY_FILE}"

if [[ "${multi_script_supported}" != "true" || "${rcs_namespace_supported}" != "true" || "${mavlink_ports_supported}" != "true" ]]; then
  sed -i 's/^decision=.*/decision=rejected_multi_vehicle_upstream_static_audit/' "${SUMMARY_FILE}"
  sed -i 's/^reason=.*/reason=required_px4_multi_instance_patterns_missing/' "${SUMMARY_FILE}"
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi

echo "Multi-vehicle upstream readiness audit completed."
echo "Summary: ${SUMMARY_FILE}"
