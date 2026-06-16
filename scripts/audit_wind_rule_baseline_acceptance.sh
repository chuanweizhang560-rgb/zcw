#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_CAPTURE_SUMMARY="data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260615_091712/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260615_091712.txt"
DEFAULT_POSE_SUMMARY="data/results/wind_pose_from_multilevel_slow_loop_20260615_091712/wind_pose_from_px4_local_position_20260615_092317.txt"
DEFAULT_DYNAMIC_SUMMARY="data/results/wind_dynamic_coverage_multilevel_slow_loop_20260615_091712/wind_dynamic_coverage_progression_20260615_092327.txt"
DEFAULT_OCCLUSION_SUMMARY="data/results/wind_occlusion_coverage_multilevel_slow_loop_dense_20260616_000000/wind_occlusion_coverage_progression_20260616_094504.txt"
DEFAULT_LOOP_SUMMARY="data/results/rtabmap_loop_closure_evidence_20260615_093152/rtabmap_loop_closure_evidence_20260615_093152.txt"
DEFAULT_OUTPUT_BOUNDARY_SUMMARY="data/results/rtabmap_wind_capture_output_boundary_20260615_093222/rtabmap_wind_capture_output_boundary_20260615_093222.txt"
DEFAULT_P3D_ATE_SUMMARY="data/results/rtabmap_multilevel_slow_loop_final_db_trajectory_ate_20260615_093152/rtabmap_multilevel_slow_loop_final_db_trajectory_ate_20260615_093152.txt"
DEFAULT_PX4_CROSSCHECK_SUMMARY="data/results/rtabmap_multilevel_slow_loop_px4_final_db_20260615_093152/rtabmap_multilevel_slow_loop_px4_final_db_20260615_093152.txt"

CAPTURE_SUMMARY="${CAPTURE_SUMMARY:-${DEFAULT_CAPTURE_SUMMARY}}"
POSE_SUMMARY="${POSE_SUMMARY:-${DEFAULT_POSE_SUMMARY}}"
DYNAMIC_SUMMARY="${DYNAMIC_SUMMARY:-${DEFAULT_DYNAMIC_SUMMARY}}"
OCCLUSION_SUMMARY="${OCCLUSION_SUMMARY:-${DEFAULT_OCCLUSION_SUMMARY}}"
LOOP_SUMMARY="${LOOP_SUMMARY:-${DEFAULT_LOOP_SUMMARY}}"
OUTPUT_BOUNDARY_SUMMARY="${OUTPUT_BOUNDARY_SUMMARY:-${DEFAULT_OUTPUT_BOUNDARY_SUMMARY}}"
P3D_ATE_SUMMARY="${P3D_ATE_SUMMARY:-${DEFAULT_P3D_ATE_SUMMARY}}"
PX4_CROSSCHECK_SUMMARY="${PX4_CROSSCHECK_SUMMARY:-${DEFAULT_PX4_CROSSCHECK_SUMMARY}}"

MIN_WAYPOINT_ADVANCEMENTS="${MIN_WAYPOINT_ADVANCEMENTS:-120}"
MIN_LOCAL_POSITION_SAMPLES="${MIN_LOCAL_POSITION_SAMPLES:-40000}"
MIN_VALID_POSE_SAMPLES="${MIN_VALID_POSE_SAMPLES:-40000}"
MIN_CAPTURE_DURATION_SEC="${MIN_CAPTURE_DURATION_SEC:-300}"
MIN_CLEARANCE_M="${MIN_CLEARANCE_M:-1.0}"
MIN_DYNAMIC_NORMAL_COVERAGE="${MIN_DYNAMIC_NORMAL_COVERAGE:-0.70}"
MIN_DYNAMIC_BAND_COVERAGE="${MIN_DYNAMIC_BAND_COVERAGE:-0.55}"
MIN_OCCLUSION_CLEAR_COVERAGE="${MIN_OCCLUSION_CLEAR_COVERAGE:-0.65}"
MIN_OCCLUSION_BAND_COVERAGE="${MIN_OCCLUSION_BAND_COVERAGE:-0.55}"
MIN_DB_NODES="${MIN_DB_NODES:-180}"
MIN_OFFICIAL_GLOBAL_CLOSURES="${MIN_OFFICIAL_GLOBAL_CLOSURES:-1}"
MAX_P3D_ATE_RMSE_M="${MAX_P3D_ATE_RMSE_M:-0.01}"
MAX_PX4_CROSSCHECK_P95_M="${MAX_PX4_CROSSCHECK_P95_M:-4.0}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/wind_rule_baseline_acceptance_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/wind_rule_baseline_acceptance_${STAMP}.txt"

