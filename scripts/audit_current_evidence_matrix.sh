#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_CABLE_DRY_RUN_SUMMARY="data/results/cable_dry_run_acceptance_20260617_085648/cable_dry_run_acceptance_20260617_085648.txt"
DEFAULT_CABLE_VISUAL_SUMMARY="data/results/cable_visual_acceptance_20260617_085710/cable_visual_acceptance_20260617_085710.txt"
DEFAULT_CABLE_SURFACE_SUMMARY="data/results/cable_surface_current_acceptance_20260617_163650/cable_surface_current_acceptance_20260617_163650.txt"
DEFAULT_WIND_SUMMARY="data/results/wind_rule_baseline_acceptance_20260616_095017/wind_rule_baseline_acceptance_20260616_095017.txt"
DEFAULT_FOUR_VEHICLE_SUMMARY="data/results/four_vehicle_dry_run_acceptance_20260616_090911/four_vehicle_dry_run_acceptance_20260616_090911.txt"
DEFAULT_PROJECT_SUMMARY="data/results/project_current_acceptance_20260617_085710/project_current_acceptance_20260617_085710.txt"
DEFAULT_READINESS_SUMMARY="data/results/cable_active_readiness_snapshot_20260617_172343/cable_active_readiness_snapshot_20260617_172343.txt"
DEFAULT_APPROVAL_MANIFEST="docs/28_cable_active_approval_manifest.md"
DEFAULT_HANDOFF_BUNDLE="docs/29_cable_active_handoff_bundle.md"
DEFAULT_FOURVIEW_UNION_SUMMARY="data/results/cable_fourview_surface_union_offline_20260618_131943/cable_fourview_surface_union_offline_20260618_131943.txt"
DEFAULT_FOURVIEW_ATTITUDE_SUMMARY="data/results/cable_fourview_attitude_feasibility_20260618_132059/cable_fourview_attitude_feasibility_20260618_132059.txt"
CABLE_DRY_RUN_SUMMARY="${CABLE_DRY_RUN_SUMMARY:-${DEFAULT_CABLE_DRY_RUN_SUMMARY}}"
CABLE_VISUAL_SUMMARY="${CABLE_VISUAL_SUMMARY:-${DEFAULT_CABLE_VISUAL_SUMMARY}}"
CABLE_SURFACE_SUMMARY="${CABLE_SURFACE_SUMMARY:-${DEFAULT_CABLE_SURFACE_SUMMARY}}"
WIND_SUMMARY="${WIND_SUMMARY:-${DEFAULT_WIND_SUMMARY}}"
FOUR_VEHICLE_SUMMARY="${FOUR_VEHICLE_SUMMARY:-${DEFAULT_FOUR_VEHICLE_SUMMARY}}"
PROJECT_SUMMARY="${PROJECT_SUMMARY:-${DEFAULT_PROJECT_SUMMARY}}"
READINESS_SUMMARY="${READINESS_SUMMARY:-${DEFAULT_READINESS_SUMMARY}}"
APPROVAL_MANIFEST="${APPROVAL_MANIFEST:-${DEFAULT_APPROVAL_MANIFEST}}"
HANDOFF_BUNDLE="${HANDOFF_BUNDLE:-${DEFAULT_HANDOFF_BUNDLE}}"
FOURVIEW_UNION_SUMMARY="${FOURVIEW_UNION_SUMMARY:-${DEFAULT_FOURVIEW_UNION_SUMMARY}}"
FOURVIEW_ATTITUDE_SUMMARY="${FOURVIEW_ATTITUDE_SUMMARY:-${DEFAULT_FOURVIEW_ATTITUDE_SUMMARY}}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/current_evidence_matrix_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/current_evidence_matrix_${STAMP}.txt"
MATRIX_CSV="${RESULT_DIR}/current_evidence_matrix_${STAMP}.csv"

