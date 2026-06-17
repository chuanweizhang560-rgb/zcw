#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH_CSV="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_CAMERA_POSE_LOG="data/logs/rtabmap_depth_camera_rgbd_motion_rviz_depth_pose_trajectory_20260612_132911.log"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH_CSV}}"
CAMERA_POSE_LOG="${CAMERA_POSE_LOG:-${DEFAULT_CAMERA_POSE_LOG}}"
MIN_POSE_SAMPLES="${MIN_POSE_SAMPLES:-100}"
MIN_PATH_POINTS="${MIN_PATH_POINTS:-100}"
INSPECTION_DISTANCE_M="${INSPECTION_DISTANCE_M:-30.0}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_surface_coverage_input_gap_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_surface_coverage_input_gap_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_surface_coverage_input_gap_groups_${STAMP}.csv"

for file in "${OFFSET_PATH_CSV}" "${CAMERA_POSE_LOG}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required input file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${OFFSET_PATH_CSV}" "${CAMERA_POSE_LOG}" "${GROUP_CSV}" \
  "${MIN_POSE_SAMPLES}" "${MIN_PATH_POINTS}" "${INSPECTION_DISTANCE_M}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import re
import sys
from collections import defaultdict

offset_path_csv, camera_pose_log, group_csv, min_pose_samples, min_path_points, inspection_distance_m = sys.argv[1:7]
min_pose_samples = int(min_pose_samples)
min_path_points = int(min_path_points)
inspection_distance_m = float(inspection_distance_m)


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def bounds(points):
    out = {}
    for idx, axis in enumerate("xyz"):
        vals = [p[idx] for p in points]
        out[f"{axis}_min"] = min(vals)
        out[f"{axis}_max"] = max(vals)
        out[f"{axis}_mean"] = sum(vals) / len(vals)
    return out


path_groups = defaultdict(list)
with open(offset_path_csv, newline="") as f:
    for row in csv.DictReader(f):
        path_groups[row["group_id"]].append(
            (float(row["x"]), float(row["y"]), float(row["z"]))
        )

camera_poses = []
current = {}
section = None
with open(camera_pose_log) as f:
    for line in f:
        stripped = line.strip()
        if stripped == "---":
            if all(key in current for key in ("x", "y", "z")):
                camera_poses.append((current["x"], current["y"], current["z"]))
            current = {}
            section = None
            continue
        if stripped == "position:":
            section = "position"
            continue
        if stripped == "orientation:":
            section = "orientation"
            continue
        match = re.match(r"([xyz]):\s*([-+0-9.eE]+)$", stripped)
        if match and section == "position":
            current[match.group(1)] = float(match.group(2))
if all(key in current for key in ("x", "y", "z")):
    camera_poses.append((current["x"], current["y"], current["z"]))

all_path_points = [pt for pts in path_groups.values() for pt in pts]
input_ok = len(camera_poses) >= min_pose_samples and len(all_path_points) >= min_path_points

group_rows = []
covered_group_count = 0
for group_id in sorted(path_groups):
    pts = path_groups[group_id]
    nearest = []
    for point in pts:
        nearest.append(min(dist(point, pose) for pose in camera_poses))
    min_distance = min(nearest)
    max_nearest_distance = max(nearest)
    mean_nearest_distance = sum(nearest) / len(nearest)
    distance_gate_ready = max_nearest_distance <= inspection_distance_m
    if distance_gate_ready:
        covered_group_count += 1
    group_rows.append(
        {
            "group_id": group_id,
            "path_points": len(pts),
            "min_camera_distance_m": min_distance,
            "mean_nearest_camera_distance_m": mean_nearest_distance,
            "max_nearest_camera_distance_m": max_nearest_distance,
            "inspection_distance_m": inspection_distance_m,
            "distance_gate_ready": str(distance_gate_ready).lower(),
        }
    )

with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "group_id",
            "path_points",
            "min_camera_distance_m",
            "mean_nearest_camera_distance_m",
            "max_nearest_camera_distance_m",
            "inspection_distance_m",
            "distance_gate_ready",
        ],
    )
    writer.writeheader()
    writer.writerows(group_rows)

path_bounds = bounds(all_path_points) if all_path_points else {}
pose_bounds = bounds(camera_poses) if camera_poses else {}
global_min_distance = min(row["min_camera_distance_m"] for row in group_rows) if group_rows else math.inf
global_max_nearest_distance = max(row["max_nearest_camera_distance_m"] for row in group_rows) if group_rows else math.inf
coverage_claimable = (
    input_ok
    and covered_group_count == len(group_rows)
    and False
)

decision = "accepted_cable_surface_coverage_input_gap"
reason = "inputs_parsed_and_gap_recorded"

print("scope=cable_surface_coverage_input_gap")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"offset_path_csv={offset_path_csv}")
print(f"camera_pose_log={camera_pose_log}")
print(f"group_csv={group_csv}")
print(f"min_pose_samples={min_pose_samples}")
print(f"min_path_points={min_path_points}")
print(f"inspection_distance_m={inspection_distance_m:.9f}")
print(f"camera_pose_count={len(camera_poses)}")
print(f"path_point_count={len(all_path_points)}")
print(f"group_count={len(group_rows)}")
print(f"distance_ready_group_count={covered_group_count}")
print(f"input_ok={str(input_ok).lower()}")
print(f"global_min_camera_distance_m={global_min_distance:.9f}")
print(f"global_max_nearest_camera_distance_m={global_max_nearest_distance:.9f}")
for prefix, b in (("path", path_bounds), ("camera", pose_bounds)):
    for key in ("x_min", "x_max", "y_min", "y_max", "z_min", "z_max"):
        print(f"{prefix}_{key}={b.get(key, math.nan):.9f}")
print("fov_gate_implemented=false")
print("occlusion_gate_implemented=false")
print("surface_sampling_implemented=false")
print("claims_final_cable_inspection_coverage=false")
print(f"coverage_claimable={str(coverage_claimable).lower()}")
PY

echo "Cable surface coverage input-gap audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_surface_coverage_input_gap" "${SUMMARY_FILE}"
