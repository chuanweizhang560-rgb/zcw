# Evidence Inventory

This document records how ignored local evidence is tracked.

It does not approve Phase B execution.

## 1. Purpose

Most runtime evidence is intentionally ignored by git:

- `data/logs/*`
- `data/results/*`
- `data/screenshots/*`

That keeps the repository small, but it means a fresh checkout does not contain screenshots, ROS topic echoes, PX4 logs or audit result files. The inventory audit checks whether the required local proof files for the current dry-run boundary are still present on this machine.

The same audit also tracks the current wind turbine rule-baseline proof files. Those wind evidence files may include Offboard/GUI artifacts, but the inventory audit itself only checks local file presence and git-ignore status.

## 2. Audit Command

```bash
scripts/audit_evidence_inventory.sh
```

The audit is allowed to:

- inspect local files under `data/`.
- check whether evidence paths are ignored by git.
- write its own summary under `data/results/`.

The audit is not allowed to:

- start ROS, PX4, Gazebo or RViz.
- start Offboard.
- arm.
- publish `/fmu/in/*`.
- create active bridge code.

## 3. Required Evidence Groups

| Group | Evidence | Regeneration entry |
|---|---|---|
| Phase A bridge dry-run | bridge state topic echo and RViz screenshot | `scripts/verify_px4_bridge_dry_run_isolation.sh`, `scripts/capture_px4_bridge_dry_run_rviz_overlay.sh` |
| PX4/Gazebo read-only frame sample | frame alignment summary | `scripts/verify_px4_gazebo_readonly_frame_alignment.sh` |
| Offboard gate dry-run | gate summary, forbidden publisher log, RViz summary, RViz screenshot | `scripts/verify_cable_offboard_gate_dry_run.sh`, `scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh` |
| Offboard gate dry-run refreshed overlay | refreshed RViz summary and screenshot | `scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh` |
| Cable active readiness snapshot | packaged frozen-path readiness summary | `scripts/audit_cable_active_readiness_snapshot.sh` |
| Cable path inputs | offset path CSV and lookahead target CSV | `scripts/audit_catenary_fit.sh`, `scripts/audit_offset_path.sh`, `scripts/audit_lookahead_target.sh` |
| Cable path geometry audit | offset path and lookahead target consistency summary | `scripts/audit_cable_path_geometry.sh` |
| Cable Frenet consistency audit | offset path and lookahead target Frenet consistency summary | `scripts/audit_cable_frenet_consistency.sh` |
| Cable frame contract audit | centerline, offset path and lookahead target frame-contract summary | `scripts/audit_cable_frame_contract.sh` |
| Cable line-segment coverage audit | all-groups lookahead segment arc-coverage summary, current/target point error and forward-dot checks | `scripts/audit_cable_line_segment_coverage.sh` |
| Cable dry-run acceptance audit | aggregate tracking, frame-contract, coverage-monitor and line-segment coverage threshold summary | `scripts/audit_cable_dry_run_acceptance.sh` |
| Cable lookahead sweep | multi-lookahead summary and CSV | `scripts/audit_lookahead_distance_sweep.sh` |
| Cable dry-run coverage monitor | coverage monitor summary, topic list and coverage state echo | `scripts/verify_lookahead_coverage_monitor.sh`, `scripts/audit_lookahead_coverage_monitor_all_groups.sh` |
| Cable all-groups RViz overlay | all accepted cable groups rendered as MarkerArray in RViz, with no PX4/Gazebo/Offboard path | `scripts/capture_cable_all_groups_rviz_overlay.sh` |
| Cable visual acceptance audit | aggregate cable dry-run acceptance and all-groups RViz overlay summary | `scripts/audit_cable_visual_acceptance.sh` |
| Cable acceptance threshold contract | threshold/non-claim documentation matched to the aggregate cable dry-run audit defaults | `scripts/audit_cable_acceptance_threshold_contract.sh` |
| Cable surface current acceptance | aggregate C1/C2 cable surface progression and dry-run boundary summary | `scripts/audit_cable_surface_current_acceptance.sh` |
| Cable multiview surface occlusion | AerialCore two-tower collision-mesh ray intersection surface gate | `scripts/audit_cable_multiview_surface_occlusion_offline.sh` |
| Cable four-view surface progression | four-view union upper-bound and attitude feasibility summaries | `scripts/audit_cable_fourview_surface_union_offline.sh`, `scripts/audit_cable_fourview_attitude_feasibility.sh` |
| Cable AerialCore GUI screenshot | Gazebo GUI scene-start screenshot for the two-tower cable world | `scripts/capture_px4_aerialcore_world_gui.sh` |
| Active threshold inputs | gate state echo and approved NED dry-run echo | `scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh` |
| Wind turbine multilevel static geometry | static summary and waypoint CSV | `scripts/audit_wind_turbine_multilevel_orbit_launch.sh` |
| Wind turbine multilevel headless Offboard | control log, vehicle status and local position echo | `scripts/verify_wind_turbine_multilevel_orbit.sh` |
| Wind turbine multilevel GUI motion evidence | Gazebo screenshot, window id, Offboard log, vehicle status and local position echo | `scripts/capture_wind_turbine_multilevel_orbit_gui.sh` |
| Wind rule-baseline acceptance | aggregate multi-level slow-loop motion, coverage, SLAM and mapping evidence summary | `scripts/audit_wind_rule_baseline_acceptance.sh` |
| Wind acceptance threshold contract | threshold/non-claim documentation matched to the aggregate wind audit defaults | `scripts/audit_wind_acceptance_threshold_contract.sh` |
| Four-vehicle dry-run acceptance | aggregate read-only namespace, contract, smoke, samples and score-sweep summary | `scripts/audit_four_vehicle_dry_run_acceptance.sh` |
| Four-vehicle assignment/topology sweep | offline topology and fixed-role boundary summary | `scripts/audit_four_vehicle_assignment_topology_sweep.sh` |
| Project current acceptance | aggregate current cable, wind and four-vehicle acceptance summary | `scripts/audit_project_current_acceptance.sh` |
| Current evidence matrix | machine-checkable positive claims, non-claims and forbidden capabilities | `scripts/audit_current_evidence_matrix.sh` |

