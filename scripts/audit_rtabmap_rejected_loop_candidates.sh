#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_rejected_loop_candidates_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_rejected_loop_candidates_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/rtabmap_rejected_loop_candidates_${STAMP}.csv"

RTABMAP_LOG="${RTABMAP_LOG:-}"
if [[ -z "${RTABMAP_LOG}" ]]; then
  RTABMAP_LOG="$(find "${ROOT_DIR}/data/logs" -name 'rtabmap_depth_camera_rgbd_wind_rviz_rtabmap_*.log' | sort | tail -n 1)"
fi

if [[ -z "${RTABMAP_LOG}" || ! -f "${RTABMAP_LOG}" ]]; then
  echo "RTAB-Map log not found: ${RTABMAP_LOG}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$RTABMAP_LOG" "$CSV_FILE" "$SUMMARY_FILE" <<'PY'
import csv
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
csv_path = Path(sys.argv[2])
summary_path = Path(sys.argv[3])

pattern = re.compile(
    r"Rejected loop closure\s+(\d+)\s+->\s+(\d+):\s+Not enough inliers\s+(\d+)/(\d+)\s+\(matches=(\d+)\)"
)

rows = []
for line_no, line in enumerate(log_path.read_text(errors="replace").splitlines(), start=1):
    match = pattern.search(line)
    if not match:
        continue
    from_id, to_id, inliers, required, matches = map(int, match.groups())
    rows.append(
        {
            "line": line_no,
            "from_id": from_id,
            "to_id": to_id,
            "inliers": inliers,
            "required_inliers": required,
            "matches": matches,
            "inlier_ratio": (inliers / matches) if matches else 0.0,
        }
    )

with csv_path.open("w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "line",
            "from_id",
            "to_id",
            "inliers",
            "required_inliers",
            "matches",
            "inlier_ratio",
        ],
    )
    writer.writeheader()
    writer.writerows(rows)

best_by_inliers = max(rows, key=lambda row: (row["inliers"], row["matches"]), default=None)
best_by_matches = max(rows, key=lambda row: (row["matches"], row["inliers"]), default=None)
near_pass_count = sum(1 for row in rows if row["required_inliers"] - row["inliers"] <= 5)
matched_candidate_count = sum(1 for row in rows if row["matches"] > 0)

def row_field(row, key, default="none"):
    return default if row is None else str(row[key])

summary = [
    "scope=rtabmap_rejected_loop_candidates",
    "decision=accepted_rtabmap_rejected_loop_candidates_audit",
    "starts_ros=false",
    "starts_px4=false",
    "starts_gazebo=false",
    "starts_rviz=false",
    "starts_offboard=false",
    "arms=false",
    "publishes_fmu_in=false",
    f"rtabmap_log={log_path}",
    f"csv_file={csv_path}",
    f"rejected_loop_candidate_count={len(rows)}",
    f"matched_candidate_count={matched_candidate_count}",
    f"near_pass_count={near_pass_count}",
    f"best_inliers={row_field(best_by_inliers, 'inliers', '0')}",
    f"best_required_inliers={row_field(best_by_inliers, 'required_inliers', '0')}",
    f"best_inliers_from_id={row_field(best_by_inliers, 'from_id')}",
    f"best_inliers_to_id={row_field(best_by_inliers, 'to_id')}",
    f"best_inliers_matches={row_field(best_by_inliers, 'matches', '0')}",
    f"best_matches={row_field(best_by_matches, 'matches', '0')}",
    f"best_matches_from_id={row_field(best_by_matches, 'from_id')}",
    f"best_matches_to_id={row_field(best_by_matches, 'to_id')}",
    f"best_matches_inliers={row_field(best_by_matches, 'inliers', '0')}",
]
summary_path.write_text("\n".join(summary) + "\n")
PY

echo "RTAB-Map rejected loop-candidate audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"