for file in "${CABLE_DRY_RUN_SUMMARY}" "${CABLE_VISUAL_SUMMARY}" "${CABLE_SURFACE_SUMMARY}" "${WIND_SUMMARY}" "${FOUR_VEHICLE_SUMMARY}" "${PROJECT_SUMMARY}" "${READINESS_SUMMARY}" "${APPROVAL_MANIFEST}" "${HANDOFF_BUNDLE}" "${FOURVIEW_UNION_SUMMARY}" "${FOURVIEW_ATTITUDE_SUMMARY}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required aggregate summary does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${CABLE_DRY_RUN_SUMMARY}" "${CABLE_VISUAL_SUMMARY}" "${CABLE_SURFACE_SUMMARY}" "${WIND_SUMMARY}" \
  "${FOUR_VEHICLE_SUMMARY}" "${PROJECT_SUMMARY}" "${READINESS_SUMMARY}" "${APPROVAL_MANIFEST}" "${HANDOFF_BUNDLE}" \
  "${FOURVIEW_UNION_SUMMARY}" "${FOURVIEW_ATTITUDE_SUMMARY}" "${MATRIX_CSV}" >"${SUMMARY_FILE}" <<'PY'
import csv
import os
import sys

(
    cable_dry_run_summary,
    cable_visual_summary,
    cable_surface_summary,
    wind_summary,
    four_vehicle_summary,
    project_summary,
    readiness_summary,
    approval_manifest,
    handoff_bundle,
    fourview_union_summary,
    fourview_attitude_summary,
    matrix_csv,
) = sys.argv[1:13]


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


cable = load_kv(cable_dry_run_summary)
cable_visual = load_kv(cable_visual_summary)
cable_surface = load_kv(cable_surface_summary)
wind = load_kv(wind_summary)
four = load_kv(four_vehicle_summary)
project = load_kv(project_summary)
readiness = load_kv(readiness_summary)
fourview_union = load_kv(fourview_union_summary)
fourview_attitude = load_kv(fourview_attitude_summary)

cable_ok = (
    cable.get("decision") == "accepted_cable_dry_run_acceptance"
    and cable.get("tracking_ok") == "true"
    and cable.get("frame_ok") == "true"
    and cable.get("coverage_ok") == "true"
    and cable.get("line_segment_ok") == "true"
    and cable.get("boundary_ok") == "true"
)
cable_visual_ok = (
    cable_visual.get("decision") == "accepted_cable_visual_acceptance"
    and cable_visual.get("dry_run_ok") == "true"
    and cable_visual.get("overlay_boundary_ok") == "true"
    and cable_visual.get("overlay_content_ok") == "true"
)
cable_surface_ok = (
    cable_surface.get("decision") == "accepted_cable_surface_current_acceptance"
    and cable_surface.get("c1_visible_side_ok") == "true"
    and cable_surface.get("c2_candidate_ok") == "true"
    and cable_surface.get("c2_union_ok") == "true"
    and cable_surface.get("occlusion_ok") == "true"
    and cable_surface.get("dry_run_ok") == "true"
    and cable_surface.get("final_claim_blocked") == "true"
    and cable_surface.get("claims_final_cable_inspection_coverage") == "false"
)
wind_ok = (
    wind.get("decision") == "accepted_wind_rule_baseline_acceptance"
    and wind.get("capture_ok") == "true"
    and wind.get("dynamic_ok") == "true"
    and wind.get("occlusion_ok") == "true"
    and wind.get("loop_ok") == "true"
    and wind.get("mapping_boundary_ok") == "true"
    and wind.get("claims_final_inspection_coverage") == "false"
)
four_ok = (
    four.get("decision") == "accepted_four_vehicle_dry_run_acceptance"
    and four.get("readonly_ok") == "true"
    and four.get("contract_ok") == "true"
    and four.get("smoke_ok") == "true"
    and four.get("samples_ok") == "true"
    and four.get("score_ok") == "true"
    and four.get("assignment_topology_ok") == "true"
    and four.get("claims_multi_vehicle_active_approval") == "false"
)
project_ok = (
    project.get("decision") == "accepted_project_current_acceptance"
    and project.get("cable_dry_run_ok") == "true"
    and project.get("wind_rule_baseline_ok") == "true"
    and project.get("four_vehicle_dry_run_ok") == "true"
)