## 4. Latest Result

Latest evidence:

- summary: `data/results/evidence_inventory_20260617_090429/evidence_inventory_20260617_090429.txt`
- inventory CSV: `data/results/evidence_inventory_20260617_090429/evidence_inventory_20260617_090429.csv`
- regeneration list: `data/results/evidence_inventory_20260617_090429/evidence_regeneration_20260617_090429.txt`

Expected accepted fields:

```text
decision=accepted_evidence_inventory
starts_ros=false
starts_px4=false
starts_gazebo=false
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
missing_count=0
not_ignored_count=0
```

Latest accepted result:

- `required_evidence_count=35`
- `present_count=35`
- `missing_count=0`
- `not_ignored_count=0`

Fresh local evidence since that accepted run:

- summary: `data/results/cable_offboard_gate_rviz_overlay_20260617_171815/cable_offboard_gate_rviz_overlay_20260617_171815.txt`
- screenshot: `data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260617_171815.png`
- accepted fields: `decision=accepted_cable_offboard_gate_rviz_overlay_capture`, `phase_b_allowed=false`, `publishes_fmu_in=false`
- readiness snapshot: `data/results/cable_active_readiness_snapshot_20260617_172343/cable_active_readiness_snapshot_20260617_172343.txt`
- readiness accepted fields: `decision=accepted_cable_active_readiness_snapshot`, `ready_for_review=true`, `active_control_approved=false`, `phase_b_user_approved=false`, `publishes_fmu_in=false`
- four-view union summary: `data/results/cable_fourview_surface_union_offline_20260618_131943/cable_fourview_surface_union_offline_20260618_131943.txt`
- four-view attitude summary: `data/results/cable_fourview_attitude_feasibility_20260618_132059/cable_fourview_attitude_feasibility_20260618_132059.txt`

Additional latest local cable coverage evidence:

