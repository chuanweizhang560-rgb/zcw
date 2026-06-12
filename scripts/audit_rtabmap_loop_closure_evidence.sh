#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_loop_closure_evidence_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_loop_closure_evidence_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/rtabmap_loop_closure_evidence_${STAMP}.csv"
INFO_LOG="${RESULT_DIR}/rtabmap_loop_closure_info_${STAMP}.log"

DB_PATH="${DB_PATH:-}"
if [[ -z "${DB_PATH}" ]]; then
  DB_PATH="$(find "${ROOT_DIR}/data/results" -path '*rtabmap_depth_camera_rgbd_wind_rviz_overlay_*/*.db' | sort | tail -n 1)"
fi

if [[ -z "${DB_PATH}" || ! -f "${DB_PATH}" ]]; then
  echo "RTAB-Map database not found: ${DB_PATH}" >&2
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found" >&2
  exit 1
fi
if ! command -v rtabmap-info >/dev/null 2>&1; then
  echo "rtabmap-info not found" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

rtabmap-info "${DB_PATH}" >"${INFO_LOG}" 2>&1

python3 - "$DB_PATH" "$INFO_LOG" "$CSV_FILE" "$SUMMARY_FILE" <<'PY'
import csv
import math
import re
import sqlite3
import struct
import sys
from pathlib import Path

db_path = Path(sys.argv[1])
info_log = Path(sys.argv[2])
csv_file = Path(sys.argv[3])
summary_file = Path(sys.argv[4])

con = sqlite3.connect(str(db_path))
node_rows = con.execute(
    "select id, stamp, pose from Node where pose is not null and length(pose)=48 order by stamp"
).fetchall()
link_rows = con.execute(
    "select from_id, to_id, type, length(transform), length(information_matrix) from Link order by type, from_id, to_id"
).fetchall()
con.close()

poses = {}
for node_id, stamp, blob in node_rows:
    values = struct.unpack("<12f", blob)
    poses[int(node_id)] = (float(stamp), (float(values[3]), float(values[7]), float(values[11])))

counts = {i: 0 for i in range(9)}
for _, _, link_type, _, _ in link_rows:
    counts[int(link_type)] = counts.get(int(link_type), 0) + 1

def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))

first_last_distance = math.nan
path_length = 0.0
if len(node_rows) >= 2:
    first_id = int(node_rows[0][0])
    last_id = int(node_rows[-1][0])
    first_last_distance = dist(poses[first_id][1], poses[last_id][1])
    ordered_ids = [int(row[0]) for row in node_rows]
    for a, b in zip(ordered_ids[:-1], ordered_ids[1:]):
        path_length += dist(poses[a][1], poses[b][1])

with csv_file.open("w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(
        [
            "from_id",
            "to_id",
            "type",
            "type_name",
            "from_stamp",
            "to_stamp",
            "node_distance_m",
            "transform_len",
            "information_matrix_len",
        ]
    )
    names = {
        0: "Neighbor",
        1: "GlobalClosure",
        2: "LocalSpaceClosure",
        3: "LocalTimeClosure",
        4: "UserClosure",
        5: "VirtualClosure",
        6: "NeighborMerged",
        7: "PosePrior",
        8: "Landmark",
    }
    for from_id, to_id, link_type, transform_len, information_len in link_rows:
        from_id = int(from_id)
        to_id = int(to_id)
        link_type = int(link_type)
        if from_id in poses and to_id in poses:
            from_stamp = poses[from_id][0]
            to_stamp = poses[to_id][0]
            node_distance = dist(poses[from_id][1], poses[to_id][1])
        else:
            from_stamp = math.nan
            to_stamp = math.nan
            node_distance = math.nan
        writer.writerow(
            [
                from_id,
                to_id,
                link_type,
                names.get(link_type, "Unknown"),
                f"{from_stamp:.9f}",
                f"{to_stamp:.9f}",
                f"{node_distance:.9f}",
                transform_len,
                information_len,
            ]
        )

info_text = info_log.read_text(errors="replace")
def info_count(label):
    match = re.search(rf"^\s*{re.escape(label)}:\s*([0-9]+)", info_text, flags=re.MULTILINE)
    return int(match.group(1)) if match else -1

raw_global = counts.get(1, 0)
raw_local_space = counts.get(2, 0)
raw_local_time = counts.get(3, 0)
official_global = info_count("GlobalClosure")
official_local_space = info_count("LocalSpaceClosure")
official_local_time = info_count("LocalTimeClosure")

has_raw_loop_candidate = raw_global + raw_local_space + raw_local_time > 0
official_loop_count = max(official_global, 0) + max(official_local_space, 0) + max(official_local_time, 0)
has_official_loop = official_loop_count > 0
has_mismatch = has_raw_loop_candidate and not has_official_loop

decision = "accepted_rtabmap_loop_closure_evidence_audit"
reason = "raw_loop_candidate_present_but_official_info_does_not_confirm_loop_closure" if has_mismatch else (
    "official_loop_closure_present" if has_official_loop else "no_loop_closure_evidence_present"
)

def metric(value):
    return "nan" if not math.isfinite(value) else f"{value:.9f}"

summary_lines = [
    "scope=rtabmap_loop_closure_evidence",
    f"decision={decision}",
    f"reason={reason}",
    "starts_ros=false",
    "starts_px4=false",
    "starts_gazebo=false",
    "starts_rviz=false",
    "starts_offboard=false",
    "arms=false",
    "publishes_fmu_in=false",
    "uses_rtabmap_db=true",
    "uses_rtabmap_info=true",
    "claims_loop_closure_pass=false",
    f"db_path={db_path}",
    f"csv_file={csv_file}",
    f"info_log={info_log}",
    f"node_count={len(node_rows)}",
    f"link_count={len(link_rows)}",
    f"raw_neighbor_links={counts.get(0, 0)}",
    f"raw_global_closure_links={raw_global}",
    f"raw_local_space_closure_links={raw_local_space}",
    f"raw_local_time_closure_links={raw_local_time}",
    f"official_global_closure_links={official_global}",
    f"official_local_space_closure_links={official_local_space}",
    f"official_local_time_closure_links={official_local_time}",
    f"has_raw_loop_candidate={'true' if has_raw_loop_candidate else 'false'}",
    f"has_official_loop_closure={'true' if has_official_loop else 'false'}",
    f"raw_official_mismatch={'true' if has_mismatch else 'false'}",
    f"path_length_proxy_m={metric(path_length)}",
    f"first_last_distance_m={metric(first_last_distance)}",
]
summary_file.write_text("\n".join(summary_lines) + "\n")
PY

echo "RTAB-Map loop closure evidence audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"
