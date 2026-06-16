#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_CABLE_SUMMARY="data/results/cable_dry_run_acceptance_20260616_152304/cable_dry_run_acceptance_20260616_152304.txt"
DEFAULT_WIND_SUMMARY="data/results/wind_rule_baseline_acceptance_20260616_095017/wind_rule_baseline_acceptance_20260616_095017.txt"
DEFAULT_FOUR_VEHICLE_SUMMARY="data/results/four_vehicle_dry_run_acceptance_20260616_085834/four_vehicle_dry_run_acceptance_20260616_085834.txt"
CABLE_SUMMARY="${CABLE_SUMMARY:-${DEFAULT_CABLE_SUMMARY}}"
WIND_SUMMARY="${WIND_SUMMARY:-${DEFAULT_WIND_SUMMARY}}"
FOUR_VEHICLE_SUMMARY="${FOUR_VEHICLE_SUMMARY:-${DEFAULT_FOUR_VEHICLE_SUMMARY}}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/project_current_acceptance_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/project_current_acceptance_${STAMP}.txt"

for file in "${CABLE_SUMMARY}" "${WIND_SUMMARY}" "${FOUR_VEHICLE_SUMMARY}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required aggregate summary does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${CABLE_SUMMARY}" "${WIND_SUMMARY}" "${FOUR_VEHICLE_SUMMARY}" >"${SUMMARY_FILE}" <<'PY'
import sys

cable_summary, wind_summary, four_vehicle_summary = sys.argv[1:4]


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


cable = load_kv(cable_summary)
wind = load_kv(wind_summary)
four = load_kv(four_vehicle_summary)

cable_ok = (
    cable.get("decision") == "accepted_cable_dry_run_acceptance"
    and cable.get("tracking_ok") == "true"
    and cable.get("frame_ok") == "true"
    and cable.get("coverage_ok") == "true"
    and cable.get("boundary_ok") == "true"
)
wind_ok = (
    wind.get("decision") == "accepted_wind_rule_baseline_acceptance"
    and wind.get("capture_ok") == "true"
    and wind.get("dynamic_ok") == "true"
    and wind.get("occlusion_ok") == "true"
    and wind.get("loop_ok") == "true"
    and wind.get("mapping_boundary_ok") == "true"
    and wind.get("claims_cable_active_bridge_approval") == "false"
    and wind.get("claims_multi_vehicle_active_approval") == "false"
)
four_ok = (
    four.get("decision") == "accepted_four_vehicle_dry_run_acceptance"
    and four.get("readonly_ok") == "true"
    and four.get("contract_ok") == "true"
    and four.get("smoke_ok") == "true"
    and four.get("samples_ok") == "true"
    and four.get("score_ok") == "true"
    and four.get("claims_multi_vehicle_active_approval") == "false"
    and four.get("claims_cable_active_bridge_approval") == "false"
)

accepted = cable_ok and wind_ok and four_ok
decision = "accepted_project_current_acceptance" if accepted else "rejected_project_current_acceptance"
reason = "cable_wind_and_four_vehicle_current_aggregate_evidence_pass" if accepted else "one_or_more_project_aggregate_gates_failed"

print("scope=project_current_acceptance")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"cable_summary={cable_summary}")
print(f"wind_summary={wind_summary}")
print(f"four_vehicle_summary={four_vehicle_summary}")
print(f"cable_dry_run_ok={str(cable_ok).lower()}")
print(f"wind_rule_baseline_ok={str(wind_ok).lower()}")
print(f"four_vehicle_dry_run_ok={str(four_ok).lower()}")
print("allowed_current_capability=cable_geometry_tracking_coverage_dry_run")
print("allowed_current_capability=single_vehicle_wind_rule_baseline_evidence")
print("allowed_current_capability=four_vehicle_assignment_topology_scoring_dry_run")
print("forbidden_current_capability=cable_phase_b_active_bridge")
print("forbidden_current_capability=multi_vehicle_active_offboard")
print("forbidden_current_capability=rl_policy_control")
print("forbidden_current_capability=image_level_defect_detection_claim")
print("claims_project_current_acceptance_pass=" + str(accepted).lower())
PY

echo "Project current acceptance audit completed."
echo "Summary: ${SUMMARY_FILE}"

grep -q "decision=accepted_project_current_acceptance" "${SUMMARY_FILE}"
