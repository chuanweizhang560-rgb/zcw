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

Stage M2: read-only ROS graph smoke.

- Start two-vehicle read-only PX4/Gazebo using `scripts/verify_px4_gazebo_classic_multi_vehicle_readonly.sh` or a derived wrapper.
- Start the dry-run planner.
- Verify dry-run topics are published.
- Verify `/px4_1/fmu/in/*` and `/px4_2/fmu/in/*` publisher count remains `0`.

Stage M3: RViz overlay.

- Show vehicle poses, candidate goals and relay radius.
- Capture real RViz evidence only after M2 passes.
- Do not start Offboard or arm for this overlay.

## 6. Promotion Criteria

Two-vehicle active control may only be considered after all of these exist:

- accepted M1 static contract audit.
- accepted M2 read-only smoke.
- accepted M3 RViz overlay.
- documented user approval for a two-vehicle active review.
- separate active bridge design that is not cable Phase B active bridge.

Until then, two-vehicle work remains dry-run/read-only.
