#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_FOURVIEW_CSV="$(find data/results -path '*cable_fourview_surface_candidate_offline_*/*.csv' 2>/dev/null | sort | tail -n 1 || true)"
DEFAULT_FOURVIEW_UNION_SUMMARY="data/results/cable_fourview_surface_union_offline_20260618_131943/cable_fourview_surface_union_offline_20260618_131943.txt"
DEFAULT_FOURVIEW_OCCLUSION_SUMMARY="data/results/cable_fourview_surface_occlusion_offline_20260618_132716/cable_fourview_surface_occlusion_offline_20260618_132716.txt"
FOURVIEW_CSV="${FOURVIEW_CSV:-${DEFAULT_FOURVIEW_CSV}}"
FOURVIEW_UNION_SUMMARY="${FOURVIEW_UNION_SUMMARY:-${DEFAULT_FOURVIEW_UNION_SUMMARY}}"
FOURVIEW_OCCLUSION_SUMMARY="${FOURVIEW_OCCLUSION_SUMMARY:-${DEFAULT_FOURVIEW_OCCLUSION_SUMMARY}}"
MAX_ABS_PITCH_BODY_FIXED_DEG="${MAX_ABS_PITCH_BODY_FIXED_DEG:-45.0}"
MIN_FULL_SURFACE_RATIO="${MIN_FULL_SURFACE_RATIO:-0.95}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_fourview_mount_strategy_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_fourview_mount_strategy_${STAMP}.txt"
VIEW_CSV="${RESULT_DIR}/cable_fourview_mount_strategy_views_${STAMP}.csv"

for file in "${FOURVIEW_CSV}" "${FOURVIEW_UNION_SUMMARY}" "${FOURVIEW_OCCLUSION_SUMMARY}"; do
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "Required input file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${FOURVIEW_CSV}" "${FOURVIEW_UNION_SUMMARY}" "${FOURVIEW_OCCLUSION_SUMMARY}" \
  "${VIEW_CSV}" "${MAX_ABS_PITCH_BODY_FIXED_DEG}" "${MIN_FULL_SURFACE_RATIO}" >"${SUMMARY_FILE}" <<'PY'
import csv
import sys
from collections import defaultdict

(
    fourview_csv,
    fourview_union_summary,
    fourview_occlusion_summary,
    view_csv,
    max_abs_pitch_body_fixed_deg,
    min_full_surface_ratio,
) = sys.argv[1:7]
max_abs_pitch_body_fixed_deg = float(max_abs_pitch_body_fixed_deg)
min_full_surface_ratio = float(min_full_surface_ratio)


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


view_stats = defaultdict(
    lambda: {
        "sample_count": 0,
        "source_groups": set(),
        "min_pitch": 999.0,
        "max_pitch": -999.0,
        "max_abs_pitch": 0.0,
        "finite_count": 0,
    }
)

with open(fourview_csv, newline="") as f:
    for row in csv.DictReader(f):
        view = row["view_name"]
        pitch = float(row["pitch_deg"])
        finite = row.get("finite_pose", "true").lower() == "true"
        stats = view_stats[view]
        stats["sample_count"] += 1
        stats["source_groups"].add(row["source_group_id"])
        stats["min_pitch"] = min(stats["min_pitch"], pitch)
        stats["max_pitch"] = max(stats["max_pitch"], pitch)
        stats["max_abs_pitch"] = max(stats["max_abs_pitch"], abs(pitch))
        if finite:
            stats["finite_count"] += 1

