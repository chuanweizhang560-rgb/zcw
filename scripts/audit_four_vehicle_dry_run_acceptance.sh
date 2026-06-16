#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_READONLY_SUMMARY="data/results/multi_vehicle_readonly_20260609_111036/multi_vehicle_readonly_20260609_111036.txt"
DEFAULT_CONTRACT_SUMMARY="data/results/four_vehicle_dry_run_contract_20260611_150804/four_vehicle_dry_run_contract_20260611_150804.txt"
DEFAULT_SMOKE_SUMMARY="data/results/four_vehicle_dry_run_smoke_20260611_150906/four_vehicle_dry_run_smoke_20260611_150906.txt"
DEFAULT_SAMPLES_SUMMARY="data/results/four_vehicle_dry_run_samples_audit_20260611_150859/four_vehicle_dry_run_samples_audit_20260611_150859.txt"
DEFAULT_SCORE_SWEEP_SUMMARY="data/results/four_vehicle_rule_score_sweep_20260611_152204/four_vehicle_rule_score_sweep_20260611_152204.txt"
DEFAULT_ASSIGNMENT_TOPOLOGY_SWEEP_SUMMARY="data/results/four_vehicle_assignment_topology_sweep_20260616_090752/four_vehicle_assignment_topology_sweep_20260616_090752.txt"

READONLY_SUMMARY="${READONLY_SUMMARY:-${DEFAULT_READONLY_SUMMARY}}"
CONTRACT_SUMMARY="${CONTRACT_SUMMARY:-${DEFAULT_CONTRACT_SUMMARY}}"
SMOKE_SUMMARY="${SMOKE_SUMMARY:-${DEFAULT_SMOKE_SUMMARY}}"
SAMPLES_SUMMARY="${SAMPLES_SUMMARY:-${DEFAULT_SAMPLES_SUMMARY}}"
SCORE_SWEEP_SUMMARY="${SCORE_SWEEP_SUMMARY:-${DEFAULT_SCORE_SWEEP_SUMMARY}}"
ASSIGNMENT_TOPOLOGY_SWEEP_SUMMARY="${ASSIGNMENT_TOPOLOGY_SWEEP_SUMMARY:-${DEFAULT_ASSIGNMENT_TOPOLOGY_SWEEP_SUMMARY}}"
MIN_SCORE_SWEEP_CASES="${MIN_SCORE_SWEEP_CASES:-8}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/four_vehicle_dry_run_acceptance_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/four_vehicle_dry_run_acceptance_${STAMP}.txt"

for file in "${READONLY_SUMMARY}" "${CONTRACT_SUMMARY}" "${SMOKE_SUMMARY}" "${SAMPLES_SUMMARY}" "${SCORE_SWEEP_SUMMARY}" "${ASSIGNMENT_TOPOLOGY_SWEEP_SUMMARY}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required evidence file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - \
  "${READONLY_SUMMARY}" \
  "${CONTRACT_SUMMARY}" \
  "${SMOKE_SUMMARY}" \
  "${SAMPLES_SUMMARY}" \
  "${SCORE_SWEEP_SUMMARY}" \
  "${ASSIGNMENT_TOPOLOGY_SWEEP_SUMMARY}" \
  "${MIN_SCORE_SWEEP_CASES}" >"${SUMMARY_FILE}" <<'PY'
import os
import sys

(
    readonly_summary,
    contract_summary,
    smoke_summary,
    samples_summary,
    score_sweep_summary,
    assignment_topology_sweep_summary,
    min_score_sweep_cases,
) = sys.argv[1:8]
min_score_sweep_cases = int(min_score_sweep_cases)


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


def i(kv, key, default=0):
    try:
        return int(float(kv.get(key, default)))
    except ValueError:
        return default


readonly = load_kv(readonly_summary)
contract = load_kv(contract_summary)
smoke = load_kv(smoke_summary)
samples = load_kv(samples_summary)
score = load_kv(score_sweep_summary)
assignment_topology = load_kv(assignment_topology_sweep_summary)

screenshot = smoke.get("screenshot", "")
screenshot_path = screenshot if screenshot.startswith("/") else os.path.abspath(screenshot)
screenshot_ok = os.path.isfile(screenshot_path) and os.path.getsize(screenshot_path) > 0

