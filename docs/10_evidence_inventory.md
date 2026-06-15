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
| Cable path inputs | offset path CSV and lookahead target CSV | `scripts/audit_catenary_fit.sh`, `scripts/audit_offset_path.sh`, `scripts/audit_lookahead_target.sh` |
| Cable path geometry audit | offset path and lookahead target consistency summary | `scripts/audit_cable_path_geometry.sh` |
| Cable Frenet consistency audit | offset path and lookahead target Frenet consistency summary | `scripts/audit_cable_frenet_consistency.sh` |
| Cable frame contract audit | centerline, offset path and lookahead target frame-contract summary | `scripts/audit_cable_frame_contract.sh` |
| Cable lookahead sweep | multi-lookahead summary and CSV | `scripts/audit_lookahead_distance_sweep.sh` |
| Cable dry-run coverage monitor | coverage monitor summary, topic list and coverage state echo | `scripts/verify_lookahead_coverage_monitor.sh`, `scripts/audit_lookahead_coverage_monitor_all_groups.sh` |
| Active threshold inputs | gate state echo and approved NED dry-run echo | `scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh` |
| Wind turbine multilevel static geometry | static summary and waypoint CSV | `scripts/audit_wind_turbine_multilevel_orbit_launch.sh` |
| Wind turbine multilevel headless Offboard | control log, vehicle status and local position echo | `scripts/verify_wind_turbine_multilevel_orbit.sh` |
| Wind turbine multilevel GUI motion evidence | Gazebo screenshot, window id, Offboard log, vehicle status and local position echo | `scripts/capture_wind_turbine_multilevel_orbit_gui.sh` |

## 4. Latest Result

Latest evidence:

- summary: `data/results/evidence_inventory_20260604_140426/evidence_inventory_20260604_140426.txt`
- inventory CSV: `data/results/evidence_inventory_20260604_140426/evidence_inventory_20260604_140426.csv`
- regeneration list: `data/results/evidence_inventory_20260604_140426/evidence_regeneration_20260604_140426.txt`

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

- `required_evidence_count=21`
- `present_count=21`
- `missing_count=0`
- `not_ignored_count=0`

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

## 5. Regeneration Rule

If the inventory rejects because an ignored evidence file is missing, regenerate only the missing group.

Visual evidence should be regenerated with real Gazebo/RViz/PCL screenshots when the script requires display access. Do not replace it with diagrams or hand-made images.

The inventory audit itself is only a file audit. It does not prove the simulation still runs; it proves the current local evidence set is still complete enough for the dry-run readiness boundary.