for file in \
  "${CAPTURE_SUMMARY}" \
  "${POSE_SUMMARY}" \
  "${DYNAMIC_SUMMARY}" \
  "${OCCLUSION_SUMMARY}" \
  "${LOOP_SUMMARY}" \
  "${OUTPUT_BOUNDARY_SUMMARY}" \
  "${P3D_ATE_SUMMARY}" \
  "${PX4_CROSSCHECK_SUMMARY}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required evidence file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - \
  "${CAPTURE_SUMMARY}" \
  "${POSE_SUMMARY}" \
  "${DYNAMIC_SUMMARY}" \
  "${OCCLUSION_SUMMARY}" \
  "${LOOP_SUMMARY}" \
  "${OUTPUT_BOUNDARY_SUMMARY}" \
  "${P3D_ATE_SUMMARY}" \
  "${PX4_CROSSCHECK_SUMMARY}" \
  "${MIN_WAYPOINT_ADVANCEMENTS}" \
  "${MIN_LOCAL_POSITION_SAMPLES}" \
  "${MIN_VALID_POSE_SAMPLES}" \
  "${MIN_CAPTURE_DURATION_SEC}" \
  "${MIN_CLEARANCE_M}" \
  "${MIN_DYNAMIC_NORMAL_COVERAGE}" \
  "${MIN_DYNAMIC_BAND_COVERAGE}" \
  "${MIN_OCCLUSION_CLEAR_COVERAGE}" \
  "${MIN_OCCLUSION_BAND_COVERAGE}" \
  "${MIN_DB_NODES}" \
  "${MIN_OFFICIAL_GLOBAL_CLOSURES}" \
  "${MAX_P3D_ATE_RMSE_M}" \
  "${MAX_PX4_CROSSCHECK_P95_M}" >"${SUMMARY_FILE}" <<'PY'
import math
import os
import sys

(
    capture_summary,
    pose_summary,
    dynamic_summary,
    occlusion_summary,
    loop_summary,
    output_boundary_summary,
    p3d_ate_summary,
    px4_crosscheck_summary,
    min_waypoint_advancements,
    min_local_position_samples,
    min_valid_pose_samples,
    min_capture_duration_sec,
    min_clearance_m,
    min_dynamic_normal_coverage,
    min_dynamic_band_coverage,
    min_occlusion_clear_coverage,
    min_occlusion_band_coverage,
    min_db_nodes,
    min_official_global_closures,
    max_p3d_ate_rmse_m,
    max_px4_crosscheck_p95_m,
) = sys.argv[1:22]

min_waypoint_advancements = int(min_waypoint_advancements)
min_local_position_samples = int(min_local_position_samples)
min_valid_pose_samples = int(min_valid_pose_samples)
min_capture_duration_sec = float(min_capture_duration_sec)
min_clearance_m = float(min_clearance_m)
min_dynamic_normal_coverage = float(min_dynamic_normal_coverage)
min_dynamic_band_coverage = float(min_dynamic_band_coverage)
min_occlusion_clear_coverage = float(min_occlusion_clear_coverage)
min_occlusion_band_coverage = float(min_occlusion_band_coverage)
min_db_nodes = int(min_db_nodes)
min_official_global_closures = int(min_official_global_closures)
max_p3d_ate_rmse_m = float(max_p3d_ate_rmse_m)
max_px4_crosscheck_p95_m = float(max_px4_crosscheck_p95_m)


