#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
OUTPUT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/px4_isolation_audit_${STAMP}}"
SUMMARY="${OUTPUT_DIR}/px4_isolation_audit_${STAMP}.txt"
DETAILS="${OUTPUT_DIR}/px4_isolation_audit_details_${STAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

status=0
{
  echo "PX4 isolation audit"
  echo "timestamp: ${STAMP}"
  echo "scope: ros2_ws/src/zcw_cable_perception scripts/verify_lookahead_* scripts/capture_lookahead_*"
  echo

  echo "[check] package.xml must not depend on px4_msgs"
  if rg -n '<depend>px4_msgs</depend>|<build_depend>px4_msgs</build_depend>|<exec_depend>px4_msgs</exec_depend>' \
    ros2_ws/src/zcw_cable_perception/package.xml >"${OUTPUT_DIR}/package_px4_msgs_matches.txt"; then
    echo "FAIL: px4_msgs dependency found"
    status=1
  else
    echo "PASS"
  fi
  echo

  echo "[check] CMakeLists.txt must not find or link px4_msgs"
  if rg -n 'px4_msgs|TrajectorySetpoint|VehicleCommand|OffboardControlMode' \
    ros2_ws/src/zcw_cable_perception/CMakeLists.txt >"${OUTPUT_DIR}/cmake_px4_matches.txt"; then
    echo "FAIL: PX4 CMake reference found"
    status=1
  else
    echo "PASS"
  fi
  echo

  echo "[check] cable perception source must not include PX4 message APIs"
  if rg -n 'px4_msgs|TrajectorySetpoint|VehicleCommand|OffboardControlMode' \
    ros2_ws/src/zcw_cable_perception/src >"${OUTPUT_DIR}/source_px4_api_matches.txt"; then
    echo "FAIL: PX4 message API reference found"
    status=1
  else
    echo "PASS"
  fi
  echo

  echo "[check] cable perception source must not publish /fmu/in topics"
  if rg -n '"/fmu/in/|/fmu/in/' \
    ros2_ws/src/zcw_cable_perception/src >"${OUTPUT_DIR}/source_fmu_in_matches.txt"; then
    echo "FAIL: /fmu/in source reference found"
    status=1
  else
    echo "PASS"
  fi
  echo

  echo "[check] lookahead scripts must not publish /fmu/in topics"
  if rg -n 'ros2 topic pub.*/fmu/in|/fmu/in/trajectory_setpoint|/fmu/in/offboard_control_mode|/fmu/in/vehicle_command' \
    scripts/verify_lookahead_* scripts/capture_lookahead_* >"${OUTPUT_DIR}/script_fmu_in_publish_matches.txt"; then
    echo "FAIL: lookahead script forbidden PX4 input publish found"
    status=1
  else
    echo "PASS"
  fi
  echo

  echo "[check] dry-run debug topics are under /zcw/cable/dry_run"
  if rg -n '/zcw/cable/dry_run/(state|candidate_setpoint|path)' \
    ros2_ws/src/zcw_cable_perception/src/lookahead_dry_run_setpoint.cpp >"${OUTPUT_DIR}/dry_run_topic_matches.txt"; then
    echo "PASS"
  else
    echo "FAIL: expected dry-run debug topics not found"
    status=1
  fi
  echo

  if [[ "${status}" -eq 0 ]]; then
    echo "decision: accepted_px4_isolation_smoke"
  else
    echo "decision: rejected_px4_isolation_smoke"
  fi
} | tee "${SUMMARY}" >"${DETAILS}"

echo "PX4 isolation audit completed."
echo "Summary: ${SUMMARY}"
echo "Details: ${DETAILS}"
exit "${status}"
