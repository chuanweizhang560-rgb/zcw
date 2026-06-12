#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
SCENARIO="${SCENARIO:-rtabmap_px4_local_position_crosscheck}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/${SCENARIO}_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/${SCENARIO}_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/${SCENARIO}_${STAMP}.csv"

SOURCE_SUMMARY="${SOURCE_SUMMARY:-}"
DB_PATH="${DB_PATH:-}"
PX4_LOCAL_POSITION_LOG="${PX4_LOCAL_POSITION_LOG:-}"

value_for() {
  local key="$1"
  local file="$2"
  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${file}"
}

if [[ -n "${SOURCE_SUMMARY}" && -f "${SOURCE_SUMMARY}" ]]; then
  if [[ -z "${DB_PATH}" ]]; then
    DB_PATH="$(find "$(dirname "${SOURCE_SUMMARY}")" -maxdepth 1 -type f -name '*.db' | sort | tail -n 1)"
  fi
  if [[ -z "${PX4_LOCAL_POSITION_LOG}" ]]; then
    PX4_LOCAL_POSITION_LOG="$(value_for local_position_trajectory_log "${SOURCE_SUMMARY}")"
  fi
fi

if [[ -z "${DB_PATH}" || ! -f "${DB_PATH}" ]]; then
  echo "RTAB-Map database not found. Set DB_PATH or SOURCE_SUMMARY." >&2
  exit 1
fi
if [[ -z "${PX4_LOCAL_POSITION_LOG}" || ! -f "${PX4_LOCAL_POSITION_LOG}" ]]; then
  echo "PX4 local-position trajectory log not found. Set PX4_LOCAL_POSITION_LOG or SOURCE_SUMMARY." >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$DB_PATH" "$PX4_LOCAL_POSITION_LOG" "$CSV_FILE" "$SUMMARY_FILE" "${SOURCE_SUMMARY:-}" "${SCENARIO}" <<'PY'
import csv
import math
import re
import sqlite3
import struct
import sys
from pathlib import Path

import numpy as np

db_path = Path(sys.argv[1])
px4_log = Path(sys.argv[2])
csv_file = Path(sys.argv[3])
summary_file = Path(sys.argv[4])
source_summary = sys.argv[5]
scenario = sys.argv[6]


def load_rtabmap_poses(path):
    con = sqlite3.connect(str(path))
    rows = con.execute(
        "select id, stamp, pose from Node where pose is not null and length(pose)=48 order by stamp"
    ).fetchall()
    con.close()
    poses = []
    for node_id, stamp, blob in rows:
        values = struct.unpack("<12f", blob)
        xyz = np.array([values[3], values[7], values[11]], dtype=float)
        if np.all(np.isfinite(xyz)):
            poses.append((int(node_id), float(stamp), xyz))
    if not poses:
        return []
    t0 = poses[0][1]
    return [(node_id, stamp - t0, xyz) for node_id, stamp, xyz in poses]


def parse_px4_local_position(path):
    text = path.read_text(errors="replace")
    blocks = re.split(r"\n---\s*\n", text)
    samples = []
    for block in blocks:
        ts_m = re.search(r"^timestamp:\s*([0-9]+)", block, flags=re.MULTILINE)
        x_m = re.search(r"^x:\s*([-+0-9.eE]+)", block, flags=re.MULTILINE)
        y_m = re.search(r"^y:\s*([-+0-9.eE]+)", block, flags=re.MULTILINE)
        z_m = re.search(r"^z:\s*([-+0-9.eE]+)", block, flags=re.MULTILINE)
        valid = all(re.search(rf"^{key}:\s*true", block, flags=re.MULTILINE) for key in ("xy_valid", "z_valid"))
        if not ts_m or not x_m or not y_m or not z_m or not valid:
            continue
        stamp = float(ts_m.group(1)) * 1e-6
        # PX4 local_position is NED. Keep the raw axis convention and use a rigid SE(3)
        # alignment below, so the audit is a cross-check rather than a frame claim.
        xyz = np.array([float(x_m.group(1)), float(y_m.group(1)), float(z_m.group(1))], dtype=float)
        if np.all(np.isfinite(xyz)):
            samples.append((stamp, xyz))
    samples.sort(key=lambda item: item[0])
    dedup = []
    for stamp, xyz in samples:
        if dedup and abs(dedup[-1][0] - stamp) < 1e-9:
            dedup[-1] = (stamp, xyz)
        else:
            dedup.append((stamp, xyz))
    if not dedup:
        return []
    t0 = dedup[0][0]
    return [(stamp - t0, xyz) for stamp, xyz in dedup]


def interpolate(samples, stamp):
    if not samples or stamp < samples[0][0] or stamp > samples[-1][0]:
        return None
    lo = 0
    hi = len(samples) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        mid_stamp = samples[mid][0]
        if mid_stamp < stamp:
            lo = mid + 1
        elif mid_stamp > stamp:
            hi = mid - 1
        else:
            return samples[mid][1]
    right = lo
    left = lo - 1
    if left < 0 or right >= len(samples):
        return None
    t0, p0 = samples[left]
    t1, p1 = samples[right]
    if t1 <= t0:
        return p0
    alpha = (stamp - t0) / (t1 - t0)
    return p0 * (1.0 - alpha) + p1 * alpha


