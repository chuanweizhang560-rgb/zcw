# Cable Active Approval Manifest

This document freezes the exact approval wording and approval constraints for any future transition from frozen cable dry-run/read-only evidence to an approved active bridge.

It is not approval. It does not create an active bridge. It does not permit `/fmu/in/*` publication.

## 1. Required Approval Text

If active cable control is ever approved, `PROCESS_LOG.md` must contain explicit approval text that includes all of the following pieces:

- `single_vehicle_cable_short_active`
- `active_control_approved=true`
- `phase_b_user_approved=true`
- `cable_phase_b_active_bridge_approved=true`

The approval text must also state the intended scenario in plain language:

- one PX4 SITL vehicle,
- cable only,
- one AerialCore two-tower cable world,
- one short active window,
- no multi-vehicle relay,
- no RL policy in the publication loop,
- no SLAM feedback in the publication loop.

## 2. Required Approval Scope

The approval only covers:

- the frozen `single_vehicle_cable_short_active` scenario,
- a single vehicle namespace,
- the single-vehicle cable active bridge,
- the explicitly approved active window.

It does not cover:

- four-vehicle active Offboard,
- learned policy control,
- SLAM-feedback control,
- full cable traversal beyond the frozen short test,
- automatic relay recovery,
- any real hardware flight.

## 3. Required Approval Preconditions

Before the approval text is considered valid, the following prerequisites must already exist:

- `docs/25_cable_active_control_review_package.md`
- `docs/26_cable_single_vehicle_active_scenario.md`
- `docs/27_cable_active_readiness_snapshot.md`
- `docs/19_current_evidence_matrix.md`
- `docs/10_evidence_inventory.md`
- `docs/21_future_cable_active_bridge_design.md`
- explicit dry-run and RViz evidence for the cable gate

## 4. Review Rule

If the required approval text is absent from `PROCESS_LOG.md`, the active bridge remains blocked.

If the required approval text appears but the frozen scenario name is missing, the approval is invalid.

If the required approval text appears but any of the approval scope constraints are violated, the approval is invalid.

## 5. Non-Goals

This manifest does not:

1. start Gazebo,
2. start PX4,
3. arm a vehicle,
4. publish Offboard heartbeat,
5. publish PX4 trajectory setpoints,
6. claim that the drone can follow the cable.
