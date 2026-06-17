# Cable Active Control Review Package

This document is the single handoff package for any future transition from cable dry-run/read-only evidence to an approved single-vehicle active PX4 setpoint run.

It is not approval. It does not create an active bridge. It does not permit `/fmu/in/*` publication.

## 1. Package Purpose

This package exists to remove ambiguity before any future active-control decision.

It collects:

- the current active-control boundary,
- the existing cable dry-run and surface-progression evidence,
- the exact first active scenario shape,
- the required runtime limits,
- the required evidence after an approved active run,
- the stop conditions.

The intended consumer is a future executor that must not invent a new controller or a new task definition.

The frozen scenario is defined separately in `docs/26_cable_single_vehicle_active_scenario.md`.
The approval wording is defined separately in `docs/28_cable_active_approval_manifest.md`.

## 2. Current Decision

Current decision:

```text
active_control_approved=false
cable_phase_b_active_bridge_approved=false
multi_vehicle_active_offboard_approved=false
rl_policy_control_approved=false
slam_feedback_control_approved=false
phase_b_user_approved=false
```

The active bridge remains blocked until the user explicitly approves a named active-control scenario in `PROCESS_LOG.md`.

## 3. Scope

This package only covers the future single-vehicle cable active bridge path.

It does not cover:

- four-vehicle active Offboard,
- learned policy control,
- SLAM output used directly for control,
- image-level defect detection,
- real hardware flight,
- automatic multi-vehicle relay logic.

## 4. Existing Evidence Inputs

The approved evidence chain that may justify a future active review is:

| Evidence | File |
|---|---|
| current status and next steps | `docs/14_current_status_and_next_steps.md` |
| current evidence matrix | `docs/19_current_evidence_matrix.md` |
| active control review entry | `docs/20_active_control_review_entry.md` |
| future cable active bridge design | `docs/21_future_cable_active_bridge_design.md` |
| cable inspection surface model | `docs/22_cable_inspection_surface_coverage_model.md` |
| cable multiview observation plan | `docs/23_cable_multiview_surface_observation_plan.md` |
| cable surface current acceptance | `docs/24_cable_surface_current_acceptance.md` |
| evidence inventory | `docs/10_evidence_inventory.md` |

The latest accepted cable progression evidence is currently dry-run and offline. It is not final cable inspection coverage and not active control evidence.
The current debug-overlay evidence was refreshed on 2026-06-17 at `data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260617_171815.png` with `phase_b_allowed=false` and `publishes_fmu_in=false`.
The frozen path readiness snapshot is documented in `docs/27_cable_active_readiness_snapshot.md`.

## 5. Scenario Freeze

If active control is ever approved, the first scenario must be frozen before implementation:

- single vehicle only,
- cable only,
- one short approved AerialCore cable scenario,
- frozen as `single_vehicle_cable_short_active` in `docs/26_cable_single_vehicle_active_scenario.md`,
- one vehicle namespace,
- one explicit active window,
- no multi-vehicle relay,
- no RL policy in the publication loop,
- no SLAM feedback in the publication loop,
- no automatic task switching.

The bridge should remain small and deterministic.

## 6. Runtime Policy

The runtime policy for the future active bridge is:

- active publication loop at `20 Hz`,
- consume only gate-approved NED setpoints,
- publish `OffboardControlMode`, `TrajectorySetpoint`, and `VehicleCommand` only inside the approved active window,
- keep role assignment, path generation, catenary fitting, and smoothing outside the real-time publication loop,
- use mature PX4 / ROS 2 Offboard behavior rather than a custom flight controller.

Required initial limits:

- horizontal setpoint jump `<= 2.5 m`,
- vertical setpoint jump `<= 0.5 m`,
- stale gate timeout `<= 0.5 s`,
- stale vehicle state timeout `<= 0.5 s`,
- first active run duration `<= 60 s`.

## 7. Required Evidence After Approval

An approved active run must produce:

- `PROCESS_LOG.md` entry with explicit approval text,
- static contract summary for the active bridge,
- dry-run active bridge summary,
- active PX4/Gazebo summary,
- `/fmu/in/*` publisher-count log,
- setpoint rate and jump CSV,
- vehicle status log,
- vehicle local position log,
- Gazebo screenshot,
- RViz screenshot.

## 8. Stop Conditions

Abort immediately if any of the following occur:

- approval becomes false,
- safety gate becomes false,
- setpoint jump exceeds threshold,
- vehicle status becomes stale,
- vehicle local position becomes stale,
- PX4 leaves the expected Offboard state,
- an unexpected `/fmu/in/*` publisher appears,
- the vehicle leaves the approved corridor,
- required screenshots cannot be captured after the active claim.

Abort means stop active publication, record the abort reason, and keep the logs.

## 9. Non-Goals

This package does not:

1. start Gazebo,
2. start PX4,
3. arm a vehicle,
4. publish Offboard heartbeat,
5. publish PX4 trajectory setpoints,
6. claim that the drone can follow the cable.

## 10. Review Package Usage

Future agents should use this document as the first stop before any active-control implementation.

If the required approval text is not present in `PROCESS_LOG.md`, the active bridge remains blocked.

If the dry-run evidence chain is incomplete, the active bridge remains blocked.

If the task broadens to multi-vehicle, RL policy control, or SLAM-feedback control, this package no longer applies.
