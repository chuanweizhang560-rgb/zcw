# Two-Vehicle Rule Baseline Design

This document defines the first allowed two-vehicle rule-baseline path.

It does not approve two-vehicle Offboard control, arming, RL, role assignment, or cable Phase B active bridge.

## 1. Current Evidence

Accepted upstream/static evidence:

- `docs/12_multi_vehicle_readiness.md`
- `scripts/audit_multi_vehicle_upstream_readiness.sh`
- latest upstream summary: `data/results/multi_vehicle_upstream_readiness_20260604_140726/multi_vehicle_upstream_readiness_20260604_140726.txt`

Accepted refreshed two-vehicle read-only evidence:

- script: `scripts/verify_px4_gazebo_classic_multi_vehicle_readonly.sh`
- summary: `data/results/multi_vehicle_readonly_20260609_104248/multi_vehicle_readonly_20260609_104248.txt`
- topics log: `data/logs/multi_vehicle_topics_20260609_104248.log`
- forbidden publishers log: `data/logs/multi_vehicle_forbidden_publishers_20260609_104248.log`

Observed boundary:

```text
decision=accepted_multi_vehicle_readonly_smoke
starts_offboard=false
arms=false
publishes_fmu_in=false
observed_px4_1_vehicle_status=true
observed_px4_2_vehicle_status=true
forbidden_publishers_zero=true
```

## 2. Hard Boundaries

The first two-vehicle rule-baseline implementation must stay below these boundaries:

- Do not publish to `/fmu/in/*`, `/px4_1/fmu/in/*`, or `/px4_2/fmu/in/*`.
- Do not arm either vehicle.
- Do not request Offboard mode.
- Do not connect cable lookahead/gate outputs to PX4 active setpoints.
- Do not use RTAB-Map, coverage, or perception output for active control.
- Do not implement RL, MAPPO, role assignment, relay control, or learned policy logic.
- Do not start four vehicles until two-vehicle dry-run evidence is accepted.

## 3. First Rule-Baseline Scope

The first two-vehicle rule baseline should be a dry-run planner only.

Inputs:

- `/px4_1/fmu/out/vehicle_local_position`
- `/px4_2/fmu/out/vehicle_local_position`
- optional `/px4_1/fmu/out/vehicle_status`
- optional `/px4_2/fmu/out/vehicle_status`
- static task anchors from existing wind/cable geometry documents

Outputs:

- `/zcw/multi_vehicle/dry_run/vehicle_1_goal`
- `/zcw/multi_vehicle/dry_run/vehicle_2_goal`
- `/zcw/multi_vehicle/dry_run/topology_state`
- `/zcw/multi_vehicle/dry_run/safety_state`
- `/zcw/multi_vehicle/dry_run/assignment_state`

Forbidden outputs:

- any PX4 input topic.
- any command topic that can be bridged to PX4 without a separate review.

## 4. Initial Behavior

The first dry-run behavior should be deliberately simple:

- Vehicle 1 is assigned an inspection candidate goal.
- Vehicle 2 is assigned a relay/standby candidate goal.
- The planner computes the Euclidean distance from each vehicle to its goal.
- The planner computes vehicle-to-vehicle distance.
- The planner computes each vehicle distance to the base point.
- The planner marks topology as ready only if both vehicles remain within a configured relay radius.
- The planner publishes a dry-run assignment state that declares rule-baseline roles only:
  `vehicle_1_role=inspection_candidate` and `vehicle_2_role=relay_candidate`.

Default constants:

```text
base_x=0.0
base_y=0.0
relay_radius_m=800.0
goal_acceptance_radius_m=5.0
max_state_age_sec=2.0
```

The first goal set may be synthetic and should be documented as dry-run only. It must not be sent to PX4.

## 5. Verification Plan

Stage M1: static contract audit.

- Verify the dry-run planner has no `px4_msgs` publisher for PX4 input topics.
- Verify launch files do not start Offboard or arm.
- Verify all output topic names are under `/zcw/multi_vehicle/dry_run/`.

