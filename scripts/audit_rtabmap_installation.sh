#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_installation_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_installation_${STAMP}.txt"
DPKG_LOG="${RESULT_DIR}/rtabmap_dpkg_${STAMP}.log"
PKG_LOG="${RESULT_DIR}/rtabmap_ros2_packages_${STAMP}.log"
EXEC_LOG="${RESULT_DIR}/rtabmap_executables_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

dpkg -l | rg 'ros-humble-rtabmap(-ros|-slam|-odom|-util)?\s' >"${DPKG_LOG}"

bash -lc "source /opt/ros/humble/setup.bash && ros2 pkg list | rg '^rtabmap'" >"${PKG_LOG}"

bash -lc "source /opt/ros/humble/setup.bash && ros2 pkg executables rtabmap_slam && ros2 pkg executables rtabmap_odom && ros2 pkg executables rtabmap_util" >"${EXEC_LOG}"

required_packages=(
  rtabmap_ros
  rtabmap_slam
  rtabmap_odom
  rtabmap_util
)

required_executables=(
  "rtabmap_slam rtabmap"
  "rtabmap_odom icp_odometry"
  "rtabmap_odom rgbd_odometry"
  "rtabmap_util point_cloud_xyz"
  "rtabmap_util point_cloud_assembler"
)

missing_count=0

for package in "${required_packages[@]}"; do
  if ! grep -qx "${package}" "${PKG_LOG}"; then
    missing_count=$((missing_count + 1))
  fi
done

for executable in "${required_executables[@]}"; do
  if ! grep -qx "${executable}" "${EXEC_LOG}"; then
    missing_count=$((missing_count + 1))
  fi
done

decision="accepted_rtabmap_installation"
reason="rtabmap_ros2_packages_and_required_executables_present"
if (( missing_count > 0 )); then
  decision="rejected_rtabmap_installation"
  reason="required_rtabmap_package_or_executable_missing"
fi

{
  echo "scope=rtabmap_installation"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "apt_package=ros-humble-rtabmap-ros"
  echo "dpkg_log=${DPKG_LOG}"
  echo "pkg_log=${PKG_LOG}"
  echo "exec_log=${EXEC_LOG}"
  echo "missing_count=${missing_count}"
} >"${SUMMARY_FILE}"

echo "RTAB-Map installation audit completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_rtabmap_installation" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi
