#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH_CSV="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH_CSV}}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_POSES_PER_GROUP="${MIN_POSES_PER_GROUP:-25}"
TARGET_DISTANCE_M="${TARGET_DISTANCE_M:-5.0}"
MAX_DISTANCE_ERROR_M="${MAX_DISTANCE_ERROR_M:-0.001}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_surface_observation_pose_candidate_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_surface_observation_pose_candidate_${STAMP}.txt"
POSE_CSV="${RESULT_DIR}/cable_surface_observation_pose_candidate_${STAMP}.csv"

if [[ ! -f "${OFFSET_PATH_CSV}" ]]; then
  echo "Required input file does not exist: ${OFFSET_PATH_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "${OFFSET_PATH_CSV}" "${POSE_CSV}" "${MIN_GROUPS}" "${MIN_POSES_PER_GROUP}" \
  "${TARGET_DISTANCE_M}" "${MAX_DISTANCE_ERROR_M}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

offset_path_csv, pose_csv, min_groups, min_poses_per_group, target_distance_m, max_distance_error_m = sys.argv[1:7]
min_groups = int(min_groups)
min_poses_per_group = int(min_poses_per_group)
target_distance_m = float(target_distance_m)
max_distance_error_m = float(max_distance_error_m)

rows = []
with open(offset_path_csv, newline="") as f:
    for row in csv.DictReader(f):
        camera = (float(row["x"]), float(row["y"]), float(row["z"]))
        target = (float(row["source_x"]), float(row["source_y"]), float(row["source_z"]))
        vec = tuple(t - c for t, c in zip(target, camera))
        horizontal = math.hypot(vec[0], vec[1])
        distance = math.sqrt(sum(v * v for v in vec))
        yaw = math.atan2(vec[1], vec[0])
        pitch = math.atan2(vec[2], horizontal)
        rows.append(
            {
                "group_id": row["group_id"],
                "index": int(row["index"]),
                "camera_x": camera[0],
                "camera_y": camera[1],
                "camera_z": camera[2],
                "target_x": target[0],
                "target_y": target[1],
                "target_z": target[2],
                "target_distance_m": distance,
                "target_distance_error_m": abs(distance - target_distance_m),
                "yaw_rad": yaw,
                "pitch_rad": pitch,
                "yaw_deg": math.degrees(yaw),
                "pitch_deg": math.degrees(pitch),
                "finite_pose": str(all(math.isfinite(v) for v in (distance, yaw, pitch))).lower(),
            }
        )

rows.sort(key=lambda r: (r["group_id"], r["index"]))

with open(pose_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "group_id",
            "index",
            "camera_x",
            "camera_y",
            "camera_z",
            "target_x",
            "target_y",
            "target_z",
            "target_distance_m",
            "target_distance_error_m",
            "yaw_rad",
            "pitch_rad",
            "yaw_deg",
            "pitch_deg",
            "finite_pose",
        ],
    )
    writer.writeheader()
    writer.writerows(rows)

groups = defaultdict(list)
for row in rows:
    groups[row["group_id"]].append(row)

group_count = len(groups)
accepted_group_count = 0
max_distance_error = 0.0
min_distance = math.inf
max_distance = 0.0
min_pitch = math.inf
max_pitch = -math.inf

for group_rows in groups.values():
    group_ok = len(group_rows) >= min_poses_per_group
    for row in group_rows:
        max_distance_error = max(max_distance_error, row["target_distance_error_m"])
        min_distance = min(min_distance, row["target_distance_m"])
        max_distance = max(max_distance, row["target_distance_m"])
        min_pitch = min(min_pitch, row["pitch_deg"])
        max_pitch = max(max_pitch, row["pitch_deg"])
        group_ok = group_ok and row["finite_pose"] == "true" and row["target_distance_error_m"] <= max_distance_error_m
    if group_ok:
        accepted_group_count += 1

accepted = group_count >= min_groups and accepted_group_count >= min_groups
decision = "accepted_cable_surface_observation_pose_candidate" if accepted else "rejected_cable_surface_observation_pose_candidate"
reason = "all_groups_have_finite_offset_to_source_observation_poses" if accepted else "one_or_more_groups_failed_pose_candidate_checks"

print("scope=cable_surface_observation_pose_candidate")
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
print(f"pose_csv={pose_csv}")
print(f"min_groups={min_groups}")
print(f"min_poses_per_group={min_poses_per_group}")
print(f"target_distance_m={target_distance_m:.9f}")
print(f"max_distance_error_m={max_distance_error_m:.9f}")
print(f"group_count={group_count}")
print(f"accepted_group_count={accepted_group_count}")
print(f"pose_count={len(rows)}")
print(f"min_target_distance_m={min_distance:.9f}")
print(f"max_target_distance_m={max_distance:.9f}")
print(f"global_max_target_distance_error_m={max_distance_error:.9f}")
print(f"min_pitch_deg={min_pitch:.9f}")
print(f"max_pitch_deg={max_pitch:.9f}")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_surface_observation_pose_candidate_pass={str(accepted).lower()}")
PY

echo "Cable surface observation pose candidate audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Pose CSV: ${POSE_CSV}"

grep -q "decision=accepted_cable_surface_observation_pose_candidate" "${SUMMARY_FILE}"