rows = [
    {
        "area": "cable",
        "capability": "geometry_tracking_lookahead_dry_run",
        "status": "accepted" if cable_ok else "rejected",
        "evidence": cable_dry_run_summary,
        "claim": "5 wire groups, frame contract, dry-run coverage monitor, and line-segment arc coverage are accepted",
        "non_claim": "not active PX4 control; not final cable inspection coverage; not defect detection",
        "starts_active_control": "false",
        "publishes_fmu_in": cable.get("publishes_fmu_in", "unknown"),
        "source_may_have_active_control": "false",
    },
    {
        "area": "cable",
        "capability": "all_groups_rviz_visual_evidence",
        "status": "accepted" if cable_visual_ok else "rejected",
        "evidence": cable_visual_summary,
        "claim": "all accepted cable groups and lookahead targets have RViz overlay evidence",
        "non_claim": "not Gazebo/PX4 execution evidence; not final inspection coverage",
        "starts_active_control": "false",
        "publishes_fmu_in": cable_visual.get("publishes_fmu_in", "unknown"),
        "source_may_have_active_control": "false",
    },
    {
        "area": "cable",
        "capability": "surface_progression_visible_side_and_multiview_offline",
        "status": "accepted" if cable_surface_ok else "rejected",
        "evidence": cable_surface_summary,
        "claim": "visible-side C1, side-A/side-B multiview C2, and AerialCore-mesh occlusion gate are accepted",
        "non_claim": "not active PX4 control; not final cable inspection coverage; not real trajectory certification",
        "starts_active_control": "false",
        "publishes_fmu_in": cable_surface.get("publishes_fmu_in", "unknown"),
        "source_may_have_active_control": "false",
    },
    {
        "area": "wind",
        "capability": "single_vehicle_rule_baseline_motion_mapping_coverage",
        "status": "accepted" if wind_ok else "rejected",
        "evidence": wind_summary,
        "claim": "single-vehicle wind rule baseline has motion, mapping, loop, and sampled occlusion coverage evidence",
        "non_claim": "not final inspection coverage; not cable active bridge; not multi-vehicle active approval",
        "starts_active_control": "false",
        "publishes_fmu_in": wind.get("publishes_fmu_in", "unknown"),
        "source_may_have_active_control": wind.get("source_capture_published_fmu_in", "unknown"),
    },
    {
        "area": "multi_vehicle",
        "capability": "four_vehicle_assignment_topology_scoring_dry_run",
        "status": "accepted" if four_ok else "rejected",
        "evidence": four_vehicle_summary,
        "claim": "four-vehicle read-only/dry-run topology, assignment, scoring, and RViz evidence are accepted",
        "non_claim": "not multi-vehicle active Offboard; not learned policy; not cable active tracking",
        "starts_active_control": "false",
        "publishes_fmu_in": four.get("publishes_fmu_in", "unknown"),
        "source_may_have_active_control": four.get("source_smoke_published_fmu_in", "unknown"),
    },
    {
        "area": "project",
        "capability": "current_integrated_status",
        "status": "accepted" if project_ok else "rejected",
        "evidence": project_summary,
        "claim": "current cable, wind, and four-vehicle aggregate evidence all pass",
        "non_claim": "not RL policy control; not image-level defect detection; not active multi-vehicle control",
        "starts_active_control": "false",
        "publishes_fmu_in": project.get("publishes_fmu_in", "unknown"),
        "source_may_have_active_control": "mixed",
    },
    {
        "area": "cable",
        "capability": "active_readiness_snapshot_packaged",
        "status": "accepted" if (
            readiness.get("decision") == "accepted_cable_active_readiness_snapshot"
            and readiness.get("ready_for_review") == "true"
            and readiness.get("active_control_approved") == "false"
            and readiness.get("phase_b_user_approved") == "false"
            and readiness.get("publishes_fmu_in") == "false"
        ) else "rejected",
        "evidence": readiness_summary,
        "claim": "single-vehicle cable active path is packaged, frozen, and explicitly inactive",
        "non_claim": "not active PX4 control; not approval to publish /fmu/in/*; not final cable traversal",
        "starts_active_control": "false",
        "publishes_fmu_in": "false",
        "source_may_have_active_control": "false",
    },
    {
        "area": "cable",
        "capability": "active_approval_manifest_frozen",
        "status": "accepted" if os.path.isfile(approval_manifest) else "rejected",
        "evidence": approval_manifest,
        "claim": "approval wording for the frozen single-vehicle cable active path is documented and remains blocked",
        "non_claim": "not active approval; not permission to publish /fmu/in/*",
        "starts_active_control": "false",
        "publishes_fmu_in": "false",
        "source_may_have_active_control": "false",
    },
    {
        "area": "cable",
        "capability": "active_handoff_bundle_frozen",
        "status": "accepted" if (
            os.path.isfile(handoff_bundle)
        ) else "rejected",
        "evidence": handoff_bundle,
        "claim": "review package, scenario freeze, readiness snapshot, approval manifest, matrix and inventory are bundled",
        "non_claim": "not active approval; not permission to publish /fmu/in/*",
        "starts_active_control": "false",
        "publishes_fmu_in": "false",
        "source_may_have_active_control": "false",
    },
    {
        "area": "cable",
        "capability": "fourview_surface_progression_offline",
        "status": "accepted" if (
            fourview_union.get("decision") == "accepted_cable_fourview_surface_union_offline"
            and fourview_union.get("meets_total_surface_target") == "true"
            and fourview_union.get("claims_final_cable_inspection_coverage") == "false"
            and fourview_attitude.get("decision") == "accepted_cable_fourview_attitude_feasibility"
            and fourview_attitude.get("requires_gimbal_or_attitude_review") == "true"
            and fourview_attitude.get("claims_active_control_approval") == "false"
        ) else "rejected",
        "evidence": fourview_union_summary,
        "claim": "four-view offline geometry reaches the total-surface upper-bound target while attitude feasibility remains gated",
        "non_claim": "not active PX4 control; not physical camera/gimbal approval; not final cable inspection coverage",
        "starts_active_control": "false",
        "publishes_fmu_in": "false",
        "source_may_have_active_control": "false",
    },
]

