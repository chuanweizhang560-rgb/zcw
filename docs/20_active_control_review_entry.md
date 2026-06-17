# Active Control Review Entry

This document is the single entry point for any future transition from dry-run/read-only evidence to active PX4 setpoint publication.

It does not approve active control. It does not create an active bridge. It does not permit `/fmu/in/*` publication.

## 1. Current Decision

Current decision:

```text
active_control_approved=false
cable_phase_b_active_bridge_approved=false
multi_vehicle_active_offboard_approved=false
rl_policy_control_approved=false
slam_feedback_control_approved=false
```

Any future active-control node must start from a new explicit user instruction that says active PX4 setpoint publication is approved for a named scenario.

The consolidated handoff document for that decision point is `docs/25_cable_active_control_review_package.md`.
The frozen first active scenario is defined in `docs/26_cable_single_vehicle_active_scenario.md`.

## 2. Scope

This review entry only covers the path toward a future single-vehicle cable active bridge.

It does not cover:

- four-vehicle active Offboard.
- learned policy control.
- SLAM feedback used directly for control.
- image-level defect detection.
- real hardware flight.

## 3. Existing Evidence Inputs

The current accepted evidence chain is:

| Evidence | File |
|---|---|
| current evidence matrix | `docs/19_current_evidence_matrix.md` |
| cable dry-run acceptance | `data/results/cable_dry_run_acceptance_20260617_085648/cable_dry_run_acceptance_20260617_085648.txt` |
| cable line-segment coverage | `data/results/cable_line_segment_coverage_20260617_085604/cable_line_segment_coverage_20260617_085604.txt` |
| cable visual acceptance | `data/results/cable_visual_acceptance_20260617_085710/cable_visual_acceptance_20260617_085710.txt` |
| Phase B gate plan | `docs/05_cable_phase_b_gate_plan.md` |
| active preflight boundary | `docs/06_cable_phase_b_active_bridge_preflight.md` |
| active threshold review | `docs/07_cable_active_threshold_review.md` |
| active bridge code review template | `docs/08_cable_active_bridge_code_review.md` |
| dry-run readiness matrix | `docs/09_dry_run_readiness_matrix.md` |

## 4. Required Approval Sequence

Before any future active bridge exists, complete these steps in order:

1. Record explicit user approval in `PROCESS_LOG.md`.
2. Freeze the exact scenario: single vehicle, cable group, world, vehicle model, ROS domain, and timeout.
3. Create a new isolated active bridge design diff. Do not mutate the existing dry-run node into an active publisher.
4. Add a static contract audit proving the bridge has a dry-run default and cannot publish `/fmu/in/*` unless an explicit approval parameter is true.
5. Add an active bridge dry-run mode that publishes only debug topics under `/zcw/cable/offboard_active/*`.
6. Re-run current evidence matrix and dry-run readiness.
7. Only then run a short approved active simulation in Gazebo, with screenshots and publisher-count logs.

## 5. Runtime Control Policy

The active bridge must not publish raw lookahead targets directly to PX4.

Required policy:

- Consume only gate-approved NED setpoints from the existing dry-run gate path.
- Enforce horizontal jump limit `<= 2.5 m`.
- Enforce vertical jump limit `<= 0.5 m`.
- Keep observed dry-run setpoint step near `<= 1.1 m` before approval.
- Publish setpoints at a fixed real-time rate, initially `20 Hz`, matching typical PX4 Offboard setpoint practice.
- Abort on stale tracking state, stale vehicle state, missing safety gate, target jump violation, group mismatch, or publisher-count mismatch.

This project should prefer mature PX4/ROS 2 Offboard examples and PX4 message semantics over a custom controller. If trajectory smoothing is required later, it must be introduced as a separate reviewed dependency or upstream-backed module, not as ad hoc flight-control logic inside the bridge.

## 6. Realtime Concern

The policy output should remain simple at the active bridge boundary:

```text
approved local setpoint + yaw + safety state
```

Role assignment, task allocation, spline fitting, catenary fitting, and lookahead generation should stay outside the real-time PX4 publication loop. The bridge loop should only validate and publish already-approved setpoints.

This keeps the active publisher deterministic and easier to shut down.

## 7. Forbidden In The First Active Bridge

The first active bridge must not include:

- multi-vehicle control.
- relay behavior.
- learned policy output.
- SLAM output used as a control source.
- defect-detection logic.
- automatic selection of cable group.
- automatic takeoff task sequencing beyond the explicitly approved test.
- hidden parameter override that enables active publication.

## 8. Required Evidence From The First Active Run

A future approved active run must produce:

- PX4/Gazebo summary.
- vehicle status log showing intended Offboard/armed window.
- `/fmu/in/*` publisher-count log showing only the approved active bridge publisher.
- setpoint stream log with rate, max jump, min/max altitude, and abort state.
- RViz screenshot showing cable line, approved path, setpoint, and vehicle pose.
- Gazebo screenshot showing vehicle and cable environment.
- updated `PROCESS_LOG.md`.

## 9. Stop Conditions

Immediately abort and mark the run failed if any of these occur:

- unexpected publisher appears on `/fmu/in/*`.
- setpoint jump exceeds threshold.
- vehicle state becomes stale.
- safety gate becomes false.
- cable tracking group changes unexpectedly.
- PX4 leaves the intended Offboard state.
- vehicle leaves the approved corridor.
- Gazebo/RViz evidence cannot be captured after an active claim.

## 10. Current Next Action

The next safe action is not to implement the active bridge yet.

The next safe action is one of:

- review this entry with the user.
- review `docs/21_future_cable_active_bridge_design.md`.
- review `docs/25_cable_active_control_review_package.md`.
- review `docs/26_cable_single_vehicle_active_scenario.md`.
- strengthen cable/wind evidence while remaining dry-run/read-only.

The active bridge remains blocked until explicit user approval is recorded.