def rigid_align(source_points, target_points):
    src = np.asarray(source_points, dtype=float)
    tgt = np.asarray(target_points, dtype=float)
    src_mean = src.mean(axis=0)
    tgt_mean = tgt.mean(axis=0)
    src_centered = src - src_mean
    tgt_centered = tgt - tgt_mean
    covariance = src_centered.T @ tgt_centered
    u, _, vt = np.linalg.svd(covariance)
    rotation = vt.T @ u.T
    if np.linalg.det(rotation) < 0:
        vt[-1, :] *= -1
        rotation = vt.T @ u.T
    translation = tgt_mean - rotation @ src_mean
    aligned = (rotation @ src.T).T + translation
    return aligned, rotation, translation


rtabmap_poses = load_rtabmap_poses(db_path)
px4_samples = parse_px4_local_position(px4_log)
pairs = []
for node_id, stamp, rtab_xyz in rtabmap_poses:
    px4_xyz = interpolate(px4_samples, stamp)
    if px4_xyz is not None:
        pairs.append((node_id, stamp, rtab_xyz, px4_xyz))

if len(pairs) >= 3:
    rtab_points = np.vstack([item[2] for item in pairs])
    px4_points = np.vstack([item[3] for item in pairs])
    aligned_points, rotation, translation = rigid_align(rtab_points, px4_points)
    errors = np.linalg.norm(aligned_points - px4_points, axis=1)
else:
    aligned_points = np.zeros((0, 3), dtype=float)
    rotation = np.eye(3, dtype=float)
    translation = np.zeros(3, dtype=float)
    errors = np.array([], dtype=float)

with csv_file.open("w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["node_id", "elapsed_s", "rtab_x", "rtab_y", "rtab_z", "px4_x", "px4_y", "px4_z", "aligned_x", "aligned_y", "aligned_z", "error_m"])
    for index, (node_id, stamp, rtab_xyz, px4_xyz) in enumerate(pairs):
        aligned_xyz = aligned_points[index] if len(aligned_points) else np.array([math.nan] * 3)
        error = errors[index] if len(errors) else math.nan
        writer.writerow([node_id, f"{stamp:.9f}", f"{rtab_xyz[0]:.9f}", f"{rtab_xyz[1]:.9f}", f"{rtab_xyz[2]:.9f}", f"{px4_xyz[0]:.9f}", f"{px4_xyz[1]:.9f}", f"{px4_xyz[2]:.9f}", f"{aligned_xyz[0]:.9f}", f"{aligned_xyz[1]:.9f}", f"{aligned_xyz[2]:.9f}", f"{error:.9f}"])

computed = len(errors) >= 3 and np.all(np.isfinite(errors))
decision = f"accepted_{scenario}" if computed else f"rejected_{scenario}"
reason = "rigid_aligned_elapsed_time_crosscheck_against_px4_local_position" if computed else "insufficient_time_overlap_for_px4_crosscheck"

def metric(value):
    return "nan" if value is None or not np.isfinite(value) else f"{value:.9f}"

rmse = math.sqrt(float(np.mean(errors ** 2))) if computed else math.nan
mean_error = float(np.mean(errors)) if computed else math.nan
median_error = float(np.median(errors)) if computed else math.nan
max_error = float(np.max(errors)) if computed else math.nan
p95_error = float(np.percentile(errors, 95)) if computed else math.nan

lines = [
    f"scope={scenario}",
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
    "uses_px4_local_position_reference=true",
    "alignment=rigid_se3_svd",
    "time_alignment=elapsed_time_from_first_sample",
    "claims_slam_pass=false",
    "claims_ground_truth_accuracy=false",
    "source_boundary=px4_local_position_is_estimator_output_not_independent_ground_truth",
    f"source_summary={source_summary}",
    f"db_path={db_path}",
    f"px4_local_position_log={px4_log}",
    f"csv_file={csv_file}",
    f"rtabmap_pose_count={len(rtabmap_poses)}",
    f"px4_reference_sample_count={len(px4_samples)}",
    f"matched_pair_count={len(pairs)}",
    f"rmse_m={metric(rmse)}",
    f"mean_error_m={metric(mean_error)}",
    f"median_error_m={metric(median_error)}",
    f"p95_error_m={metric(p95_error)}",
    f"max_error_m={metric(max_error)}",
    f"rtabmap_elapsed_start={metric(rtabmap_poses[0][1] if rtabmap_poses else math.nan)}",
    f"rtabmap_elapsed_end={metric(rtabmap_poses[-1][1] if rtabmap_poses else math.nan)}",
    f"px4_elapsed_start={metric(px4_samples[0][0] if px4_samples else math.nan)}",
    f"px4_elapsed_end={metric(px4_samples[-1][0] if px4_samples else math.nan)}",
    "rotation_row_major=" + " ".join(f"{v:.9f}" for v in rotation.reshape(-1)),
    "translation_xyz=" + " ".join(f"{v:.9f}" for v in translation),
]
summary_file.write_text("\n".join(lines) + "\n")
if not computed:
    sys.exit(1)
PY

echo "RTAB-Map PX4 local-position cross-check completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"