forbidden_rows = [
    {
        "area": "forbidden",
        "capability": "cable_phase_b_active_bridge",
        "status": "not_approved",
        "evidence": project_summary,
        "claim": "no current approval",
        "non_claim": "must not implement or run without explicit user approval",
        "starts_active_control": "true",
        "publishes_fmu_in": "would_publish_if_implemented",
        "source_may_have_active_control": "not_applicable",
    },
    {
        "area": "forbidden",
        "capability": "multi_vehicle_active_offboard",
        "status": "not_approved",
        "evidence": project_summary,
        "claim": "no current approval",
        "non_claim": "four-vehicle work remains read-only/dry-run",
        "starts_active_control": "true",
        "publishes_fmu_in": "would_publish_if_implemented",
        "source_may_have_active_control": "not_applicable",
    },
    {
        "area": "forbidden",
        "capability": "rl_policy_control",
        "status": "not_implemented",
        "evidence": project_summary,
        "claim": "rule baselines only",
        "non_claim": "no learned policy controls PX4 or task allocation",
        "starts_active_control": "unknown",
        "publishes_fmu_in": "unknown",
        "source_may_have_active_control": "not_applicable",
    },
    {
        "area": "forbidden",
        "capability": "image_level_defect_detection",
        "status": "not_implemented",
        "evidence": project_summary,
        "claim": "not in current project capability",
        "non_claim": "no defect recognition model or defect dataset evidence",
        "starts_active_control": "false",
        "publishes_fmu_in": "false",
        "source_may_have_active_control": "not_applicable",
    },
]

all_rows = rows + forbidden_rows
fieldnames = [
    "area",
    "capability",
    "status",
    "evidence",
    "claim",
    "non_claim",
    "starts_active_control",
    "publishes_fmu_in",
    "source_may_have_active_control",
]
with open(matrix_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(all_rows)

accepted_rows = sum(1 for row in rows if row["status"] == "accepted")
forbidden_count = len(forbidden_rows)
forbidden_not_enabled = all(row["status"] in {"not_approved", "not_implemented"} for row in forbidden_rows)
accepted = accepted_rows == len(rows) and forbidden_not_enabled
decision = "accepted_current_evidence_matrix" if accepted else "rejected_current_evidence_matrix"
reason = "current_positive_capabilities_and_forbidden_boundaries_are_explicit" if accepted else "one_or_more_current_capabilities_or_boundaries_failed"

print("scope=current_evidence_matrix")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"matrix_csv={matrix_csv}")
print(f"cable_dry_run_summary={cable_dry_run_summary}")
print(f"cable_visual_summary={cable_visual_summary}")
print(f"cable_surface_summary={cable_surface_summary}")
print(f"wind_summary={wind_summary}")
print(f"four_vehicle_summary={four_vehicle_summary}")
print(f"project_summary={project_summary}")
print(f"positive_capability_count={len(rows)}")
print(f"accepted_positive_capability_count={accepted_rows}")
print(f"forbidden_capability_count={forbidden_count}")
print(f"forbidden_not_enabled={str(forbidden_not_enabled).lower()}")
print(f"claims_current_evidence_matrix_pass={str(accepted).lower()}")
PY

echo "Current evidence matrix audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Matrix CSV: ${MATRIX_CSV}"

grep -q "decision=accepted_current_evidence_matrix" "${SUMMARY_FILE}"
