#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_POSE_CSV="data/results/cable_surface_observation_pose_candidate_20260617_091638/cable_surface_observation_pose_candidate_20260617_091638.csv"
POSE_CSV="${POSE_CSV:-${DEFAULT_POSE_CSV}}"
MIN_SOURCE_GROUPS="${MIN_SOURCE_GROUPS:-5}"
MIN_VIEWS_PER_SOURCE_GROUP="${MIN_VIEWS_PER_SOURCE_GROUP:-2}"
TARGET_DISTANCE_M="${TARGET_DISTANCE_M:-5.0}"
MAX_DISTANCE_ERROR_M="${MAX_DISTANCE_ERROR_M:-0.001}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_multiview_surface_candidate_offline_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_multiview_surface_candidate_offline_${STAMP}.txt"
MULTIVIEW_CSV="${RESULT_DIR}/cable_multiview_surface_candidate_offline_${STAMP}.csv"

if [[ ! -f "${POSE_CSV}" ]]; then
  echo "Required input file does not exist: ${POSE_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "${POSE_CSV}" "${MULTIVIEW_CSV}" "${MIN_SOURCE_GROUPS}" "${MIN_VIEWS_PER_SOURCE_GROUP}" \
  "${TARGET_DISTANCE_M}" "${MAX_DISTANCE_ERROR_M}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

pose_csv, multiview_csv, min_source_groups, min_views_per_source_group, target_distance_m, max_distance_error_m = sys.argv[1:7]
min_source_groups = int(min_source_groups)
min_views_per_source_group = int(min_views_per_source_group)
target_distance_m = float(target_distance_m)
max_distance_error_m = float(max_distance_error_m)


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def norm(a):
    return math.sqrt(sum(x * x for x in a))


def unit(a):
    n = norm(a)
    if n <= 1e-12:
        return (0.0, 0.0, 0.0)
    return tuple(x / n for x in a)


def yaw_pitch(camera, target):
    vec = sub(target, camera)
    horizontal = math.hypot(vec[0], vec[1])
    yaw = math.atan2(vec[1], vec[0])
    pitch = math.atan2(vec[2], horizontal)
    return yaw, pitch, norm(vec)


rows = []
with open(pose_csv, newline="") as f:
    for row in csv.DictReader(f):
        for key in ("camera_x", "camera_y", "camera_z", "target_x", "target_y", "target_z"):
            row[key] = float(row[key])
        row["index"] = int(row["index"])
        rows.append(row)

rows.sort(key=lambda r: (r["group_id"], r["index"]))
source_groups = defaultdict(list)
for row in rows:
    source_groups[row["group_id"]].append(row)

multiview_rows = []
for group_id in sorted(source_groups):
    group_rows = sorted(source_groups[group_id], key=lambda r: r["index"])
    for view_name, delta_sign in (("side_a", -1.0), ("side_b", 1.0)):
        for row in group_rows:
            target = (row["target_x"], row["target_y"], row["target_z"])
            source = (row["camera_x"], row["camera_y"], row["camera_z"])
            vec = sub(target, source)
            # Current candidate is cable-aligned with an approximately pure +/-Y offset.
            # Use the target point and mirror the signed lateral offset to synthesize the opposite side.
            lateral = norm(vec)
            if lateral <= 1e-12:
                lateral = target_distance_m
            camera = (target[0], target[1] - delta_sign * lateral, target[2])
            yaw, pitch, distance = yaw_pitch(camera, target)
            multiview_rows.append(
                {
                    "multiview_group_id": f"{group_id}_{view_name}",
                    "source_group_id": group_id,
                    "view_name": view_name,
                    "index": row["index"],
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

with open(multiview_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "multiview_group_id",
            "source_group_id",
            "view_name",
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
    writer.writerows(multiview_rows)

group_map = defaultdict(list)
for row in multiview_rows:
    group_map[row["source_group_id"]].append(row)

group_count = len(group_map)
accepted_group_count = 0
min_distance = math.inf
max_distance = 0.0
min_pitch = math.inf
max_pitch = -math.inf
for group_rows in group_map.values():
    group_view_names = {row["view_name"] for row in group_rows}
    group_ok = len(group_view_names) >= min_views_per_source_group
    for row in group_rows:
        min_distance = min(min_distance, row["target_distance_m"])
        max_distance = max(max_distance, row["target_distance_m"])
        min_pitch = min(min_pitch, row["pitch_deg"])
        max_pitch = max(max_pitch, row["pitch_deg"])
        group_ok = group_ok and row["finite_pose"] == "true" and row["target_distance_error_m"] <= max_distance_error_m
    if group_ok:
        accepted_group_count += 1

accepted = group_count >= min_source_groups and accepted_group_count >= min_source_groups
decision = "accepted_cable_multiview_surface_candidate_offline" if accepted else "rejected_cable_multiview_surface_candidate_offline"
reason = "multiview_side_a_and_side_b_candidate_generated" if accepted else "multiview_candidate_generation_failed"

print("scope=cable_multiview_surface_candidate_offline")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"pose_csv={pose_csv}")
print(f"multiview_csv={multiview_csv}")
print(f"min_source_groups={min_source_groups}")
print(f"min_views_per_source_group={min_views_per_source_group}")
print(f"target_distance_m={target_distance_m:.9f}")
print(f"max_distance_error_m={max_distance_error_m:.9f}")
print(f"group_count={group_count}")
print(f"accepted_group_count={accepted_group_count}")
print(f"pose_count={len(multiview_rows)}")
print(f"min_target_distance_m={min_distance:.9f}")
print(f"max_target_distance_m={max_distance:.9f}")
print(f"min_pitch_deg={min_pitch:.9f}")
print(f"max_pitch_deg={max_pitch:.9f}")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_multiview_surface_candidate_offline_pass={str(accepted).lower()}")
PY

echo "Cable multiview surface candidate offline audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Multiview CSV: ${MULTIVIEW_CSV}"

grep -q "decision=accepted_cable_multiview_surface_candidate_offline" "${SUMMARY_FILE}"
