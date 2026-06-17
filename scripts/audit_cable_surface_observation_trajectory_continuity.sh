#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_POSE_CSV="data/results/cable_surface_observation_pose_candidate_20260617_091638/cable_surface_observation_pose_candidate_20260617_091638.csv"
POSE_CSV="${POSE_CSV:-${DEFAULT_POSE_CSV}}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_POSES_PER_GROUP="${MIN_POSES_PER_GROUP:-25}"
MAX_STEP_M="${MAX_STEP_M:-5.1}"
MAX_YAW_STEP_DEG="${MAX_YAW_STEP_DEG:-1.0}"
MAX_PITCH_STEP_DEG="${MAX_PITCH_STEP_DEG:-1.0}"
MAX_DISTANCE_ERROR_M="${MAX_DISTANCE_ERROR_M:-0.001}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_surface_observation_trajectory_continuity_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_surface_observation_trajectory_continuity_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_surface_observation_trajectory_continuity_groups_${STAMP}.csv"

if [[ ! -f "${POSE_CSV}" ]]; then
  echo "Required input file does not exist: ${POSE_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "${POSE_CSV}" "${GROUP_CSV}" "${MIN_GROUPS}" "${MIN_POSES_PER_GROUP}" \
  "${MAX_STEP_M}" "${MAX_YAW_STEP_DEG}" "${MAX_PITCH_STEP_DEG}" "${MAX_DISTANCE_ERROR_M}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

(
    pose_csv,
    group_csv,
    min_groups,
    min_poses_per_group,
    max_step_m,
    max_yaw_step_deg,
    max_pitch_step_deg,
    max_distance_error_m,
) = sys.argv[1:9]
min_groups = int(min_groups)
min_poses_per_group = int(min_poses_per_group)
max_step_m = float(max_step_m)
max_yaw_step_deg = float(max_yaw_step_deg)
max_pitch_step_deg = float(max_pitch_step_deg)
max_distance_error_m = float(max_distance_error_m)


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def angle_delta_deg(a, b):
    delta = (a - b + 180.0) % 360.0 - 180.0
    return abs(delta)


groups = defaultdict(list)
with open(pose_csv, newline="") as f:
    for row in csv.DictReader(f):
        row["index"] = int(row["index"])
        for key in (
            "camera_x",
            "camera_y",
            "camera_z",
            "target_distance_error_m",
            "yaw_deg",
            "pitch_deg",
        ):
            row[key] = float(row[key])
        groups[row["group_id"]].append(row)

for rows in groups.values():
    rows.sort(key=lambda r: r["index"])

summaries = []
accepted_count = 0
for group_id in sorted(groups):
    rows = groups[group_id]
    steps = []
    yaw_steps = []
    pitch_steps = []
    monotonic = True
    for prev, cur in zip(rows, rows[1:]):
        steps.append(
            dist(
                (prev["camera_x"], prev["camera_y"], prev["camera_z"]),
                (cur["camera_x"], cur["camera_y"], cur["camera_z"]),
            )
        )
        yaw_steps.append(angle_delta_deg(cur["yaw_deg"], prev["yaw_deg"]))
        pitch_steps.append(angle_delta_deg(cur["pitch_deg"], prev["pitch_deg"]))
        monotonic = monotonic and cur["index"] > prev["index"]

    max_step = max(steps) if steps else 0.0
    min_step = min(steps) if steps else 0.0
    max_yaw_step = max(yaw_steps) if yaw_steps else 0.0
    max_pitch_step = max(pitch_steps) if pitch_steps else 0.0
    max_distance_error = max(abs(row["target_distance_error_m"]) for row in rows)
    finite = all(row["finite_pose"] == "true" for row in rows)
    accepted = (
        len(rows) >= min_poses_per_group
        and monotonic
        and finite
        and max_step <= max_step_m
        and max_yaw_step <= max_yaw_step_deg
        and max_pitch_step <= max_pitch_step_deg
        and max_distance_error <= max_distance_error_m
    )
    if accepted:
        accepted_count += 1
    summaries.append(
        {
            "group_id": group_id,
            "decision": "accepted_observation_trajectory_group" if accepted else "rejected_observation_trajectory_group",
            "pose_count": len(rows),
            "monotonic_index": str(monotonic).lower(),
            "finite_pose": str(finite).lower(),
            "min_step_m": min_step,
            "max_step_m": max_step,
            "max_yaw_step_deg": max_yaw_step,
            "max_pitch_step_deg": max_pitch_step,
            "max_target_distance_error_m": max_distance_error,
        }
    )

with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "group_id",
            "decision",
            "pose_count",
            "monotonic_index",
            "finite_pose",
            "min_step_m",
            "max_step_m",
            "max_yaw_step_deg",
            "max_pitch_step_deg",
            "max_target_distance_error_m",
        ],
    )
    writer.writeheader()
    writer.writerows(summaries)

global_max_step = max((row["max_step_m"] for row in summaries), default=0.0)
global_max_yaw_step = max((row["max_yaw_step_deg"] for row in summaries), default=0.0)
global_max_pitch_step = max((row["max_pitch_step_deg"] for row in summaries), default=0.0)
global_max_distance_error = max((row["max_target_distance_error_m"] for row in summaries), default=0.0)
accepted = len(summaries) >= min_groups and accepted_count >= min_groups
decision = "accepted_cable_surface_observation_trajectory_continuity" if accepted else "rejected_cable_surface_observation_trajectory_continuity"
reason = "all_groups_have_continuous_surface_observation_pose_candidates" if accepted else "one_or_more_groups_failed_continuity_checks"

print("scope=cable_surface_observation_trajectory_continuity")
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
print(f"group_csv={group_csv}")
print(f"min_groups={min_groups}")
print(f"min_poses_per_group={min_poses_per_group}")
print(f"max_step_m_threshold={max_step_m:.9f}")
print(f"max_yaw_step_deg_threshold={max_yaw_step_deg:.9f}")
print(f"max_pitch_step_deg_threshold={max_pitch_step_deg:.9f}")
print(f"max_distance_error_m_threshold={max_distance_error_m:.9f}")
print(f"group_count={len(summaries)}")
print(f"accepted_group_count={accepted_count}")
print(f"global_max_step_m={global_max_step:.9f}")
print(f"global_max_yaw_step_deg={global_max_yaw_step:.9f}")
print(f"global_max_pitch_step_deg={global_max_pitch_step:.9f}")
print(f"global_max_target_distance_error_m={global_max_distance_error:.9f}")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_surface_observation_trajectory_continuity_pass={str(accepted).lower()}")
PY

echo "Cable surface observation trajectory continuity audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_surface_observation_trajectory_continuity" "${SUMMARY_FILE}"
