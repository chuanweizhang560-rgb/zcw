#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/four_vehicle_rule_score_sweep_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/four_vehicle_rule_score_sweep_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/four_vehicle_rule_score_sweep_${STAMP}.csv"
DETAIL_FILE="${RESULT_DIR}/four_vehicle_rule_score_sweep_detail_${STAMP}.log"

RELAY_RADIUS_M="${RELAY_RADIUS_M:-800.0}"

mkdir -p "${RESULT_DIR}"

awk -v relay_radius="${RELAY_RADIUS_M}" -v csv_file="${CSV_FILE}" '
function abs(v) { return v < 0 ? -v : v }
function dist(ax, ay, bx, by, dx, dy) {
  dx = ax - bx
  dy = ay - by
  return sqrt(dx * dx + dy * dy)
}
function clamp01(v) {
  if (v < 0.0) { return 0.0 }
  if (v > 1.0) { return 1.0 }
  return v
}
function score_case(name, pose_ready, status_ready,
  x1, y1, x2, y2, x3, y3, x4, y4,
  g1x, g1y, g2x, g2y, g3x, g3y, g4x, g4y,
  dbase1, dbase2, dbase3, dbase4,
  d12, d23, d34, topology_ready, state_score, gd1, gd2, gd3, gd4,
  mean_goal_distance, task_distance_score, rule_total_score,
  chain_max_distance, chain_min_margin) {
  dbase1 = dist(x1, y1, 0.0, 0.0)
  dbase2 = dist(x2, y2, 0.0, 0.0)
  dbase3 = dist(x3, y3, 0.0, 0.0)
  dbase4 = dist(x4, y4, 0.0, 0.0)
  d12 = dist(x1, y1, x2, y2)
  d23 = dist(x2, y2, x3, y3)
  d34 = dist(x3, y3, x4, y4)
  chain_max_distance = d12
  if (d23 > chain_max_distance) { chain_max_distance = d23 }
  if (d34 > chain_max_distance) { chain_max_distance = d34 }
  chain_min_margin = relay_radius - d12
  if (relay_radius - d23 < chain_min_margin) { chain_min_margin = relay_radius - d23 }
  if (relay_radius - d34 < chain_min_margin) { chain_min_margin = relay_radius - d34 }

  topology_ready = pose_ready && dbase1 <= relay_radius && dbase2 <= relay_radius && dbase3 <= relay_radius && dbase4 <= relay_radius && d12 <= relay_radius && d23 <= relay_radius && d34 <= relay_radius
  state_score = (pose_ready && status_ready) ? 1.0 : 0.0

  if (pose_ready) {
    gd1 = dist(x1, y1, g1x, g1y)
    gd2 = dist(x2, y2, g2x, g2y)
    gd3 = dist(x3, y3, g3x, g3y)
    gd4 = dist(x4, y4, g4x, g4y)
    mean_goal_distance = (gd1 + gd2 + gd3 + gd4) / 4.0
    task_distance_score = 1.0 / (1.0 + mean_goal_distance / relay_radius)
  } else {
    mean_goal_distance = -1.0
    task_distance_score = 0.0
  }
  rule_total_score = 0.45 * (topology_ready ? 1.0 : 0.0) + 0.30 * state_score + 0.25 * task_distance_score

  printf "%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n", name, topology_ready ? "true" : "false", (pose_ready && status_ready) ? "true" : "false", chain_max_distance, chain_min_margin, mean_goal_distance, task_distance_score, rule_total_score, relay_radius >> csv_file
}
BEGIN {
  print "case,topology_ready,state_ready,chain_max_distance_m,chain_min_margin_m,mean_goal_distance_m,task_distance_score,rule_total_score,relay_radius_m" > csv_file

  score_case("near_ready_nominal", 1, 1, 0, 0, 0, 3, 3, 0, 3, 3, -25, -10, -35, 20, -12.5, -5, -17.5, 10)
  score_case("near_ready_exact_goals", 1, 1, -25, -10, -35, 20, -12.5, -5, -17.5, 10, -25, -10, -35, 20, -12.5, -5, -17.5, 10)
  score_case("topology_ok_task_far", 1, 1, 0, 0, 100, 0, 200, 0, 300, 0, 700, 0, 700, 50, 700, -50, 750, 0)
  score_case("chain_margin_near_limit", 1, 1, 0, 0, 780, 0, 790, 0, 795, 0, 780, 0, 790, 0, 795, 0, 796, 0)
  score_case("chain_break_between_1_2", 1, 1, 0, 0, 850, 0, 860, 0, 870, 0, 850, 0, 860, 0, 870, 0, 875, 0)
  score_case("base_range_break_vehicle_4", 1, 1, 0, 0, 250, 0, 500, 0, 850, 0, 100, 0, 300, 0, 500, 0, 850, 0)
  score_case("status_stale_topology_ok", 1, 0, 0, 0, 100, 0, 200, 0, 300, 0, 0, 0, 100, 0, 200, 0, 300, 0)
  score_case("pose_missing", 0, 1, 0, 0, 100, 0, 200, 0, 300, 0, 0, 0, 100, 0, 200, 0, 300, 0)
}
' >"${DETAIL_FILE}"

accepted=true
reason="score_sweep_matches_expected_monotonic_boundaries"

if ! awk -F, 'NR > 1 { if ($8 < 0 || $8 > 1.000001) exit 1 }' "${CSV_FILE}"; then
  accepted=false
  reason="rule_total_score_out_of_unit_range"
fi
if ! awk -F, '$1 == "near_ready_exact_goals" { if ($2 != "true" || $3 != "true" || $8 < 0.999999) exit 1 }' "${CSV_FILE}"; then
  accepted=false
  reason="exact_goal_ready_case_not_max_score"
fi
if ! awk -F, '$1 == "chain_break_between_1_2" { if ($2 != "false" || $8 >= 0.75) exit 1 }' "${CSV_FILE}"; then
  accepted=false
  reason="chain_break_case_not_penalized"
fi
if ! awk -F, '$1 == "status_stale_topology_ok" { if ($2 != "true" || $3 != "false" || $8 >= 0.75) exit 1 }' "${CSV_FILE}"; then
  accepted=false
  reason="status_stale_case_not_penalized"
fi
if ! awk -F, '$1 == "pose_missing" { if ($2 != "false" || $3 != "false" || $8 != 0) exit 1 }' "${CSV_FILE}"; then
  accepted=false
  reason="pose_missing_case_not_zeroed"
fi

{
  echo "scope=four_vehicle_rule_score_sweep"
  echo "decision=$([[ "${accepted}" == "true" ]] && echo accepted_four_vehicle_rule_score_sweep || echo rejected_four_vehicle_rule_score_sweep)"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "uses_learned_policy=false"
  echo "relay_radius_m=${RELAY_RADIUS_M}"
  echo "csv_file=${CSV_FILE}"
  echo "detail_file=${DETAIL_FILE}"
  echo "cases=$(awk 'END { print NR - 1 }' "${CSV_FILE}")"
} >"${SUMMARY_FILE}"

if [[ "${accepted}" != "true" ]]; then
  cat "${SUMMARY_FILE}" >&2
  cat "${CSV_FILE}" >&2
  exit 1
fi

cat "${CSV_FILE}" >>"${DETAIL_FILE}"

echo "Four-vehicle rule score sweep completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"