rows = []
body_fixed_ready_count = 0
gimbal_required_count = 0
for view in sorted(view_stats):
    stats = view_stats[view]
    finite_ready = stats["finite_count"] == stats["sample_count"]
    body_fixed_ready = finite_ready and stats["max_abs_pitch"] <= max_abs_pitch_body_fixed_deg
    requires_pitch_gimbal = finite_ready and not body_fixed_ready
    if body_fixed_ready:
        strategy = "body_fixed_candidate"
        body_fixed_ready_count += 1
    elif requires_pitch_gimbal:
        strategy = "requires_pitch_gimbal_or_camera_mount_review"
        gimbal_required_count += 1
    else:
        strategy = "rejected_nonfinite_pose"
    rows.append(
        {
            "view_name": view,
            "sample_count": stats["sample_count"],
            "source_group_count": len(stats["source_groups"]),
            "min_pitch_deg": f"{stats['min_pitch']:.9f}",
            "max_pitch_deg": f"{stats['max_pitch']:.9f}",
            "max_abs_pitch_deg": f"{stats['max_abs_pitch']:.9f}",
            "finite_ready": str(finite_ready).lower(),
            "body_fixed_ready": str(body_fixed_ready).lower(),
            "requires_pitch_gimbal_or_mount_review": str(requires_pitch_gimbal).lower(),
            "strategy": strategy,
        }
    )

with open(view_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "view_name",
            "sample_count",
            "source_group_count",
            "min_pitch_deg",
            "max_pitch_deg",
            "max_abs_pitch_deg",
            "finite_ready",
            "body_fixed_ready",
            "requires_pitch_gimbal_or_mount_review",
            "strategy",
        ],
    )
    writer.writeheader()
    writer.writerows(rows)

union = load_kv(fourview_union_summary)
occlusion = load_kv(fourview_occlusion_summary)
full_surface_ratio = float(union.get("global_min_total_surface_coverage_upper_bound_ratio", "0"))
occlusion_ratio = float(occlusion.get("global_min_occlusion_clear_total_surface_ratio", "0"))
fourview_geometry_ready = (
    union.get("decision") == "accepted_cable_fourview_surface_union_offline"
    and occlusion.get("decision") == "accepted_cable_fourview_surface_occlusion_offline"
    and full_surface_ratio >= min_full_surface_ratio
    and occlusion_ratio >= min_full_surface_ratio
)
body_fixed_only_full_surface_ready = body_fixed_ready_count == len(rows) and fourview_geometry_ready
full_surface_requires_mount_review = fourview_geometry_ready and not body_fixed_only_full_surface_ready
accepted = bool(rows) and fourview_geometry_ready and full_surface_requires_mount_review
decision = "accepted_cable_fourview_mount_strategy" if accepted else "rejected_cable_fourview_mount_strategy"
reason = "full_surface_geometry_ready_but_mount_strategy_requires_review" if accepted else "mount_strategy_inputs_not_ready"

print("scope=cable_fourview_mount_strategy")
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
print(f"fourview_union_summary={fourview_union_summary}")
print(f"fourview_occlusion_summary={fourview_occlusion_summary}")
print(f"view_csv={view_csv}")
print(f"view_count={len(rows)}")
print(f"body_fixed_ready_view_count={body_fixed_ready_count}")
print(f"gimbal_or_mount_review_view_count={gimbal_required_count}")
print(f"max_abs_pitch_body_fixed_deg={max_abs_pitch_body_fixed_deg:.9f}")
print(f"full_surface_ratio={full_surface_ratio:.9f}")
print(f"occlusion_clear_ratio={occlusion_ratio:.9f}")
print(f"fourview_geometry_ready={str(fourview_geometry_ready).lower()}")
print(f"body_fixed_only_full_surface_ready={str(body_fixed_only_full_surface_ready).lower()}")
print(f"full_surface_requires_mount_review={str(full_surface_requires_mount_review).lower()}")
print("recommended_active_track=body_fixed_side_views_only_until_mount_review")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_fourview_mount_strategy_pass={str(accepted).lower()}")
PY

echo "Cable four-view mount strategy audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "View CSV: ${VIEW_CSV}"

grep -q "decision=accepted_cable_fourview_mount_strategy" "${SUMMARY_FILE}"