- summary: `data/results/lookahead_coverage_monitor_20260615_094950/lookahead_coverage_monitor_20260615_094950.txt`
- coverage echo: `data/logs/lookahead_coverage_state_echo_20260615_094950.log`
- topic list: `data/logs/lookahead_coverage_topic_list_20260615_094950.log`
- accepted fields: `decision=accepted_lookahead_coverage_monitor`, `coverage_ratio=0.84`, `coverage_ready=true`, `publishes_fmu_in=false`
- all-groups summary: `data/results/lookahead_coverage_monitor_all_groups_20260615_100351/lookahead_coverage_monitor_all_groups_20260615_100351.txt`
- all-groups CSV: `data/results/lookahead_coverage_monitor_all_groups_20260615_100351/lookahead_coverage_monitor_all_groups_20260615_100351.csv`
- all-groups accepted fields: `decision=accepted_lookahead_coverage_monitor_all_groups`, `group_count=5`, `accepted_group_count=5`, each group `coverage_ratio=0.84`
- frame-contract summary: `data/results/cable_frame_contract_20260615_100822/cable_frame_contract_20260615_100822.txt`
- frame-contract CSV: `data/results/cable_frame_contract_20260615_100822/cable_frame_contract_groups_20260615_100822.csv`
- frame-contract accepted fields: `decision=accepted_cable_frame_contract_audit`, `accepted_group_count=5`, `global_max_target_point_error_m=0.000000000`, `global_max_lookahead_error_m=0.001200000`
- line-segment coverage summary: `data/results/cable_line_segment_coverage_20260617_085604/cable_line_segment_coverage_20260617_085604.txt`
- line-segment coverage fields: `decision=accepted_cable_line_segment_coverage`, `accepted_group_count=5`, `total_path_length_m=600.011818322`, `global_min_arc_coverage_ratio=1.000000000`, `global_min_segment_forward_dot=0.999999495`, `claims_final_inspection_coverage=false`
- dry-run acceptance summary: `data/results/cable_dry_run_acceptance_20260617_085648/cable_dry_run_acceptance_20260617_085648.txt`
- dry-run acceptance fields: `decision=accepted_cable_dry_run_acceptance`, `tracking_ok=true`, `frame_ok=true`, `coverage_ok=true`, `line_segment_ok=true`, `boundary_ok=true`
- cable threshold contract summary: `data/results/cable_acceptance_threshold_contract_20260616_152304/cable_acceptance_threshold_contract_20260616_152304.txt`
- cable threshold contract fields: `decision=accepted_cable_acceptance_threshold_contract`, `check_count=11`, `fail_count=0`, `claims_active_control_approval=false`, `claims_final_inspection_coverage=false`
- cable surface occlusion summary: `data/results/cable_multiview_surface_occlusion_offline_20260617_162441/cable_multiview_surface_occlusion_offline_20260617_162441.txt`
- cable surface occlusion fields: `decision=accepted_cable_multiview_surface_occlusion_offline`, `uses_real_aerialcore_collision_mesh=true`, `ray_tests=1750`, `global_min_occlusion_clear_total_surface_ratio=0.875000000`, `claims_cable_multiview_surface_occlusion_offline_pass=true`
- cable surface current acceptance summary: `data/results/cable_surface_current_acceptance_20260617_163650/cable_surface_current_acceptance_20260617_163650.txt`
- cable surface current acceptance fields: `decision=accepted_cable_surface_current_acceptance`, `c1_visible_side_ok=true`, `c2_candidate_ok=true`, `c2_union_ok=true`, `occlusion_ok=true`, `dry_run_ok=true`, `final_claim_blocked=true`, `claims_cable_surface_progression_current_acceptance_pass=true`
- cable AerialCore GUI screenshot: `data/screenshots/px4_aerialcore_danube_wires_gui_20260617_162903.png`

Additional latest local wind rule-baseline evidence:

- wind rule-baseline acceptance summary: `data/results/wind_rule_baseline_acceptance_20260616_095017/wind_rule_baseline_acceptance_20260616_095017.txt`
- wind rule-baseline accepted fields: `decision=accepted_wind_rule_baseline_acceptance`, `capture_ok=true`, `dynamic_ok=true`, `occlusion_ok=true`, `loop_ok=true`, `mapping_boundary_ok=true`, `claims_wind_rule_baseline_acceptance_pass=true`

Additional latest local four-vehicle dry-run evidence:

- four-vehicle dry-run acceptance summary: `data/results/four_vehicle_dry_run_acceptance_20260616_090911/four_vehicle_dry_run_acceptance_20260616_090911.txt`
- four-vehicle dry-run accepted fields: `decision=accepted_four_vehicle_dry_run_acceptance`, `readonly_ok=true`, `contract_ok=true`, `smoke_ok=true`, `samples_ok=true`, `score_ok=true`, `assignment_topology_ok=true`, `claims_multi_vehicle_active_approval=false`
- four-vehicle assignment/topology sweep summary: `data/results/four_vehicle_assignment_topology_sweep_20260616_090752/four_vehicle_assignment_topology_sweep_20260616_090752.txt`
- four-vehicle assignment/topology accepted fields: `decision=accepted_four_vehicle_assignment_topology_sweep`, `cases=11`, `chain_just_over_rejected=true`, `base_just_over_rejected=true`, `roles_fixed=true`

Additional latest local project aggregate evidence:

- project current acceptance summary: `data/results/project_current_acceptance_20260617_085710/project_current_acceptance_20260617_085710.txt`
- project current accepted fields: `decision=accepted_project_current_acceptance`, `cable_dry_run_ok=true`, `wind_rule_baseline_ok=true`, `four_vehicle_dry_run_ok=true`, `claims_project_current_acceptance_pass=true`
- current evidence matrix summary: `data/results/current_evidence_matrix_20260617_090333/current_evidence_matrix_20260617_090333.txt`
- current evidence matrix fields: `decision=accepted_current_evidence_matrix`, `accepted_positive_capability_count=6`, `forbidden_capability_count=4`, `forbidden_not_enabled=true`, `claims_current_evidence_matrix_pass=true`
- refreshed current evidence matrix summary: `data/results/current_evidence_matrix_20260617_163839/current_evidence_matrix_20260617_163839.txt`
- refreshed evidence inventory summary: `data/results/evidence_inventory_20260617_163850/evidence_inventory_20260617_163850.txt`

## 5. Regeneration Rule

If the inventory rejects because an ignored evidence file is missing, regenerate only the missing group.

Visual evidence should be regenerated with real Gazebo/RViz/PCL screenshots when the script requires display access. Do not replace it with diagrams or hand-made images.

The inventory audit itself is only a file audit. It does not prove the simulation still runs; it proves the current local evidence set is still complete enough for the dry-run readiness boundary.
