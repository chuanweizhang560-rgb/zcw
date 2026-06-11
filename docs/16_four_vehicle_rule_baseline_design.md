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

## 5. M2 ROS Graph Smoke

M2 requirements:

- Start four PX4/Gazebo Classic read-only instances.
- Start `four_vehicle_dry_run_planner`.
- Verify dry-run goal/topology/safety/assignment topics publish.
- Verify key `/px4_i/fmu/in/*` publisher counts remain `0`.
- Capture full-length dry-run samples and run an offline sample audit.

Latest M2 evidence:

- smoke script: `scripts/verify_four_vehicle_dry_run_smoke.sh`
- smoke summary: `data/results/four_vehicle_dry_run_smoke_20260611_142737/four_vehicle_dry_run_smoke_20260611_142737.txt`
- dry-run samples: `data/logs/four_vehicle_dry_run_samples_20260611_142737.log`
- forbidden publishers: `data/logs/four_vehicle_dry_run_forbidden_publishers_20260611_142737.log`
- samples audit script: `scripts/audit_four_vehicle_dry_run_samples.sh`
- samples audit summary: `data/results/four_vehicle_dry_run_samples_audit_20260611_142923/four_vehicle_dry_run_samples_audit_20260611_142923.txt`

Observed M2 result:

```text
decision=accepted_four_vehicle_dry_run_smoke
starts_ros=true
starts_px4=true
starts_gazebo=true
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
num_vehicles=4
dry_topics_ok=true
forbidden_publishers_zero=true
```

Observed sample audit result:

```text
decision=accepted_four_vehicle_dry_run_samples_audit
has_all_goals=true
has_topology=true
has_safety=true
has_assignment=true
has_rule_baseline=true
has_no_learned_policy=true
has_no_active=true
has_no_fmu_in=true
has_valid_topology_distance=true
has_roles=true
```

Representative assignment sample:

```text
FOUR_RULE_BASELINE_DRY_RUN; dry_run=true; learned_policy=false; starts_offboard=false; arms=false; publishes_fmu_in=false; vehicle_1_role=wind_inspection_candidate; vehicle_2_role=cable_inspection_candidate; vehicle_3_role=relay_candidate; vehicle_4_role=relay_candidate; topology_ready=true; safety_ready=true
```

## 6. M3 RViz Overlay

M3 requirements:

- Reuse the accepted M2 smoke boundary.
- Start RViz only for visualization.
- Display all four dry-run goal topics.
- Capture a real RViz screenshot.
- Keep `/px4_i/fmu/in/*` publisher counts at `0`.

Latest M3 evidence:

- RViz config: `ros2_ws/src/zcw_cable_perception/rviz/four_vehicle_dry_run_overlay.rviz`
- command: `CAPTURE_RVIZ=1 RVIZ_SETTLE_SEC=10 scripts/verify_four_vehicle_dry_run_smoke.sh`
- summary: `data/results/four_vehicle_dry_run_smoke_20260611_143238/four_vehicle_dry_run_smoke_20260611_143238.txt`
- screenshot: `data/screenshots/four_vehicle_dry_run_overlay_20260611_143238.png`
- forbidden publishers: `data/logs/four_vehicle_dry_run_forbidden_publishers_20260611_143238.log`
- RViz log: `data/logs/four_vehicle_dry_run_rviz_20260611_143238.log`

Observed M3 result:

```text
decision=accepted_four_vehicle_dry_run_smoke
starts_rviz=true
starts_offboard=false
arms=false
publishes_fmu_in=false
dry_topics_ok=true
forbidden_publishers_zero=true
capture_rviz=1
screenshot_ok=1
```

Manual screenshot review:

- RViz screenshot is non-empty: `2480x1522`, mean pixel value `21573`.
- Four dry-run goal displays are enabled.
- Four colored dry-run goal points are visible on the grid.

## 7. Promotion Criteria

Four-vehicle active control may only be considered after all of these exist:

- accepted M1 static contract audit.
- accepted four-vehicle read-only smoke.
- accepted four-vehicle dry-run ROS graph smoke.
- accepted four-vehicle RViz overlay.
- documented user approval for a four-vehicle active review.

Until then, four-vehicle work remains dry-run/read-only.
