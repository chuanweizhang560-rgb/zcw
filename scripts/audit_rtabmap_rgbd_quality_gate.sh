#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_rgbd_quality_gate_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_rgbd_quality_gate_${STAMP}.txt"
DETAIL_FILE="${RESULT_DIR}/rtabmap_rgbd_quality_gate_detail_${STAMP}.log"

SMOKE_SUMMARY="${SMOKE_SUMMARY:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_smoke_20260608_104242/rtabmap_depth_camera_rgbd_smoke_20260608_104242.txt}"
CONSISTENCY_SUMMARY="${CONSISTENCY_SUMMARY:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_consistency_20260608_104242/rtabmap_depth_camera_rgbd_consistency_20260608_104242.txt}"
STATIC_RVIZ_SUMMARY="${STATIC_RVIZ_SUMMARY:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_rviz_overlay_20260608_104629/rtabmap_depth_camera_rgbd_rviz_overlay_20260608_104629.txt}"
MOTION_RVIZ_SUMMARY="${MOTION_RVIZ_SUMMARY:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260608_104943/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260608_104943.txt}"
WIND_RVIZ_SUMMARY="${WIND_RVIZ_SUMMARY:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840.txt}"

mkdir -p "${RESULT_DIR}"

value_for() {
  local key="$1"
  local file="$2"
  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${file}"
}

require_file() {
  local file="$1"
  [[ -f "${file}" ]]
}

image_dims() {
  local file="$1"
  identify -format "%w,%h" "${file}" 2>/dev/null || echo "0,0"
}

image_mean() {
  local file="$1"
  identify -format "%[mean]" "${file}" 2>/dev/null || echo "0"
}

for required in \
  "${SMOKE_SUMMARY}" \
  "${CONSISTENCY_SUMMARY}" \
  "${STATIC_RVIZ_SUMMARY}" \
  "${MOTION_RVIZ_SUMMARY}" \
  "${WIND_RVIZ_SUMMARY}"; do
  if ! require_file "${required}"; then
    echo "Required RTAB-Map evidence file missing: ${required}" >&2
    exit 1
  fi
done

smoke_accepted=false
consistency_accepted=false
static_rviz_accepted=false
motion_rviz_accepted=false
wind_rviz_accepted=false
static_outputs_ok=false
motion_outputs_ok=false
wind_outputs_ok=false
static_no_active=false
smoke_no_active=false
topics_have_map=false
topics_have_cloud=false
topics_have_octomap=false
depth_contract_ok=false
static_screenshot_ok=false
motion_screenshot_ok=false
wind_screenshot_ok=false

[[ "$(value_for decision "${SMOKE_SUMMARY}")" == "accepted_rtabmap_depth_camera_rgbd_smoke" ]] && smoke_accepted=true
[[ "$(value_for decision "${CONSISTENCY_SUMMARY}")" == "accepted_rtabmap_depth_camera_rgbd_consistency" ]] && consistency_accepted=true
[[ "$(value_for decision "${STATIC_RVIZ_SUMMARY}")" == "accepted_rtabmap_depth_camera_rgbd_rviz_overlay" ]] && static_rviz_accepted=true
[[ "$(value_for decision "${MOTION_RVIZ_SUMMARY}")" == "accepted_rtabmap_depth_camera_rgbd_motion_rviz_overlay" ]] && motion_rviz_accepted=true
[[ "$(value_for decision "${WIND_RVIZ_SUMMARY}")" == "accepted_rtabmap_depth_camera_rgbd_wind_rviz_overlay" ]] && wind_rviz_accepted=true
[[ "$(value_for outputs_ok "${STATIC_RVIZ_SUMMARY}")" == "true" ]] && static_outputs_ok=true
[[ "$(value_for outputs_ok "${MOTION_RVIZ_SUMMARY}")" == "true" ]] && motion_outputs_ok=true
[[ "$(value_for outputs_ok "${WIND_RVIZ_SUMMARY}")" == "true" ]] && wind_outputs_ok=true
[[ "$(value_for starts_offboard "${STATIC_RVIZ_SUMMARY}")" == "false" && "$(value_for arms "${STATIC_RVIZ_SUMMARY}")" == "false" && "$(value_for publishes_fmu_in "${STATIC_RVIZ_SUMMARY}")" == "false" ]] && static_no_active=true
[[ "$(value_for starts_offboard "${SMOKE_SUMMARY}")" == "false" && "$(value_for arms "${SMOKE_SUMMARY}")" == "false" && "$(value_for publishes_fmu_in "${SMOKE_SUMMARY}")" == "false" ]] && smoke_no_active=true