readonly_ok = (
    readonly.get("decision") == "accepted_multi_vehicle_readonly_smoke"
    and readonly.get("num_vehicles") == "4"
    and readonly.get("starts_offboard") == "false"
    and readonly.get("arms") == "false"
    and readonly.get("publishes_fmu_in") == "false"
    and readonly.get("forbidden_publishers_zero") == "true"
    and readonly.get("observed_px4_1_vehicle_status") == "true"
    and readonly.get("observed_px4_2_vehicle_status") == "true"
    and readonly.get("observed_px4_3_vehicle_status") == "true"
    and readonly.get("observed_px4_4_vehicle_status") == "true"
)
contract_ok = (
    contract.get("decision") == "accepted_four_vehicle_dry_run_contract_static_audit"
    and contract.get("has_source_target") == "true"
    and contract.get("has_launch_node") == "true"
    and contract.get("has_allowed_outputs") == "true"
    and contract.get("has_allowed_inputs") == "true"
    and contract.get("forbidden_topics") == "false"
    and contract.get("forbidden_active_terms") == "false"
)
smoke_ok = (
    smoke.get("decision") == "accepted_four_vehicle_dry_run_smoke"
    and smoke.get("num_vehicles") == "4"
    and smoke.get("starts_offboard") == "false"
    and smoke.get("arms") == "false"
    and smoke.get("publishes_fmu_in") == "false"
    and smoke.get("dry_topics_ok") == "true"
    and smoke.get("forbidden_publishers_zero") == "true"
    and smoke.get("screenshot_ok") == "1"
    and screenshot_ok
)
samples_ok = (
    samples.get("decision") == "accepted_four_vehicle_dry_run_samples_audit"
    and samples.get("has_all_goals") == "true"
    and samples.get("has_topology") == "true"
    and samples.get("has_safety") == "true"
    and samples.get("has_assignment") == "true"
    and samples.get("has_scoring") == "true"
    and samples.get("has_score_markers") == "true"
    and samples.get("has_rule_baseline") == "true"
    and samples.get("has_rule_score") == "true"
    and samples.get("has_marker_text") == "true"
    and samples.get("has_no_learned_policy") == "true"
    and samples.get("has_no_active") == "true"
    and samples.get("has_no_fmu_in") == "true"
    and samples.get("has_valid_topology_distance") == "true"
    and samples.get("has_score_terms") == "true"
    and samples.get("has_roles") == "true"
)
score_ok = (
    score.get("decision") == "accepted_four_vehicle_rule_score_sweep"
    and score.get("uses_learned_policy") == "false"
    and score.get("starts_offboard") == "false"
    and score.get("arms") == "false"
    and score.get("publishes_fmu_in") == "false"
    and i(score, "cases") >= min_score_sweep_cases
)
assignment_topology_ok = (
    assignment_topology.get("decision") == "accepted_four_vehicle_assignment_topology_sweep"
    and assignment_topology.get("uses_learned_policy") == "false"
    and assignment_topology.get("starts_offboard") == "false"
    and assignment_topology.get("arms") == "false"
    and assignment_topology.get("publishes_fmu_in") == "false"
    and assignment_topology.get("exact_limit_is_ready") == "true"
    and assignment_topology.get("chain_just_over_rejected") == "true"
    and assignment_topology.get("middle_chain_break_rejected") == "true"
    and assignment_topology.get("tail_chain_break_rejected") == "true"
    and assignment_topology.get("base_exact_limit_ready") == "true"
    and assignment_topology.get("base_just_over_rejected") == "true"
    and assignment_topology.get("status_stale_penalized") == "true"
    and assignment_topology.get("pose_missing_zeroed") == "true"
    and assignment_topology.get("roles_fixed") == "true"
)

accepted = readonly_ok and contract_ok and smoke_ok and samples_ok and score_ok and assignment_topology_ok
decision = "accepted_four_vehicle_dry_run_acceptance" if accepted else "rejected_four_vehicle_dry_run_acceptance"
reason = "four_vehicle_readonly_contract_smoke_samples_and_score_sweep_pass" if accepted else "one_or_more_four_vehicle_dry_run_gates_failed"

print("scope=four_vehicle_dry_run_acceptance")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print("source_smoke_started_ros=true")
print("source_smoke_started_px4=true")
print("source_smoke_started_gazebo=true")
print("source_smoke_started_rviz=true")
print("source_smoke_started_offboard=false")
print("source_smoke_armed=false")
print("source_smoke_published_fmu_in=false")
print("uses_learned_policy=false")
print("scope_boundary=four_vehicle_dry_run_readonly_only")
print("claims_multi_vehicle_active_approval=false")
print("claims_cable_active_bridge_approval=false")
print(f"readonly_summary={readonly_summary}")
print(f"contract_summary={contract_summary}")
print(f"smoke_summary={smoke_summary}")
print(f"samples_summary={samples_summary}")
print(f"score_sweep_summary={score_sweep_summary}")
print(f"assignment_topology_sweep_summary={assignment_topology_sweep_summary}")
print(f"readonly_ok={str(readonly_ok).lower()}")
print(f"contract_ok={str(contract_ok).lower()}")
print(f"smoke_ok={str(smoke_ok).lower()}")
print(f"samples_ok={str(samples_ok).lower()}")
print(f"score_ok={str(score_ok).lower()}")
print(f"assignment_topology_ok={str(assignment_topology_ok).lower()}")
print(f"num_vehicles={smoke.get('num_vehicles', '')}")
print(f"dry_topics_ok={smoke.get('dry_topics_ok', '')}")
print(f"forbidden_publishers_zero={smoke.get('forbidden_publishers_zero', '')}")
print(f"has_topology={samples.get('has_topology', '')}")
print(f"has_assignment={samples.get('has_assignment', '')}")
print(f"has_scoring={samples.get('has_scoring', '')}")
print(f"has_roles={samples.get('has_roles', '')}")
print(f"score_sweep_cases={i(score, 'cases')}")
print(f"assignment_topology_cases={i(assignment_topology, 'cases')}")
print(f"screenshot={screenshot_path}")
print(f"screenshot_ok={str(screenshot_ok).lower()}")
print(f"claims_four_vehicle_dry_run_acceptance_pass={str(accepted).lower()}")
PY

echo "Four-vehicle dry-run acceptance audit completed."
echo "Summary: ${SUMMARY_FILE}"

grep -q "decision=accepted_four_vehicle_dry_run_acceptance" "${SUMMARY_FILE}"
