#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_pose_from_px4_local_position_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_pose_from_px4_local_position_${STAMP}.txt"
POSE_CSV="${RESULT_DIR}/wind_pose_from_px4_local_position_${STAMP}.csv"

SOURCE_SUMMARY="${SOURCE_SUMMARY:-}"
PX4_LOCAL_POSITION_LOG="${PX4_LOCAL_POSITION_LOG:-}"
CENTER_X="${CENTER_X:--25.0}"
CENTER_Y="${CENTER_Y:--25.0}"
CONSERVATIVE_MESH_RADIUS_M="${CONSERVATIVE_MESH_RADIUS_M:-11.880407}"

value_for() {
  local key="$1"
  local file="$2"
  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${file}"
}

if [[ -n "${SOURCE_SUMMARY}" && -f "${SOURCE_SUMMARY}" && -z "${PX4_LOCAL_POSITION_LOG}" ]]; then
  PX4_LOCAL_POSITION_LOG="$(value_for local_position_trajectory_log "${SOURCE_SUMMARY}")"
fi

if [[ -z "${PX4_LOCAL_POSITION_LOG}" || ! -f "${PX4_LOCAL_POSITION_LOG}" ]]; then
  echo "PX4 local-position trajectory log not found. Set PX4_LOCAL_POSITION_LOG or SOURCE_SUMMARY." >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$PX4_LOCAL_POSITION_LOG" "$POSE_CSV" "$SUMMARY_FILE" "$CENTER_X" "$CENTER_Y" "$CONSERVATIVE_MESH_RADIUS_M" "$SOURCE_SUMMARY" <<'PY'
import csv
import math
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
pose_csv = Path(sys.argv[2])
summary_file = Path(sys.argv[3])
center_x = float(sys.argv[4])
center_y = float(sys.argv[5])
mesh_radius = float(sys.argv[6])
source_summary = sys.argv[7]

text = log_path.read_text(errors="replace")
blocks = re.split(r"\n---\s*\n", text)
samples = []
for block in blocks:
    ts_m = re.search(r"^timestamp:\s*([0-9]+)", block, flags=re.MULTILINE)
    x_m = re.search(r"^x:\s*([-+0-9.eE]+)", block, flags=re.MULTILINE)
    y_m = re.search(r"^y:\s*([-+0-9.eE]+)", block, flags=re.MULTILINE)
    z_m = re.search(r"^z:\s*([-+0-9.eE]+)", block, flags=re.MULTILINE)
    xy_valid = bool(re.search(r"^xy_valid:\s*true", block, flags=re.MULTILINE))
    z_valid = bool(re.search(r"^z_valid:\s*true", block, flags=re.MULTILINE))
    if not ts_m or not x_m or not y_m or not z_m:
        continue
    timestamp_us = int(ts_m.group(1))
    x = float(x_m.group(1))
    y = float(y_m.group(1))
    z = float(z_m.group(1))
    if all(math.isfinite(value) for value in (x, y, z)):
        samples.append((timestamp_us, x, y, z, xy_valid, z_valid))

samples.sort(key=lambda item: item[0])
dedup = []
for sample in samples:
    if dedup and dedup[-1][0] == sample[0]:
        dedup[-1] = sample
    else:
        dedup.append(sample)

if not dedup:
    raise SystemExit("no PX4 local-position samples parsed")

t0 = dedup[0][0]
valid_count = 0
min_clearance = math.inf
max_radius_error = 0.0
radius_sum = 0.0

with pose_csv.open("w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow([
        "sample_index",
        "t_sec",
        "x",
        "y",
        "z",
        "xy_valid",
        "z_valid",
        "center_xy_radius_m",
        "radius_error_m",
        "conservative_clearance_m",
    ])
    for index, (timestamp_us, x, y, z, xy_valid, z_valid) in enumerate(dedup):
        t_sec = (timestamp_us - t0) * 1e-6
        radius = math.hypot(x - center_x, y - center_y)
        radius_error = abs(radius - 15.0)
        clearance = radius - mesh_radius
        if xy_valid and z_valid:
            valid_count += 1
            radius_sum += radius
            min_clearance = min(min_clearance, clearance)
            max_radius_error = max(max_radius_error, radius_error)
        writer.writerow([
            index,
            f"{t_sec:.6f}",
            f"{x:.6f}",
            f"{y:.6f}",
            f"{z:.6f}",
            "true" if xy_valid else "false",
            "true" if z_valid else "false",
            f"{radius:.6f}",
            f"{radius_error:.6f}",
            f"{clearance:.6f}",
        ])

mean_radius = radius_sum / valid_count if valid_count else math.nan
duration = (dedup[-1][0] - dedup[0][0]) * 1e-6

summary = [
    "scope=wind_pose_from_px4_local_position",
    "decision=accepted_wind_pose_from_px4_local_position",
    "starts_ros=false",
    "starts_px4=false",
    "starts_gazebo=false",
    "starts_rviz=false",
    "starts_offboard=false",
    "arms=false",
    "publishes_fmu_in=false",
    f"source_summary={source_summary}",
    f"px4_local_position_log={log_path}",
    f"pose_csv={pose_csv}",
    f"sample_count={len(dedup)}",
    f"valid_pose_samples={valid_count}",
    f"duration_sec={duration:.6f}",
    f"center_x={center_x:.6f}",
    f"center_y={center_y:.6f}",
    f"conservative_mesh_radius_m={mesh_radius:.6f}",
    f"mean_center_xy_radius_m={mean_radius:.6f}",
    f"max_radius_error_m={max_radius_error:.6f}",
    f"min_conservative_clearance_m={min_clearance:.6f}",
    "claims_final_coverage=false",
]
summary_file.write_text("\n".join(summary) + "\n")
PY

echo "PX4 local-position wind pose CSV conversion completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Pose CSV: ${POSE_CSV}"
