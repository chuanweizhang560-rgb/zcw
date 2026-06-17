#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_FOV_SUMMARY="data/results/cable_surface_fov_candidate_upper_bound_20260617_092636/cable_surface_fov_candidate_upper_bound_20260617_092636.txt"
DEFAULT_FOV_GROUP_CSV="data/results/cable_surface_fov_candidate_upper_bound_20260617_092636/cable_surface_fov_candidate_upper_bound_groups_20260617_092636.csv"
FOV_SUMMARY="${FOV_SUMMARY:-${DEFAULT_FOV_SUMMARY}}"
FOV_GROUP_CSV="${FOV_GROUP_CSV:-${DEFAULT_FOV_GROUP_CSV}}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_VISIBLE_SIDE_RATIO="${MIN_VISIBLE_SIDE_RATIO:-0.95}"
MAX_TOTAL_SURFACE_RATIO="${MAX_TOTAL_SURFACE_RATIO:-0.50}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_visible_side_surface_coverage_offline_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_visible_side_surface_coverage_offline_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_visible_side_surface_coverage_offline_groups_${STAMP}.csv"

for file in "${FOV_SUMMARY}" "${FOV_GROUP_CSV}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required input file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${FOV_SUMMARY}" "${FOV_GROUP_CSV}" "${GROUP_CSV}" \
  "${MIN_GROUPS}" "${MIN_VISIBLE_SIDE_RATIO}" "${MAX_TOTAL_SURFACE_RATIO}" >"${SUMMARY_FILE}" <<'PY'
import csv
import sys

(
    fov_summary,
    fov_group_csv,
    group_csv,
    min_groups,
    min_visible_side_ratio,
    max_total_surface_ratio,
) = sys.argv[1:7]
min_groups = int(min_groups)
min_visible_side_ratio = float(min_visible_side_ratio)
max_total_surface_ratio = float(max_total_surface_ratio)


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


fov = load_kv(fov_summary)
rows = []
with open(fov_group_csv, newline="") as f:
    for row in csv.DictReader(f):
        rows.append(row)

accepted_group_count = sum(1 for row in rows if row["decision"] == "accepted_visible_side_upper_bound_group")
visible_side_ratios = [float(row["visible_side_coverage_upper_bound_ratio"]) for row in rows]
total_surface_ratios = [float(row["total_surface_coverage_upper_bound_ratio"]) for row in rows]
visible_side_ready = (
    fov.get("decision") == "accepted_cable_surface_fov_candidate_upper_bound_characterization"
    and fov.get("visible_side_upper_bound_ready") == "true"
    and float(fov.get("global_min_visible_side_coverage_upper_bound_ratio", "0")) >= min_visible_side_ratio
)
full_surface_ready = float(fov.get("global_min_total_surface_coverage_upper_bound_ratio", "0")) >= max_total_surface_ratio
accepted = len(rows) >= min_groups and accepted_group_count >= min_groups and visible_side_ready and not full_surface_ready
decision = "accepted_cable_visible_side_surface_coverage_offline" if accepted else "rejected_cable_visible_side_surface_coverage_offline"
reason = "visible_side_claim_is_supported_while_full_surface_claim_is_not" if accepted else "visible_side_or_full_surface_checks_failed"

with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "group_id",
            "decision",
            "visible_side_coverage_upper_bound_ratio",
            "total_surface_coverage_upper_bound_ratio",
        ],
    )
    writer.writeheader()
    for row in rows:
        writer.writerow(
            {
                "group_id": row["group_id"],
                "decision": "accepted_visible_side_offline_group" if row["decision"] == "accepted_visible_side_upper_bound_group" else "rejected_visible_side_offline_group",
                "visible_side_coverage_upper_bound_ratio": row["visible_side_coverage_upper_bound_ratio"],
                "total_surface_coverage_upper_bound_ratio": row["total_surface_coverage_upper_bound_ratio"],
            }
        )

print("scope=cable_visible_side_surface_coverage_offline")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"fov_summary={fov_summary}")
print(f"fov_group_csv={fov_group_csv}")
print(f"group_csv={group_csv}")
print(f"min_groups={min_groups}")
print(f"min_visible_side_ratio={min_visible_side_ratio:.9f}")
print(f"max_total_surface_ratio={max_total_surface_ratio:.9f}")
print(f"group_count={len(rows)}")
print(f"accepted_group_count={accepted_group_count}")
print(f"global_min_visible_side_ratio={min(visible_side_ratios):.9f}")
print(f"global_max_total_surface_ratio={max(total_surface_ratios):.9f}")
print(f"visible_side_ready={str(visible_side_ready).lower()}")
print(f"full_surface_ready={str(full_surface_ready).lower()}")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_visible_side_surface_coverage_offline_pass={str(accepted).lower()}")
PY

echo "Cable visible-side surface coverage offline audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_visible_side_surface_coverage_offline" "${SUMMARY_FILE}"