topics_log="$(value_for topics_log "${STATIC_RVIZ_SUMMARY}")"
depth_sample_log="$(value_for depth_sample_log "${STATIC_RVIZ_SUMMARY}")"
static_screenshot="$(value_for screenshot "${STATIC_RVIZ_SUMMARY}")"
motion_screenshot="$(value_for screenshot "${MOTION_RVIZ_SUMMARY}")"
wind_screenshot="$(value_for screenshot "${WIND_RVIZ_SUMMARY}")"

if [[ -f "${topics_log}" ]]; then
  rg -q '^/map$' "${topics_log}" && topics_have_map=true
  rg -q '^/cloud_map$' "${topics_log}" && topics_have_cloud=true
  rg -q '^/octomap_(binary|full|grid|occupied_space)$' "${topics_log}" && topics_have_octomap=true
fi
if [[ -f "${depth_sample_log}" ]] &&
   rg -q 'height: 480' "${depth_sample_log}" &&
   rg -q 'width: 848' "${depth_sample_log}" &&
   rg -q 'encoding: 32FC1' "${depth_sample_log}"; then
  depth_contract_ok=true
fi

static_dims="0,0"
motion_dims="0,0"
wind_dims="0,0"
static_mean="0"
motion_mean="0"
wind_mean="0"
if [[ -f "${static_screenshot}" ]]; then
  static_dims="$(image_dims "${static_screenshot}")"
  static_mean="$(image_mean "${static_screenshot}")"
fi
if [[ -f "${motion_screenshot}" ]]; then
  motion_dims="$(image_dims "${motion_screenshot}")"
  motion_mean="$(image_mean "${motion_screenshot}")"
fi
if [[ -f "${wind_screenshot}" ]]; then
  wind_dims="$(image_dims "${wind_screenshot}")"
  wind_mean="$(image_mean "${wind_screenshot}")"
fi

static_width="${static_dims%,*}"
static_height="${static_dims#*,}"
motion_width="${motion_dims%,*}"
motion_height="${motion_dims#*,}"
wind_width="${wind_dims%,*}"
wind_height="${wind_dims#*,}"

if (( static_width >= 640 && static_height >= 480 )) && awk -v mean="${static_mean}" 'BEGIN { exit !(mean > 1000) }'; then
  static_screenshot_ok=true
fi
if (( motion_width >= 640 && motion_height >= 480 )) && awk -v mean="${motion_mean}" 'BEGIN { exit !(mean > 1000) }'; then
  motion_screenshot_ok=true
fi
if (( wind_width >= 640 && wind_height >= 480 )) && awk -v mean="${wind_mean}" 'BEGIN { exit !(mean > 1000) }'; then
  wind_screenshot_ok=true
fi

quality_gate_score=0
for flag in \
  "${smoke_accepted}" \
  "${consistency_accepted}" \
  "${static_rviz_accepted}" \
  "${motion_rviz_accepted}" \
  "${wind_rviz_accepted}" \
  "${static_outputs_ok}" \
  "${motion_outputs_ok}" \
  "${wind_outputs_ok}" \
  "${topics_have_map}" \
  "${topics_have_cloud}" \
  "${topics_have_octomap}" \
  "${depth_contract_ok}" \
  "${static_screenshot_ok}" \
  "${motion_screenshot_ok}" \
  "${wind_screenshot_ok}" \
  "${static_no_active}" \
  "${smoke_no_active}"; do
  [[ "${flag}" == "true" ]] && quality_gate_score=$((quality_gate_score + 1))
