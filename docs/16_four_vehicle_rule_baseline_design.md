# Four-Vehicle Rule Baseline Design

This document defines the first four-vehicle dry-run rule-baseline path.

It does not approve four-vehicle Offboard control, arming, RL, active relay control, active role assignment, or cable Phase B active bridge.

## 1. Preconditions

Accepted prerequisites:

- two-vehicle dry-run M1-M5 evidence is accepted in `docs/15_two_vehicle_rule_baseline_design.md`.
- four-vehicle read-only namespace smoke is accepted in `docs/12_multi_vehicle_readiness.md`.

Latest four-vehicle read-only evidence:

- summary: `data/results/multi_vehicle_readonly_20260609_111036/multi_vehicle_readonly_20260609_111036.txt`
- topics: `data/logs/multi_vehicle_topics_20260609_111036.log`
- forbidden publishers: `data/logs/multi_vehicle_forbidden_publishers_20260609_111036.log`

## 2. Hard Boundaries

The first four-vehicle rule-baseline implementation must stay below these boundaries:

- Do not publish to `/fmu/in/*` or `/px4_i/fmu/in/*`.
- Do not arm any vehicle.
- Do not request Offboard mode.
- Do not connect cable lookahead/gate outputs to PX4 active setpoints.
- Do not use RTAB-Map, coverage, or perception output for active control.
- Do not implement RL, MAPPO, learned role assignment, or active relay control.

## 3. First Dry-Run Scope

Inputs:

- `/px4_1/fmu/out/vehicle_local_position` and `/px4_1/fmu/out/vehicle_status`
- `/px4_2/fmu/out/vehicle_local_position` and `/px4_2/fmu/out/vehicle_status`
- `/px4_3/fmu/out/vehicle_local_position` and `/px4_3/fmu/out/vehicle_status`
- `/px4_4/fmu/out/vehicle_local_position` and `/px4_4/fmu/out/vehicle_status`

Outputs:

- `/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_1_goal`
- `/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_2_goal`
- `/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_3_goal`
- `/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_4_goal`
- `/zcw/multi_vehicle/four_vehicle_dry_run/topology_state`
- `/zcw/multi_vehicle/four_vehicle_dry_run/safety_state`
- `/zcw/multi_vehicle/four_vehicle_dry_run/assignment_state`

Initial dry-run role candidates:

- vehicle 1: `wind_inspection_candidate`
- vehicle 2: `cable_inspection_candidate`
- vehicle 3: `relay_candidate`
- vehicle 4: `relay_candidate`

These are rule-baseline debug labels only. They are not active policy outputs.

## 4. M1 Static Contract Audit

M1 requirements:

- source and launch exist.
- CMake installs the node.
- source subscribes only to `/px4_1` through `/px4_4` output topics.
- source publishes only `/zcw/multi_vehicle/four_vehicle_dry_run/*`.
- source/launch/CMake contain no PX4 input topic, Offboard, arm, cable active, or Phase B active hook.

Latest M1 evidence:

- source: `ros2_ws/src/zcw_px4_baseline/src/four_vehicle_dry_run_planner.cpp`
- launch: `ros2_ws/src/zcw_bringup/launch/four_vehicle_dry_run_planner.launch.py`
- audit script: `scripts/audit_four_vehicle_dry_run_contract.sh`
- summary: `data/results/four_vehicle_dry_run_contract_20260609_111711/four_vehicle_dry_run_contract_20260609_111711.txt`
- detail log: `data/results/four_vehicle_dry_run_contract_20260609_111711/four_vehicle_dry_run_contract_detail_20260609_111711.log`

Observed M1 result:

```text
decision=accepted_four_vehicle_dry_run_contract_static_audit
starts_ros=false
starts_px4=false
starts_gazebo=false
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
has_source_target=true
has_launch_node=true
has_allowed_outputs=true
has_allowed_inputs=true
forbidden_topics=false
forbidden_active_terms=false
```

## 5. Promotion Criteria

Four-vehicle active control may only be considered after all of these exist:

- accepted M1 static contract audit.
- accepted four-vehicle read-only smoke.
- accepted four-vehicle dry-run ROS graph smoke.
- accepted four-vehicle RViz overlay.
- documented user approval for a four-vehicle active review.

Until then, four-vehicle work remains dry-run/read-only.
