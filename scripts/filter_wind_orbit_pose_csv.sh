#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_orbit_pose_filter_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_orbit_pose_filter_${STAMP}.txt"
FILTERED_CSV="${RESULT_DIR}/wind_orbit_pose_filter_${STAMP}.csv"

POSE_CSV="${POSE_CSV:-}"
TARGET_RADIUS_M="${TARGET_RADIUS_M:-15.0}"
MAX_RADIUS_ERROR_M="${MAX_RADIUS_ERROR_M:-2.0}"
MIN_Z_M="${MIN_Z_M:--25.0}"
MAX_Z_M="${MAX_Z_M:--15.0}"
MIN_VALID_SAMPLES="${MIN_VALID_SAMPLES:-100}"

if [[ -z "${POSE_CSV}" || ! -f "${POSE_CSV}" ]]; then
  echo "POSE_CSV is required and must exist." >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$POSE_CSV" "$FILTERED_CSV" "$SUMMARY_FILE" "$TARGET_RADIUS_M" "$MAX_RADIUS_ERROR_M" "$MIN_Z_M" "$MAX_Z_M" "$MIN_VALID_SAMPLES" <<'PY'
import csv
import math
import sys
from pathlib import Path

pose_csv = Path(sys.argv[1])
filtered_csv = Path(sys.argv[2])
summary_file = Path(sys.argv[3])
target_radius = float(sys.argv[4])
max_radius_error = float(sys.argv[5])
min_z = float(sys.argv[6])
max_z = float(sys.argv[7])
min_valid_samples = int(sys.argv[8])

rows = []
with pose_csv.open("r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    fieldnames = reader.fieldnames or []
    for row in reader:
        try:
            radius_error = abs(float(row.get("center_xy_radius_m", "nan")) - target_radius)
            z = float(row.get("z", "nan"))
        except ValueError:
            continue
        xy_valid = row.get("xy_valid") == "true"
        z_valid = row.get("z_valid") == "true"
        if xy_valid and z_valid and radius_error <= max_radius_error and min_z <= z <= max_z:
            rows.append(row)

with filtered_csv.open("w", newline="", encoding="utf-8") as f:
    if rows:
        fieldnames = fieldnames or list(rows[0].keys())
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for new_index, row in enumerate(rows):
        row = dict(row)
        row["sample_index"] = str(new_index)
        writer.writerow(row)

def finite_values(key):
    values = []
    for row in rows:
        try:
            value = float(row[key])
        except (KeyError, ValueError):
            continue
        if math.isfinite(value):
            values.append(value)
    return values

t_values = finite_values("t_sec")
radius_values = finite_values("center_xy_radius_m")
radius_error_values = [abs(value - target_radius) for value in radius_values]
clearance_values = finite_values("conservative_clearance_m")
z_values = finite_values("z")

accepted = len(rows) >= min_valid_samples
duration = (max(t_values) - min(t_values)) if t_values else math.nan
summary = [
    "scope=wind_orbit_pose_filter",
    f"decision={'accepted_wind_orbit_pose_filter' if accepted else 'rejected_wind_orbit_pose_filter'}",
    "starts_ros=false",
    "starts_px4=false",
    "starts_gazebo=false",
    "starts_rviz=false",
    "starts_offboard=false",
    "arms=false",
    "publishes_fmu_in=false",
    f"source_pose_csv={pose_csv}",
    f"filtered_pose_csv={filtered_csv}",
    f"target_radius_m={target_radius:.6f}",
    f"max_radius_error_m={max_radius_error:.6f}",
    f"min_z_m={min_z:.6f}",
    f"max_z_m={max_z:.6f}",
    f"min_valid_samples={min_valid_samples}",
    f"filtered_sample_count={len(rows)}",
    f"filtered_duration_sec={duration:.6f}",
    f"first_t_sec={(min(t_values) if t_values else math.nan):.6f}",
    f"last_t_sec={(max(t_values) if t_values else math.nan):.6f}",
    f"mean_radius_m={(sum(radius_values) / len(radius_values) if radius_values else math.nan):.6f}",
    f"max_filtered_radius_error_m={(max(radius_error_values) if radius_error_values else math.nan):.6f}",
    f"min_clearance_m={(min(clearance_values) if clearance_values else math.nan):.6f}",
    f"min_z_observed_m={(min(z_values) if z_values else math.nan):.6f}",
    f"max_z_observed_m={(max(z_values) if z_values else math.nan):.6f}",
    "claims_final_coverage=false",
]
summary_file.write_text("\n".join(summary) + "\n")
if not accepted:
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_orbit_pose_filter$' "${SUMMARY_FILE}"

echo "Wind orbit pose filter completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Filtered CSV: ${FILTERED_CSV}"