done

accepted=false
reason="rtabmap_rgbd_quality_gate_missing_required_evidence"
if [[ "${smoke_accepted}" == "true" &&
      "${consistency_accepted}" == "true" &&
      "${static_rviz_accepted}" == "true" &&
      "${motion_rviz_accepted}" == "true" &&
      "${wind_rviz_accepted}" == "true" &&
      "${static_outputs_ok}" == "true" &&
      "${motion_outputs_ok}" == "true" &&
      "${wind_outputs_ok}" == "true" &&
      "${topics_have_map}" == "true" &&
      "${topics_have_cloud}" == "true" &&
      "${topics_have_octomap}" == "true" &&
      "${depth_contract_ok}" == "true" &&
      "${static_screenshot_ok}" == "true" &&
      "${motion_screenshot_ok}" == "true" &&
      "${wind_screenshot_ok}" == "true" &&
      "${static_no_active}" == "true" &&
      "${smoke_no_active}" == "true" ]]; then
  accepted=true
  reason="rgbd_slam_baseline_has_stable_outputs_topics_depth_contract_and_visual_evidence"
fi

{
  echo "scope=rtabmap_rgbd_quality_gate"
  echo "decision=$([[ "${accepted}" == "true" ]] && echo accepted_rtabmap_rgbd_quality_gate || echo rejected_rtabmap_rgbd_quality_gate)"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "uses_gazebo_pose_as_debug_odom=true"
  echo "claims_slam_accuracy=false"
  echo "quality_gate_score=${quality_gate_score}/17"
  echo "smoke_accepted=${smoke_accepted}"
  echo "consistency_accepted=${consistency_accepted}"
  echo "static_rviz_accepted=${static_rviz_accepted}"
  echo "motion_rviz_accepted=${motion_rviz_accepted}"
  echo "wind_rviz_accepted=${wind_rviz_accepted}"
  echo "static_outputs_ok=${static_outputs_ok}"
  echo "motion_outputs_ok=${motion_outputs_ok}"
  echo "wind_outputs_ok=${wind_outputs_ok}"
  echo "topics_have_map=${topics_have_map}"
  echo "topics_have_cloud=${topics_have_cloud}"
  echo "topics_have_octomap=${topics_have_octomap}"
  echo "depth_contract_ok=${depth_contract_ok}"
  echo "static_screenshot_ok=${static_screenshot_ok}"
  echo "motion_screenshot_ok=${motion_screenshot_ok}"
  echo "wind_screenshot_ok=${wind_screenshot_ok}"
  echo "static_screenshot_dims=${static_dims}"
  echo "motion_screenshot_dims=${motion_dims}"
  echo "wind_screenshot_dims=${wind_dims}"
  echo "static_screenshot_mean=${static_mean}"
  echo "motion_screenshot_mean=${motion_mean}"
  echo "wind_screenshot_mean=${wind_mean}"
  echo "static_no_active=${static_no_active}"
  echo "smoke_no_active=${smoke_no_active}"
  echo "smoke_summary=${SMOKE_SUMMARY}"
  echo "consistency_summary=${CONSISTENCY_SUMMARY}"
  echo "static_rviz_summary=${STATIC_RVIZ_SUMMARY}"
  echo "motion_rviz_summary=${MOTION_RVIZ_SUMMARY}"
  echo "wind_rviz_summary=${WIND_RVIZ_SUMMARY}"
  echo "topics_log=${topics_log}"
  echo "depth_sample_log=${depth_sample_log}"
  echo "static_screenshot=${static_screenshot}"
  echo "motion_screenshot=${motion_screenshot}"
  echo "wind_screenshot=${wind_screenshot}"
} >"${SUMMARY_FILE}"

cp "${SUMMARY_FILE}" "${DETAIL_FILE}"

if [[ "${accepted}" != "true" ]]; then
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi

echo "RTAB-Map RGB-D quality gate audit completed."
echo "Summary: ${SUMMARY_FILE}"
