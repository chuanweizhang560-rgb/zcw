#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_C1_SUMMARY="data/results/cable_visible_side_surface_coverage_offline_20260617_093538/cable_visible_side_surface_coverage_offline_20260617_093538.txt"
DEFAULT_C2_CANDIDATE_SUMMARY="data/results/cable_multiview_surface_candidate_offline_20260617_094219/cable_multiview_surface_candidate_offline_20260617_094219.txt"
DEFAULT_C2_UNION_SUMMARY="data/results/cable_multiview_surface_union_offline_20260617_094233/cable_multiview_surface_union_offline_20260617_094233.txt"
DEFAULT_DRY_RUN_SUMMARY="data/results/cable_dry_run_acceptance_20260617_085648/cable_dry_run_acceptance_20260617_085648.txt"

C1_SUMMARY="${C1_SUMMARY:-${DEFAULT_C1_SUMMARY}}"
C2_CANDIDATE_SUMMARY="${C2_CANDIDATE_SUMMARY:-${DEFAULT_C2_CANDIDATE_SUMMARY}}"
C2_UNION_SUMMARY="${C2_UNION_SUMMARY:-${DEFAULT_C2_UNION_SUMMARY}}"
DRY_RUN_SUMMARY="${DRY_RUN_SUMMARY:-${DEFAULT_DRY_RUN_SUMMARY}}"
MIN_MULTIVIEW_TOTAL_RATIO="${MIN_MULTIVIEW_TOTAL_RATIO:-0.85}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_surface_current_acceptance_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_surface_current_acceptance_${STAMP}.txt"

for file in "${C1_SUMMARY}" "${C2_CANDIDATE_SUMMARY}" "${C2_UNION_SUMMARY}" "${DRY_RUN_SUMMARY}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required input file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

read_field() {
  local file="$1"
  local key="$2"
  awk -F= -v key="${key}" '$1 == key {print $2; found=1} END {if (!found) exit 1}' "${file}"
}

c1_decision="$(read_field "${C1_SUMMARY}" decision)"
c1_claim="$(read_field "${C1_SUMMARY}" claims_visible_side_surface_coverage_offline_pass)"
c1_final_claim="$(read_field "${C1_SUMMARY}" claims_final_cable_inspection_coverage)"
c2_candidate_decision="$(read_field "${C2_CANDIDATE_SUMMARY}" decision)"
c2_candidate_claim="$(read_field "${C2_CANDIDATE_SUMMARY}" claims_multiview_surface_candidate_offline_pass)"
c2_union_decision="$(read_field "${C2_UNION_SUMMARY}" decision)"
c2_union_claim="$(read_field "${C2_UNION_SUMMARY}" claims_multiview_surface_union_offline_pass)"
c2_total_ratio="$(read_field "${C2_UNION_SUMMARY}" global_min_total_surface_coverage_upper_bound_ratio)"
c2_visible_ratio="$(read_field "${C2_UNION_SUMMARY}" global_min_visible_side_coverage_upper_bound_ratio)"
c2_final_claim="$(read_field "${C2_UNION_SUMMARY}" claims_final_cable_inspection_coverage)"
dry_run_decision="$(read_field "${DRY_RUN_SUMMARY}" decision)"
dry_run_claim="$(read_field "${DRY_RUN_SUMMARY}" claims_cable_dry_run_acceptance_pass)"

python3 - "${SUMMARY_FILE}" \
  "${C1_SUMMARY}" "${C2_CANDIDATE_SUMMARY}" "${C2_UNION_SUMMARY}" "${DRY_RUN_SUMMARY}" \
  "${c1_decision}" "${c1_claim}" "${c1_final_claim}" \
  "${c2_candidate_decision}" "${c2_candidate_claim}" \
  "${c2_union_decision}" "${c2_union_claim}" "${c2_total_ratio}" "${c2_visible_ratio}" "${c2_final_claim}" \
  "${dry_run_decision}" "${dry_run_claim}" "${MIN_MULTIVIEW_TOTAL_RATIO}" <<'PY'
import sys

(
    summary_file,
    c1_summary,
    c2_candidate_summary,
    c2_union_summary,
    dry_run_summary,
    c1_decision,
    c1_claim,
    c1_final_claim,
    c2_candidate_decision,
    c2_candidate_claim,
    c2_union_decision,
    c2_union_claim,
    c2_total_ratio,
    c2_visible_ratio,
    c2_final_claim,
    dry_run_decision,
    dry_run_claim,
    min_multiview_total_ratio,
) = sys.argv[1:19]

c2_total_ratio_f = float(c2_total_ratio)
c2_visible_ratio_f = float(c2_visible_ratio)
min_multiview_total_ratio_f = float(min_multiview_total_ratio)

c1_ok = c1_decision == "accepted_cable_visible_side_surface_coverage_offline" and c1_claim == "true"
c2_candidate_ok = c2_candidate_decision == "accepted_cable_multiview_surface_candidate_offline" and c2_candidate_claim == "true"
c2_union_ok = (
    c2_union_decision == "accepted_cable_multiview_surface_union_offline"
    and c2_union_claim == "true"
    and c2_total_ratio_f >= min_multiview_total_ratio_f
)
dry_run_ok = dry_run_decision == "accepted_cable_dry_run_acceptance" and dry_run_claim == "true"
final_claim_blocked = c1_final_claim == "false" and c2_final_claim == "false"
accepted = c1_ok and c2_candidate_ok and c2_union_ok and dry_run_ok and final_claim_blocked
decision = "accepted_cable_surface_current_acceptance" if accepted else "rejected_cable_surface_current_acceptance"
reason = "surface_progression_ready_but_final_claim_blocked" if accepted else "surface_progression_evidence_incomplete"

lines = [
    "scope=cable_surface_current_acceptance",
    f"decision={decision}",
    f"reason={reason}",
    "starts_ros=false",
    "starts_px4=false",
    "starts_gazebo=false",
    "starts_rviz=false",
    "starts_offboard=false",
    "arms=false",
    "publishes_fmu_in=false",
    f"c1_summary={c1_summary}",
    f"c2_candidate_summary={c2_candidate_summary}",
    f"c2_union_summary={c2_union_summary}",
    f"dry_run_summary={dry_run_summary}",
    f"min_multiview_total_ratio={min_multiview_total_ratio_f:.9f}",
    f"c1_visible_side_ok={str(c1_ok).lower()}",
    f"c2_candidate_ok={str(c2_candidate_ok).lower()}",
    f"c2_union_ok={str(c2_union_ok).lower()}",
    f"dry_run_ok={str(dry_run_ok).lower()}",
    f"final_claim_blocked={str(final_claim_blocked).lower()}",
    f"c2_global_min_total_surface_coverage_upper_bound_ratio={c2_total_ratio_f:.9f}",
    f"c2_global_min_visible_side_coverage_upper_bound_ratio={c2_visible_ratio_f:.9f}",
    "claims_active_control_approval=false",
    "claims_final_cable_inspection_coverage=false",
    f"claims_cable_surface_progression_current_acceptance_pass={str(accepted).lower()}",
]

with open(summary_file, "w") as f:
    f.write("\n".join(lines) + "\n")
PY

echo "Cable surface current acceptance audit completed."
echo "Summary: ${SUMMARY_FILE}"

grep -q "decision=accepted_cable_surface_current_acceptance" "${SUMMARY_FILE}"
