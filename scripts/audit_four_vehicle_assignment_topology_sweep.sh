#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RELAY_RADIUS_M="${RELAY_RADIUS_M:-800.0}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/four_vehicle_assignment_topology_sweep_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/four_vehicle_assignment_topology_sweep_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/four_vehicle_assignment_topology_sweep_${STAMP}.csv"

mkdir -p "${RESULT_DIR}"

python3 - "${RELAY_RADIUS_M}" "${CSV_FILE}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys

relay_radius = float(sys.argv[1])
csv_file = sys.argv[2]

goals = [(-25.0, -10.0), (-35.0, 20.0), (-12.5, -5.0), (-17.5, 10.0)]
roles = [
    "wind_inspection_candidate",
    "cable_inspection_candidate",
    "relay_candidate",
    "relay_candidate",
]


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def score_case(name, poses, pose_ready=True, status_ready=True):
    base_distances = [dist(p, (0.0, 0.0)) if pose_ready else -1.0 for p in poses]
    chain_distances = [dist(poses[i - 1], poses[i]) for i in range(1, 4)] if pose_ready else [-1.0, -1.0, -1.0]
    chain_max = max(chain_distances)
    chain_min_margin = min(relay_radius - d for d in chain_distances) if pose_ready else -1.0
    topology_ready = (
        pose_ready
        and all(d <= relay_radius for d in base_distances)
        and all(d <= relay_radius for d in chain_distances)
    )
    state_ready = pose_ready and status_ready
    goal_distances = [dist(poses[i], goals[i]) for i in range(4)] if pose_ready else [-1.0] * 4
    mean_goal_distance = sum(goal_distances) / 4.0 if pose_ready else -1.0
    task_distance_score = 1.0 / (1.0 + mean_goal_distance / relay_radius) if pose_ready else 0.0
    topology_score = 1.0 if topology_ready else 0.0
    state_score = 1.0 if state_ready else 0.0
    rule_total_score = 0.45 * topology_score + 0.30 * state_score + 0.25 * task_distance_score
    return {
        "case": name,
        "topology_ready": str(topology_ready).lower(),
        "state_ready": str(state_ready).lower(),
        "chain_max_distance_m": f"{chain_max:.6f}",
        "chain_min_margin_m": f"{chain_min_margin:.6f}",
        "max_base_distance_m": f"{max(base_distances):.6f}",
        "mean_goal_distance_m": f"{mean_goal_distance:.6f}",
        "task_distance_score": f"{task_distance_score:.6f}",
        "rule_total_score": f"{rule_total_score:.6f}",
        "vehicle_1_role": roles[0],
        "vehicle_2_role": roles[1],
        "vehicle_3_role": roles[2],
        "vehicle_4_role": roles[3],
    }


cases = [
    score_case("exact_goals", goals),
    score_case("nominal_near_base", [(0.0, 0.0), (0.0, 3.0), (3.0, 0.0), (3.0, 3.0)]),
    score_case("chain_at_exact_limit", [(0.0, 0.0), (800.0, 0.0), (799.0, 0.0), (798.0, 0.0)]),
    score_case("chain_just_over_limit", [(0.0, 0.0), (800.1, 0.0), (800.1, 1.0), (800.1, 2.0)]),
    score_case("middle_chain_break", [(0.0, 0.0), (100.0, 0.0), (901.0, 0.0), (902.0, 0.0)]),
    score_case("tail_chain_break", [(0.0, 0.0), (100.0, 0.0), (200.0, 0.0), (1001.0, 0.0)]),
    score_case("base_exact_limit_vehicle_4", [(0.0, 0.0), (250.0, 0.0), (500.0, 0.0), (800.0, 0.0)]),
    score_case("base_just_over_vehicle_4", [(0.0, 0.0), (250.0, 0.0), (500.0, 0.0), (800.1, 0.0)]),
    score_case("far_tasks_but_connected", [(0.0, 0.0), (200.0, 0.0), (400.0, 0.0), (600.0, 0.0)]),
    score_case("status_stale_connected", [(0.0, 0.0), (200.0, 0.0), (400.0, 0.0), (600.0, 0.0)], status_ready=False),
    score_case("pose_missing", [(0.0, 0.0), (200.0, 0.0), (400.0, 0.0), (600.0, 0.0)], pose_ready=False),
]

with open(csv_file, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(cases[0].keys()))
    writer.writeheader()
    writer.writerows(cases)

case_by_name = {row["case"]: row for row in cases}

def as_bool(row, key):
    return row[key] == "true"

def as_float(row, key):
    return float(row[key])

checks = {
    "exact_goals_max_score": as_bool(case_by_name["exact_goals"], "topology_ready")
    and as_bool(case_by_name["exact_goals"], "state_ready")
    and as_float(case_by_name["exact_goals"], "rule_total_score") >= 0.999999,
    "exact_limit_is_ready": as_bool(case_by_name["chain_at_exact_limit"], "topology_ready"),
    "chain_just_over_rejected": not as_bool(case_by_name["chain_just_over_limit"], "topology_ready"),
    "middle_chain_break_rejected": not as_bool(case_by_name["middle_chain_break"], "topology_ready"),
    "tail_chain_break_rejected": not as_bool(case_by_name["tail_chain_break"], "topology_ready"),
    "base_exact_limit_ready": as_bool(case_by_name["base_exact_limit_vehicle_4"], "topology_ready"),
    "base_just_over_rejected": not as_bool(case_by_name["base_just_over_vehicle_4"], "topology_ready"),
    "status_stale_penalized": as_bool(case_by_name["status_stale_connected"], "topology_ready")
    and not as_bool(case_by_name["status_stale_connected"], "state_ready")
    and as_float(case_by_name["status_stale_connected"], "rule_total_score") < 0.75,
    "pose_missing_zeroed": not as_bool(case_by_name["pose_missing"], "topology_ready")
    and not as_bool(case_by_name["pose_missing"], "state_ready")
    and as_float(case_by_name["pose_missing"], "rule_total_score") == 0.0,
    "roles_fixed": all(row[f"vehicle_{idx}_role"] == roles[idx - 1] for row in cases for idx in range(1, 5)),
}

accepted = all(checks.values())
reason = "assignment_and_topology_boundaries_match_rule_baseline" if accepted else "assignment_or_topology_boundary_failed"

print("scope=four_vehicle_assignment_topology_sweep")
print(f"decision={'accepted_four_vehicle_assignment_topology_sweep' if accepted else 'rejected_four_vehicle_assignment_topology_sweep'}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print("uses_learned_policy=false")
print(f"relay_radius_m={relay_radius:.6f}")
print(f"csv_file={csv_file}")
print(f"cases={len(cases)}")
for key, value in checks.items():
    print(f"{key}={str(value).lower()}")
print(f"claims_assignment_topology_sweep_pass={str(accepted).lower()}")
PY

echo "Four-vehicle assignment/topology sweep completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"

grep -q "decision=accepted_four_vehicle_assignment_topology_sweep" "${SUMMARY_FILE}"
