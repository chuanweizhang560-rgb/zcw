# Future Cable Active Bridge Design

This is a design document for a future single-vehicle cable active bridge.

It is not an implementation. It does not approve active control. It does not permit `/fmu/in/*` publication.

## 1. Design Decision

The first future active bridge should be deliberately small:

```text
scope=single_vehicle_cable_only
input=gate_approved_dry_run_setpoint
output=PX4 Offboard setpoint topics
rate_hz=20
default_mode=dry_run
active_requires_explicit_approval=true
```

The bridge should not solve perception, catenary fitting, path generation, role allocation, or SLAM inside the real-time publication loop.

## 2. Upstream Basis

Use mature upstream behavior and interfaces:

- PX4 SITL Offboard semantics.
- ROS 2 Humble `px4_msgs`.
- PX4 official Offboard examples as the reference behavior for `OffboardControlMode`, `TrajectorySetpoint`, and `VehicleCommand`.
- Existing project dry-run gate outputs as the only setpoint source.

Do not introduce a custom flight controller.

Do not introduce custom Minimum Snap or PID logic inside the active bridge. If trajectory smoothing is needed later, it must be reviewed separately and backed by a mature dependency or upstream implementation.

## 3. Node Boundary

Future executable name:

```text
cable_active_bridge
```

Required default:

```text
phase_b_user_approved=false
```

With the default false, the node may publish only debug topics:

- `/zcw/cable/offboard_active/state`
- `/zcw/cable/offboard_active/approved_setpoint`
- `/zcw/cable/offboard_active/abort_reason`
- `/zcw/cable/offboard_active/rate_stats`

It must not publish any `/fmu/in/*` topic when `phase_b_user_approved=false`.

## 4. Future Active Outputs

Only after explicit user approval, the bridge may publish:

| Topic | Message | Purpose |
|---|---|---|
| `/fmu/in/offboard_control_mode` | `px4_msgs/msg/OffboardControlMode` | PX4 Offboard mode setpoint stream |
| `/fmu/in/trajectory_setpoint` | `px4_msgs/msg/TrajectorySetpoint` | local NED position/yaw setpoint |
| `/fmu/in/vehicle_command` | `px4_msgs/msg/VehicleCommand` | explicit arm/mode command only inside approved test window |

The first active run should use one vehicle namespace only. Multi-vehicle `/px4_i/fmu/in/*` output is out of scope.

## 5. Required Inputs

The bridge may subscribe to:

| Topic | Purpose |
|---|---|
| `/zcw/cable/offboard_gate/phase_b_allowed` | explicit approval mirror |
| `/zcw/cable/offboard_gate/approved_ned` | gate-approved local setpoint |
| `/zcw/cable/offboard_gate/state` | safety state |
| `/fmu/out/vehicle_status` | PX4 state |
| `/fmu/out/vehicle_local_position` | vehicle position sanity check |

The bridge must not subscribe directly to raw lookahead targets as its active setpoint source.

## 6. Realtime Loop

The active publication loop should run at `20 Hz`.

Each tick:

1. Check explicit approval.
2. Check fresh gate state.
3. Check fresh vehicle status and local position.
4. Check setpoint jump limits.
5. Check corridor and altitude bounds.
6. Publish debug state.
7. Publish PX4 setpoints only if every gate passes and active approval is true.

The loop should do no spline fitting, no catenary fitting, no path search, no SLAM optimization, no role assignment, and no learned-policy inference.

## 7. Safety Limits

Initial required limits:

| Limit | Value |
|---|---|
| active horizontal setpoint jump | `<= 2.5 m` |
| active vertical setpoint jump | `<= 0.5 m` |
| dry-run observed step before approval | `<= 1.1 m` |
| stale gate timeout | `<= 0.5 s` |
| stale vehicle state timeout | `<= 0.5 s` |
| first active run duration | `<= 60 s` |

The first active run should not attempt full cable traversal.

## 8. Abort Conditions

Abort immediately if:

- approval becomes false.
- safety gate becomes false.
- setpoint jump exceeds threshold.
- vehicle status is stale.
- vehicle local position is stale.
- PX4 leaves the expected Offboard state during the active window.
- unexpected `/fmu/in/*` publisher appears.
- vehicle leaves the approved cable corridor.
- debug setpoint rate drops below the accepted window.

Abort means:

- stop publishing active trajectory setpoints.
- publish abort reason.
- keep logs.
- do not automatically re-arm or retry.

## 9. Required Static Contract Audit

Before implementation can be considered, add a static audit that verifies:

- executable exists as a separate target.
- default approval parameter is false.
- no launch file sets approval true.
- dry-run mode publishes no `/fmu/in/*`.
- active mode has a single intentional PX4 input publisher.
- no multi-vehicle active namespace exists.
- no learned policy or SLAM feedback path is connected.

## 10. Required Dry-Run Evidence

Before active approval, run the active bridge in dry-run mode and prove:

- debug topics publish at the intended rate.
- max setpoint jump remains inside thresholds.
- abort conditions are observable.
- `/fmu/in/*` publisher count remains `0`.
- RViz shows cable, vehicle pose, approved setpoint and abort state.

## 11. First Active Test Shape

The first active test should be:

```text
scenario=single_vehicle_cable_short_active
vehicle=one PX4 SITL vehicle
world=AerialCore two-tower cable world
duration_sec<=60
mission=short corridor hold or short segment tracking
success=stable Offboard window + bounded setpoint stream + visual alignment evidence
```

It should not attempt:

- full 600m cable traversal.
- all five wire groups.
- multi-vehicle relay.
- RL role allocation.
- SLAM feedback control.

## 12. Evidence Required After Active Approval

After an approved active run, record:

- `PROCESS_LOG.md` entry with explicit approval text.
- active bridge static contract summary.
- dry-run active bridge summary.
- active run PX4/Gazebo summary.
- `/fmu/in/*` publisher-count log.
- setpoint rate/jump CSV.
- vehicle status log.
- vehicle local position log.
- Gazebo screenshot.
- RViz screenshot.

## 13. Current Status

Current status:

```text
design_document_exists=true
implementation_exists=false
active_control_approved=false
publishes_fmu_in=false
```

The next step is still a review step, not implementation.

The consolidated review entry that should be read first is `docs/25_cable_active_control_review_package.md`.
The frozen first active scenario is `docs/26_cable_single_vehicle_active_scenario.md`.
The latest readiness snapshot is documented in `docs/27_cable_active_readiness_snapshot.md`.
The approval wording is frozen in `docs/28_cable_active_approval_manifest.md`.
