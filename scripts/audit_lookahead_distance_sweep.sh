#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_INPUT="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
INPUT_CSV="${INPUT_CSV:-${DEFAULT_INPUT}}"
LOOKAHEAD_VALUES="${LOOKAHEAD_VALUES:-15.0 20.0 25.0}"
MIN_TARGET_DISTANCE_M="${MIN_TARGET_DISTANCE_M:-10.0}"
MAX_TARGET_DISTANCE_M="${MAX_TARGET_DISTANCE_M:-35.0}"
MIN_TARGETS_PER_GROUP="${MIN_TARGETS_PER_GROUP:-2}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/lookahead_distance_sweep_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/lookahead_distance_sweep_${STAMP}.txt"
SWEEP_CSV="${RESULT_DIR}/lookahead_distance_sweep_${STAMP}.csv"

if [[ ! -f "${INPUT_CSV}" ]]; then
  echo "Input CSV does not exist: ${INPUT_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$INPUT_CSV" "$SWEEP_CSV" "$MIN_TARGET_DISTANCE_M" "$MAX_TARGET_DISTANCE_M" "$MIN_TARGETS_PER_GROUP" "$RESULT_DIR" ${LOOKAHEAD_VALUES} >"${SUMMARY_FILE}" <<'PY'
import csv
import glob
import os
import re
import subprocess
import sys

input_csv = sys.argv[1]
sweep_csv = sys.argv[2]
min_target_distance = sys.argv[3]
max_target_distance = sys.argv[4]
min_targets_per_group = sys.argv[5]
result_dir = sys.argv[6]
lookahead_values = [float(v) for v in sys.argv[7:]]
repo_root = os.path.dirname(os.path.dirname(os.path.dirname(result_dir)))

rows = []
for value in lookahead_values:
    value_tag = str(value).replace(".", "_")
    output_dir = os.path.join(result_dir, f"lookahead_{value_tag}")
    cmd = [
        "bash",
        "-lc",
        "source /opt/ros/humble/setup.bash && source install/setup.bash && "
        f"LOOKAHEAD_M={value} MIN_TARGET_DISTANCE_M={min_target_distance} "
        f"MAX_TARGET_DISTANCE_M={max_target_distance} MIN_TARGETS_PER_GROUP={min_targets_per_group} "
        f"OUTPUT_DIR={output_dir} OUTPUT_PREFIX=lookahead_distance_audit "
        f"scripts/audit_lookahead_target.sh"
    ]
    proc = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(proc.returncode)
    summary_matches = sorted(glob.glob(os.path.join(output_dir, "lookahead_distance_audit_*.txt")))
    groups_matches = sorted(glob.glob(os.path.join(output_dir, "lookahead_distance_audit_groups_*.csv")))
    if not summary_matches:
        raise SystemExit(f"missing summary for lookahead {value}")
    summary_path = summary_matches[-1]
    groups_path = groups_matches[-1] if groups_matches else None
    summary = {}
    with open(summary_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                summary[k.strip()] = v.strip()
            elif ":" in line:
                k, v = line.split(":", 1)
                summary[k.strip()] = v.strip()
    group_rows = []
    if groups_path and os.path.exists(groups_path):
        with open(groups_path, "r", encoding="utf-8") as f:
            group_rows = list(csv.DictReader(f))
    accepted_group_rows = [row for row in group_rows if row.get("accepted", "").lower() == "true"]
    if accepted_group_rows:
        min_distance = min(float(row["min_distance"]) for row in accepted_group_rows)
        max_distance = max(float(row["max_distance"]) for row in accepted_group_rows)
        mean_distance = sum(float(row["mean_distance"]) for row in accepted_group_rows) / len(accepted_group_rows)
    else:
        min_distance = 0.0
        max_distance = 0.0
        mean_distance = 0.0
    rows.append({
        "lookahead_m": value,
        "decision": summary.get("decision", "missing"),
        "accepted_groups": summary.get("accepted_groups", "0"),
        "targets": summary.get("targets", "0"),
        "groups": summary.get("groups", "0"),
        "min_distance": min_distance,
        "max_distance": max_distance,
        "mean_distance": mean_distance,
        "output_dir": output_dir,
        "summary_path": summary_path,
    })

with open(sweep_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=[
        "lookahead_m",
        "decision",
        "accepted_groups",
        "groups",
        "targets",
        "min_distance",
        "max_distance",
        "mean_distance",
        "output_dir",
        "summary_path",
    ])
    writer.writeheader()
    writer.writerows(rows)

accepted = all(row["decision"] == "accepted_lookahead_target_smoke" for row in rows)
print("scope=lookahead_distance_sweep")
print(f"decision={'accepted_lookahead_distance_sweep' if accepted else 'rejected_lookahead_distance_sweep'}")
print(f"reason={'all_lookahead_values_accepted' if accepted else 'one_or_more_lookahead_values_rejected'}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"input_csv={input_csv}")
print(f"sweep_csv={sweep_csv}")
for row in rows:
    print(
        "lookahead_m={lookahead_m:.6f} decision={decision} accepted_groups={accepted_groups} groups={groups} targets={targets} "
        "min_distance={min_distance:.6f} max_distance={max_distance:.6f} mean_distance={mean_distance:.6f} "
        "summary_path={summary_path}".format(**row)
    )

if not accepted:
    raise SystemExit(2)
PY

echo "Lookahead distance sweep completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Sweep CSV: ${SWEEP_CSV}"