def load_kv(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, value = line.split("=", 1)
            out[key] = value
    return out


def f(kv, key, default=math.nan):
    try:
        return float(kv.get(key, default))
    except ValueError:
        return default


def i(kv, key, default=0):
    try:
        return int(float(kv.get(key, default)))
    except ValueError:
        return default


capture = load_kv(capture_summary)
pose = load_kv(pose_summary)
dynamic = load_kv(dynamic_summary)
occlusion = load_kv(occlusion_summary)
loop = load_kv(loop_summary)
output_boundary = load_kv(output_boundary_summary)
p3d_ate = load_kv(p3d_ate_summary)
px4_crosscheck = load_kv(px4_crosscheck_summary)

screenshot = capture.get("screenshot", "")
if screenshot.startswith("/"):
    screenshot_path = screenshot
else:
    screenshot_path = os.path.abspath(screenshot)

capture_ok = (
    capture.get("decision") == "accepted_rtabmap_depth_camera_rgbd_wind_rviz_overlay"
    and capture.get("world") == "wind_turbine"
    and capture.get("launch") == "single_vehicle_wind_turbine_multilevel_slow_loop_closure_smoke.launch.py"
    and capture.get("rtabmap_ok") == "true"
    and capture.get("motion_ok") == "true"
    and capture.get("screenshot_ok") == "1"
    and i(capture, "waypoint_advancements") >= min_waypoint_advancements
    and i(capture, "local_position_trajectory_samples") >= min_local_position_samples
    and os.path.isfile(screenshot_path)
    and os.path.getsize(screenshot_path) > 0
)
pose_ok = (
    pose.get("decision") == "accepted_wind_pose_from_px4_local_position"
    and i(pose, "valid_pose_samples") >= min_valid_pose_samples
    and f(pose, "duration_sec") >= min_capture_duration_sec
    and f(pose, "min_conservative_clearance_m") >= min_clearance_m
)
dynamic_ok = (
    dynamic.get("decision") == "accepted_wind_dynamic_coverage_progression_static_audit"
    and f(dynamic, "final_normal_filtered_coverage_ratio") >= min_dynamic_normal_coverage
    and f(dynamic, "min_band_normal_coverage_ratio_observed") >= min_dynamic_band_coverage
)
occlusion_ok = (
    occlusion.get("decision") == "accepted_wind_occlusion_coverage_progression_static_audit"
    and occlusion.get("uses_trimesh") == "true"
    and occlusion.get("uses_rtree") == "true"
    and f(occlusion, "final_occlusion_clear_normal_coverage_ratio") >= min_occlusion_clear_coverage
    and f(occlusion, "min_band_occlusion_clear_normal_ratio_observed") >= min_occlusion_band_coverage
)
loop_ok = (
    loop.get("decision") == "accepted_rtabmap_loop_closure_evidence_audit"
    and loop.get("claims_task_level_loop_closure_pass") == "true"
    and loop.get("has_official_loop_closure") == "true"
    and i(loop, "node_count") >= min_db_nodes
    and i(loop, "official_global_closure_links") >= min_official_global_closures
)
mapping_boundary_ok = (
    output_boundary.get("decision") == "accepted_rtabmap_wind_capture_output_boundary"
    and output_boundary.get("claims_mapping_evidence_pass") == "true"
    and i(output_boundary, "db_node_count") >= min_db_nodes
    and i(output_boundary, "map_update_count") >= min_db_nodes
)
p3d_ate_ok = (
    p3d_ate.get("decision") == "accepted_rtabmap_multilevel_slow_loop_final_db_trajectory_ate"
    and f(p3d_ate, "rmse_m") <= max_p3d_ate_rmse_m
    and i(p3d_ate, "matched_pair_count") >= 100
)
px4_crosscheck_ok = (
    px4_crosscheck.get("decision") == "accepted_rtabmap_multilevel_slow_loop_px4_final_db"
    and f(px4_crosscheck, "p95_error_m") <= max_px4_crosscheck_p95_m
    and i(px4_crosscheck, "matched_pair_count") >= 100
    and px4_crosscheck.get("claims_ground_truth_accuracy") == "false"
)

accepted = (
    capture_ok
    and pose_ok
    and dynamic_ok
    and occlusion_ok
    and loop_ok
    and mapping_boundary_ok
    and p3d_ate_ok
    and px4_crosscheck_ok
)
decision = "accepted_wind_rule_baseline_acceptance" if accepted else "rejected_wind_rule_baseline_acceptance"
reason = "multilevel_slow_loop_rule_baseline_meets_current_wind_thresholds" if accepted else "one_or_more_wind_rule_baseline_gates_failed"

print("scope=wind_rule_baseline_acceptance")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print("source_capture_started_px4=true")
print("source_capture_started_gazebo=true")
print("source_capture_started_rviz=true")
print("source_capture_started_offboard=true")
print("source_capture_armed=true")
print("source_capture_published_fmu_in=true")
print("scope_boundary=single_vehicle_wind_rule_baseline_only")
print("claims_cable_active_bridge_approval=false")
print("claims_multi_vehicle_active_approval=false")
print("claims_final_inspection_coverage=false")
print(f"capture_summary={capture_summary}")
print(f"pose_summary={pose_summary}")
print(f"dynamic_summary={dynamic_summary}")
print(f"occlusion_summary={occlusion_summary}")
print(f"loop_summary={loop_summary}")
print(f"output_boundary_summary={output_boundary_summary}")
print(f"p3d_ate_summary={p3d_ate_summary}")
print(f"px4_crosscheck_summary={px4_crosscheck_summary}")
print(f"capture_ok={str(capture_ok).lower()}")
print(f"pose_ok={str(pose_ok).lower()}")
print(f"dynamic_ok={str(dynamic_ok).lower()}")
print(f"occlusion_ok={str(occlusion_ok).lower()}")
print(f"loop_ok={str(loop_ok).lower()}")
print(f"mapping_boundary_ok={str(mapping_boundary_ok).lower()}")
print(f"p3d_ate_ok={str(p3d_ate_ok).lower()}")
print(f"px4_crosscheck_ok={str(px4_crosscheck_ok).lower()}")
print(f"waypoint_advancements={i(capture, 'waypoint_advancements')}")
print(f"local_position_trajectory_samples={i(capture, 'local_position_trajectory_samples')}")
print(f"valid_pose_samples={i(pose, 'valid_pose_samples')}")
print(f"duration_sec={f(pose, 'duration_sec'):.9f}")
print(f"min_conservative_clearance_m={f(pose, 'min_conservative_clearance_m'):.9f}")
print(f"final_normal_filtered_coverage_ratio={f(dynamic, 'final_normal_filtered_coverage_ratio'):.9f}")
print(f"min_band_normal_coverage_ratio_observed={f(dynamic, 'min_band_normal_coverage_ratio_observed'):.9f}")
print(f"final_occlusion_clear_normal_coverage_ratio={f(occlusion, 'final_occlusion_clear_normal_coverage_ratio'):.9f}")
print(f"min_band_occlusion_clear_normal_ratio_observed={f(occlusion, 'min_band_occlusion_clear_normal_ratio_observed'):.9f}")
print(f"rtabmap_node_count={i(loop, 'node_count')}")
print(f"official_global_closure_links={i(loop, 'official_global_closure_links')}")
print(f"official_local_space_closure_links={i(loop, 'official_local_space_closure_links')}")
print(f"map_update_count={i(output_boundary, 'map_update_count')}")
print(f"p3d_ate_rmse_m={f(p3d_ate, 'rmse_m'):.9f}")
print(f"px4_crosscheck_p95_error_m={f(px4_crosscheck, 'p95_error_m'):.9f}")
print(f"screenshot={screenshot_path}")
print(f"claims_wind_rule_baseline_acceptance_pass={str(accepted).lower()}")
PY

echo "Wind rule baseline acceptance audit completed."
echo "Summary: ${SUMMARY_FILE}"

grep -q "decision=accepted_wind_rule_baseline_acceptance" "${SUMMARY_FILE}"