Latest M1 evidence:

- node source: `ros2_ws/src/zcw_px4_baseline/src/two_vehicle_dry_run_planner.cpp`
- launch: `ros2_ws/src/zcw_bringup/launch/two_vehicle_dry_run_planner.launch.py`
- audit script: `scripts/audit_two_vehicle_dry_run_contract.sh`
- summary: `data/results/two_vehicle_dry_run_contract_20260609_104927/two_vehicle_dry_run_contract_20260609_104927.txt`
- detail log: `data/results/two_vehicle_dry_run_contract_20260609_104927/two_vehicle_dry_run_contract_detail_20260609_104927.log`

Observed M1 result:

```text
decision=accepted_two_vehicle_dry_run_contract_static_audit
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

Stage M2: read-only ROS graph smoke.

- Start two-vehicle read-only PX4/Gazebo using `scripts/verify_px4_gazebo_classic_multi_vehicle_readonly.sh` or a derived wrapper.
- Start the dry-run planner.
- Verify dry-run topics are published.
- Verify `/px4_1/fmu/in/*` and `/px4_2/fmu/in/*` publisher count remains `0`.

Latest M2 evidence:

- smoke script: `scripts/verify_two_vehicle_dry_run_smoke.sh`
- summary: `data/results/two_vehicle_dry_run_smoke_20260609_105232/two_vehicle_dry_run_smoke_20260609_105232.txt`
- dry-run samples: `data/logs/two_vehicle_dry_run_samples_20260609_105232.log`
- forbidden publishers: `data/logs/two_vehicle_dry_run_forbidden_publishers_20260609_105232.log`
- topics log: `data/logs/two_vehicle_dry_run_topics_20260609_105232.log`
- planner log: `data/logs/two_vehicle_dry_run_planner_20260609_105232.log`

Observed M2 result:

```text
decision=accepted_two_vehicle_dry_run_smoke
starts_ros=true
starts_px4=true
starts_gazebo=true
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
dry_topics_ok=true
forbidden_publishers_zero=true
observed_px4_1_vehicle_status=true
observed_px4_2_vehicle_status=true
```

Observed dry-run topics:

- `/zcw/multi_vehicle/dry_run/vehicle_1_goal`
- `/zcw/multi_vehicle/dry_run/vehicle_2_goal`
- `/zcw/multi_vehicle/dry_run/topology_state`
- `/zcw/multi_vehicle/dry_run/safety_state`
- `/zcw/multi_vehicle/dry_run/assignment_state`

Observed forbidden publisher counts:

- `/px4_1/fmu/in/offboard_control_mode`: `0`
- `/px4_1/fmu/in/trajectory_setpoint`: `0`
- `/px4_1/fmu/in/vehicle_command`: `0`
- `/px4_2/fmu/in/offboard_control_mode`: `0`
- `/px4_2/fmu/in/trajectory_setpoint`: `0`
- `/px4_2/fmu/in/vehicle_command`: `0`

Stage M3: RViz overlay.

- Show vehicle poses, candidate goals and relay radius.
- Capture real RViz evidence only after M2 passes.
- Do not start Offboard or arm for this overlay.

Latest M3 evidence:

- RViz config: `ros2_ws/src/zcw_cable_perception/rviz/two_vehicle_dry_run_overlay.rviz`
- command: `CAPTURE_RVIZ=1 RVIZ_SETTLE_SEC=10 scripts/verify_two_vehicle_dry_run_smoke.sh`
- summary: `data/results/two_vehicle_dry_run_smoke_20260609_105743/two_vehicle_dry_run_smoke_20260609_105743.txt`
- screenshot: `data/screenshots/two_vehicle_dry_run_overlay_20260609_105743.png`
- forbidden publishers: `data/logs/two_vehicle_dry_run_forbidden_publishers_20260609_105743.log`

Observed M3 result:

```text
decision=accepted_two_vehicle_dry_run_smoke
starts_rviz=true
starts_offboard=false
arms=false
publishes_fmu_in=false
dry_topics_ok=true
forbidden_publishers_zero=true
screenshot_ok=1
```

Manual screenshot review:

- RViz Global Status is usable for the configured fixed frame.
- Vehicle 1 and Vehicle 2 dry-run goal displays are enabled.
- The screenshot is non-empty and shows the two dry-run goal points on the grid.

Stage M4: role assignment dry-run enrichment.

- Keep the same M1/M2/M3 safety boundary.
- Add a rule-baseline `assignment_state` topic.
- Verify assignment state publishes in a two-vehicle read-only smoke.
- Verify key PX4 input publisher counts remain `0`.

Latest M4 evidence:

- source: `ros2_ws/src/zcw_px4_baseline/src/two_vehicle_dry_run_planner.cpp`
- static contract summary: `data/results/two_vehicle_dry_run_contract_20260609_110329/two_vehicle_dry_run_contract_20260609_110329.txt`
- smoke summary: `data/results/two_vehicle_dry_run_smoke_20260609_110334/two_vehicle_dry_run_smoke_20260609_110334.txt`
- dry-run samples: `data/logs/two_vehicle_dry_run_samples_20260609_110334.log`
- forbidden publishers: `data/logs/two_vehicle_dry_run_forbidden_publishers_20260609_110334.log`

Observed M4 result:

```text
decision=accepted_two_vehicle_dry_run_smoke
starts_offboard=false
arms=false
publishes_fmu_in=false
dry_topics_ok=true
forbidden_publishers_zero=true
```

Observed assignment state includes:

```text
RULE_BASELINE_DRY_RUN
dry_run=true
learned_policy=false
vehicle_1_role=inspection_candidate
vehicle_2_role=relay_candidate
```

Stage M5: dry-run sample audit.

- Use full-length ROS topic echo samples to avoid truncated role/topology evidence.
- Parse the generated sample log offline.
- Require vehicle goals, topology state, safety state and assignment state to be present.
- Require non-placeholder topology distance evidence.
- Require no-active and no-PX4-input flags to be present in the samples.

Latest M5 evidence:

- script: `scripts/audit_two_vehicle_dry_run_samples.sh`
- smoke summary: `data/results/two_vehicle_dry_run_smoke_20260609_110728/two_vehicle_dry_run_smoke_20260609_110728.txt`
- samples: `data/logs/two_vehicle_dry_run_samples_20260609_110728.log`
- samples audit summary: `data/results/two_vehicle_dry_run_samples_audit_20260609_110749/two_vehicle_dry_run_samples_audit_20260609_110749.txt`
- forbidden publishers: `data/logs/two_vehicle_dry_run_forbidden_publishers_20260609_110728.log`

Observed M5 result:

```text
decision=accepted_two_vehicle_dry_run_samples_audit
has_vehicle_1_goal=true
has_vehicle_2_goal=true
has_topology=true
has_safety=true
has_assignment=true
has_rule_baseline=true
has_no_learned_policy=true
has_v1_inspection=true
has_v2_relay=true
has_no_active=true
has_no_fmu_in=true
has_valid_topology_distance=true
```

Representative full-length topology and assignment samples:

```text
TOPOLOGY_READY; dry_run=true; publishes_fmu_in=false; vehicle_distance_m=0.0107667; relay_radius_m=800
RULE_BASELINE_DRY_RUN; dry_run=true; learned_policy=false; starts_offboard=false; arms=false; publishes_fmu_in=false; vehicle_1_role=inspection_candidate; vehicle_2_role=relay_candidate; topology_ready=true; safety_ready=true
```

## 6. Promotion Criteria

Two-vehicle active control may only be considered after all of these exist:

- accepted M1 static contract audit.
- accepted M2 read-only smoke.
- accepted M3 RViz overlay.
- documented user approval for a two-vehicle active review.
- separate active bridge design that is not cable Phase B active bridge.

Until then, two-vehicle work remains dry-run/read-only.
