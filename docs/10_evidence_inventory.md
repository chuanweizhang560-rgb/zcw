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

## 5. Regeneration Rule

If the inventory rejects because an ignored evidence file is missing, regenerate only the missing group.

Visual evidence should be regenerated with real Gazebo/RViz/PCL screenshots when the script requires display access. Do not replace it with diagrams or hand-made images.

The inventory audit itself is only a file audit. It does not prove the simulation still runs; it proves the current local evidence set is still complete enough for the dry-run readiness boundary.
