# Cable Active Handoff Bundle

This document freezes the complete handoff bundle for the frozen single-vehicle cable active-control path.

It is not approval. It does not create an active bridge. It does not permit `/fmu/in/*` publication.

## 1. Bundle Purpose

This bundle exists so a future executor can read one compact entry and obtain the complete frozen path:

- review package,
- scenario freeze,
- readiness snapshot,
- approval manifest,
- current matrix and evidence inventory state.

The bundle is intentionally narrow. It does not broaden the project scope.

## 2. Bundle Contents

The bundle consists of:

- `docs/25_cable_active_control_review_package.md`
- `docs/26_cable_single_vehicle_active_scenario.md`
- `docs/27_cable_active_readiness_snapshot.md`
- `docs/28_cable_active_approval_manifest.md`
- `docs/19_current_evidence_matrix.md`
- `docs/10_evidence_inventory.md`

The bundle is only valid if all of the above remain aligned with the same frozen inactive path.

## 3. Frozen Bundle Claim

Current bundle claim:

```text
bundle_frozen=true
ready_for_review=true
active_control_approved=false
phase_b_user_approved=false
cable_phase_b_active_bridge_approved=false
publishes_fmu_in=false
```

## 4. Bundle Scope

The bundle only covers:

- one PX4 SITL vehicle,
- cable only,
- one AerialCore two-tower cable world,
- one frozen short active candidate,
- one explicit future active window if ever approved.

It does not cover:

- four-vehicle active Offboard,
- learned policy control,
- SLAM-feedback control,
- full cable traversal beyond the frozen short test,
- real hardware flight,
- automatic relay recovery.

## 5. Bundle Review Rule

If `PROCESS_LOG.md` does not contain explicit approval text for `single_vehicle_cable_short_active`, the bundle remains inactive.

If any document in the bundle diverges from that frozen inactive state, the bundle is invalid until refreshed.
