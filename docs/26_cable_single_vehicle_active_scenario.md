# Cable Single-Vehicle Active Scenario Freeze

This document freezes the first cable active-control scenario that may be approved in the future.

It is not approval. It does not create an active bridge. It does not permit `/fmu/in/*` publication.

## 1. Frozen Scenario Name

```text
single_vehicle_cable_short_active
```

## 2. Frozen Scenario Shape

The first approved active test must remain narrowly bounded:

- one PX4 SITL vehicle,
- cable only,
- one AerialCore two-tower cable world,
- one vehicle namespace,
- one short active window,
- short corridor hold or short segment tracking,
- no multi-vehicle relay,
- no RL policy in the publication loop,
- no SLAM feedback in the publication loop,
- no automatic task switching,
- no full cable traversal.

The purpose is to validate that the approved setpoint stream can be executed safely, not to complete the full mission.

## 3. Frozen Runtime Limits

The initial active run limits are:

- active publication loop: `20 Hz`,
- horizontal setpoint jump: `<= 2.5 m`,
- vertical setpoint jump: `<= 0.5 m`,
- stale gate timeout: `<= 0.5 s`,
- stale vehicle state timeout: `<= 0.5 s`,
- first active run duration: `<= 60 s`.

## 4. Required Inputs

The future active bridge may only consume gate-approved outputs from the dry-run path:

- `/zcw/cable/offboard_gate/state`
- `/zcw/cable/offboard_gate/phase_b_allowed`
- `/zcw/cable/offboard_gate/approved_ned`
- `/fmu/out/vehicle_status`
- `/fmu/out/vehicle_local_position`

It must not read raw perception topics directly:

- `/camera/points`
- `/zcw/cable/lookahead_target`
- `/zcw/cable/offset_path`
- `/zcw/cable/dry_run/candidate_setpoint`
- `/zcw/cable/px4_bridge/ned_setpoint_dry_run`

## 5. Required Outputs After Approval

Only after explicit user approval may the future active bridge publish:

- `/fmu/in/offboard_control_mode`
- `/fmu/in/trajectory_setpoint`
- `/fmu/in/vehicle_command`
- `/zcw/cable/offboard_active/state`
- `/zcw/cable/offboard_active/abort`

## 6. Required Evidence For The Frozen Scenario

The approval package must be able to cite:

- `docs/25_cable_active_control_review_package.md`
- `docs/20_active_control_review_entry.md`
- `docs/21_future_cable_active_bridge_design.md`
- `docs/06_cable_phase_b_active_bridge_preflight.md`
- `docs/05_cable_phase_b_gate_plan.md`
- `docs/24_cable_surface_current_acceptance.md`
The readiness snapshot is documented in `docs/27_cable_active_readiness_snapshot.md`.
The approval wording is defined in `docs/28_cable_active_approval_manifest.md`.
The complete bundle is frozen in `docs/29_cable_active_handoff_bundle.md`.

## 7. Non-Goals

This scenario does not:

1. cover four-vehicle active Offboard,
2. cover learned policy control,
3. cover SLAM-feedback control,
4. cover full cable traversal,
5. cover relay or recovery logic beyond the frozen short test.

## 8. Review Rule

If `PROCESS_LOG.md` does not contain explicit approval text for `single_vehicle_cable_short_active`, this scenario remains frozen and inactive.
