#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_FOURVIEW_CSV="$(find data/results -path '*cable_fourview_surface_candidate_offline_*/*.csv' 2>/dev/null | sort | tail -n 1 || true)"
FOURVIEW_CSV="${FOURVIEW_CSV:-${DEFAULT_FOURVIEW_CSV}}"
MAX_ABS_PITCH_FOR_DIRECT_BODY_CAMERA_DEG="${MAX_ABS_PITCH_FOR_DIRECT_BODY_CAMERA_DEG:-45.0}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_fourview_attitude_feasibility_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_fourview_attitude_feasibility_${STAMP}.txt"
VIEW_CSV="${RESULT_DIR}/cable_fourview_attitude_feasibility_views_${STAMP}.csv"

if [[ -z "${FOURVIEW_CSV}" || ! -f "${FOURVIEW_CSV}" ]]; then
  echo "Required input file does not exist: ${FOURVIEW_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "${FOURVIEW_CSV}" "${VIEW_CSV}" "${MAX_ABS_PITCH_FOR_DIRECT_BODY_CAMERA_DEG}" >"${SUMMARY_FILE}" <<'PY'
import csv
import sys
from collections import defaultdict

fourview_csv, view_csv, max_abs_pitch_for_direct_body_camera_deg = sys.argv[1:4]
max_abs_pitch_for_direct_body_camera_deg = float(max_abs_pitch_for_direct_body_camera_deg)

view_stats = defaultdict(lambda: {"count": 0, "min_pitch": 999.0, "max_pitch": -999.0, "max_abs_pitch": 0.0})
with open(fourview_csv, newline="") as f:
    for row in csv.DictReader(f):
        view = row["view_name"]
        pitch = float(row["pitch_deg"])
        stats = view_stats[view]
        stats["count"] += 1
        stats["min_pitch"] = min(stats["min_pitch"], pitch)
        stats["max_pitch"] = max(stats["max_pitch"], pitch)
        stats["max_abs_pitch"] = max(stats["max_abs_pitch"], abs(pitch))

rows = []
direct_body_camera_ready = True
for view in sorted(view_stats):
    stats = view_stats[view]
    view_ready = stats["max_abs_pitch"] <= max_abs_pitch_for_direct_body_camera_deg
    direct_body_camera_ready = direct_body_camera_ready and view_ready
    rows.append(
        {
            "view_name": view,
            "sample_count": stats["count"],
            "min_pitch_deg": stats["min_pitch"],
            "max_pitch_deg": stats["max_pitch"],
            "max_abs_pitch_deg": stats["max_abs_pitch"],
            "direct_body_camera_ready": str(view_ready).lower(),
        }
    )

with open(view_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "view_name",
            "sample_count",
            "min_pitch_deg",
            "max_pitch_deg",
            "max_abs_pitch_deg",
            "direct_body_camera_ready",
        ],
    )
    writer.writeheader()
    writer.writerows(rows)

decision = "accepted_cable_fourview_attitude_feasibility" if rows else "rejected_cable_fourview_attitude_feasibility"
reason = "fourview_attitude_feasibility_characterized" if rows else "no_fourview_rows"
global_max_abs_pitch = max((row["max_abs_pitch_deg"] for row in rows), default=0.0)

print("scope=cable_fourview_attitude_feasibility")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"fourview_csv={fourview_csv}")
print(f"view_csv={view_csv}")
print(f"view_count={len(rows)}")
print(f"max_abs_pitch_for_direct_body_camera_deg={max_abs_pitch_for_direct_body_camera_deg:.9f}")
print(f"global_max_abs_pitch_deg={global_max_abs_pitch:.9f}")
print(f"direct_body_camera_ready={str(direct_body_camera_ready).lower()}")
print(f"requires_gimbal_or_attitude_review={str(not direct_body_camera_ready).lower()}")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print("claims_fourview_attitude_feasibility_pass=true")
PY

echo "Cable four-view attitude feasibility audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "View CSV: ${VIEW_CSV}"

grep -q "decision=accepted_cable_fourview_attitude_feasibility" "${SUMMARY_FILE}"
