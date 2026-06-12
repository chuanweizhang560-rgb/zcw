#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
SCENARIO="${SCENARIO:-rtabmap}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/${SCENARIO}_trajectory_ate_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/${SCENARIO}_trajectory_ate_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/${SCENARIO}_trajectory_ate_${STAMP}.csv"

SOURCE_SUMMARY="${SOURCE_SUMMARY:-}"
DB_PATH="${DB_PATH:-}"
REFERENCE_LOG="${REFERENCE_LOG:-}"

value_for() {
  local key="$1"
  local file="$2"
  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${file}"
}

if [[ -n "${SOURCE_SUMMARY}" && -f "${SOURCE_SUMMARY}" ]]; then
  if [[ -z "${DB_PATH}" ]]; then
    DB_PATH="$(find "$(dirname "${SOURCE_SUMMARY}")" -maxdepth 1 -type f -name '*.db' | sort | tail -n 1)"
  fi
  if [[ -z "${REFERENCE_LOG}" ]]; then
    REFERENCE_LOG="$(value_for depth_pose_trajectory_log "${SOURCE_SUMMARY}")"
  fi
fi

if [[ -z "${DB_PATH}" || ! -f "${DB_PATH}" ]]; then
  echo "RTAB-Map database not found. Set DB_PATH or SOURCE_SUMMARY." >&2
  exit 1
fi
if [[ -z "${REFERENCE_LOG}" || ! -f "${REFERENCE_LOG}" ]]; then
  echo "reference trajectory log not found. Set REFERENCE_LOG or SOURCE_SUMMARY with depth_pose_trajectory_log." >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$DB_PATH" "$REFERENCE_LOG" "$CSV_FILE" "$SUMMARY_FILE" "${SOURCE_SUMMARY:-}" "${SCENARIO}" <<'PY'
import csv
import math
import re
import sqlite3
import struct
import sys
from pathlib import Path

import numpy as np

db_path = Path(sys.argv[1])
reference_log = Path(sys.argv[2])
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
    return poses


def parse_reference_log(path):
    text = path.read_text(errors="replace")
    blocks = re.split(r"\n---\s*\n", text)
    samples = []
    for block in blocks:
        sec_m = re.search(r"\bstamp:\s*\n\s*sec:\s*([0-9]+)\s*\n\s*nanosec:\s*([0-9]+)", block)
        pos_m = re.search(
            r"\bposition:\s*\n\s*x:\s*([-+0-9.eE]+)\s*\n\s*y:\s*([-+0-9.eE]+)\s*\n\s*z:\s*([-+0-9.eE]+)",
            block,
        )
        if not sec_m or not pos_m:
            continue
        stamp = float(sec_m.group(1)) + float(sec_m.group(2)) * 1e-9
        xyz = np.array([float(pos_m.group(1)), float(pos_m.group(2)), float(pos_m.group(3))], dtype=float)
        if np.all(np.isfinite(xyz)):
            samples.append((stamp, xyz))
    samples.sort(key=lambda item: item[0])
    dedup = []
    for stamp, xyz in samples:
        if dedup and abs(dedup[-1][0] - stamp) < 1e-9:
            dedup[-1] = (stamp, xyz)
        else:
            dedup.append((stamp, xyz))
    return dedup


def interpolate_reference(samples, stamp):
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
reference_samples = parse_reference_log(reference_log)
pairs = []
for node_id, stamp, rtab_xyz in rtabmap_poses:
    ref_xyz = interpolate_reference(reference_samples, stamp)
    if ref_xyz is not None:
        pairs.append((node_id, stamp, rtab_xyz, ref_xyz))

if len(pairs) >= 3:
    rtab_points = np.vstack([item[2] for item in pairs])
    ref_points = np.vstack([item[3] for item in pairs])
    aligned_points, rotation, translation = rigid_align(rtab_points, ref_points)
    errors = np.linalg.norm(aligned_points - ref_points, axis=1)
else:
    aligned_points = np.zeros((0, 3), dtype=float)
    rotation = np.eye(3, dtype=float)
    translation = np.zeros(3, dtype=float)
    errors = np.array([], dtype=float)

with csv_file.open("w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["node_id", "stamp", "rtab_x", "rtab_y", "rtab_z", "ref_x", "ref_y", "ref_z", "aligned_x", "aligned_y", "aligned_z", "error_m"])
    for index, (node_id, stamp, rtab_xyz, ref_xyz) in enumerate(pairs):
        aligned_xyz = aligned_points[index] if len(aligned_points) else np.array([math.nan] * 3)
        error = errors[index] if len(errors) else math.nan
        writer.writerow([node_id, f"{stamp:.9f}", f"{rtab_xyz[0]:.9f}", f"{rtab_xyz[1]:.9f}", f"{rtab_xyz[2]:.9f}", f"{ref_xyz[0]:.9f}", f"{ref_xyz[1]:.9f}", f"{ref_xyz[2]:.9f}", f"{aligned_xyz[0]:.9f}", f"{aligned_xyz[1]:.9f}", f"{aligned_xyz[2]:.9f}", f"{error:.9f}"])

computed = len(errors) >= 3 and np.all(np.isfinite(errors))
decision = f"accepted_{scenario}_trajectory_ate" if computed else f"rejected_{scenario}_trajectory_ate"
reason = "rigid_aligned_ate_computed_from_rtabmap_db_and_p3d_reference" if computed else "insufficient_time_overlap_for_ate"

def metric(value):
    return "nan" if value is None or not np.isfinite(value) else f"{value:.9f}"

rmse = math.sqrt(float(np.mean(errors ** 2))) if computed else math.nan
mean_error = float(np.mean(errors)) if computed else math.nan
median_error = float(np.median(errors)) if computed else math.nan
max_error = float(np.max(errors)) if computed else math.nan
p95_error = float(np.percentile(errors, 95)) if computed else math.nan

lines = [
    f"scope={scenario}_trajectory_ate",
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
    "uses_p3d_reference=true",
    "alignment=rigid_se3_svd",
    "claims_slam_pass=false",
    f"source_summary={source_summary}",
    f"db_path={db_path}",
    f"reference_log={reference_log}",
    f"csv_file={csv_file}",
    f"rtabmap_pose_count={len(rtabmap_poses)}",
    f"reference_sample_count={len(reference_samples)}",
    f"matched_pair_count={len(pairs)}",
    f"rmse_m={metric(rmse)}",
    f"mean_error_m={metric(mean_error)}",
    f"median_error_m={metric(median_error)}",
    f"p95_error_m={metric(p95_error)}",
    f"max_error_m={metric(max_error)}",
    f"rtabmap_time_start={metric(rtabmap_poses[0][1] if rtabmap_poses else math.nan)}",
    f"rtabmap_time_end={metric(rtabmap_poses[-1][1] if rtabmap_poses else math.nan)}",
    f"reference_time_start={metric(reference_samples[0][0] if reference_samples else math.nan)}",
    f"reference_time_end={metric(reference_samples[-1][0] if reference_samples else math.nan)}",
    "rotation_row_major=" + " ".join(f"{v:.9f}" for v in rotation.reshape(-1)),
    "translation_xyz=" + " ".join(f"{v:.9f}" for v in translation),
]
summary_file.write_text("\n".join(lines) + "\n")
if not computed:
    sys.exit(1)
PY

echo "RTAB-Map trajectory ATE audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"
