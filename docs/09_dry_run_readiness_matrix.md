# Dry-run Readiness Matrix

This document is the current status matrix for the cable inspection stack.

It does not approve Phase B execution.

## 1. Current Boundary

Current state:

- Phase B approval: `false`
- active bridge present: `false`
- cable-specific `/fmu/in/*` publisher: `false`
- Offboard started by cable stack: `false`
- vehicle armed by cable stack: `false`

The active bridge remains forbidden until explicit approval.

## 2. Readiness Audit

Implemented total audit:

```bash
scripts/audit_dry_run_readiness.sh
```

The audit is allowed to:

- run static checks.
- run existing dry-run-only audit scripts.
- inspect local evidence under `data/`.
- write summary logs under `data/results/`.

The audit is not allowed to:

- start ROS, PX4, Gazebo or RViz.
- start Offboard.
- arm.
- publish `/fmu/in/*`.
- create active bridge code.

## 3. Matrix

| Area | Evidence | Status |
|---|---|---|
| cable perception PX4 isolation | `scripts/audit_px4_isolation.sh` | accepted |
| Phase B boundary | `scripts/audit_phase_b_active_preflight_boundary.sh` | accepted |
| setpoint threshold review | `scripts/audit_cable_setpoint_thresholds.sh` | accepted |
| active bridge review template | `scripts/audit_active_bridge_review_template.sh` | accepted |
| total dry-run readiness | `scripts/audit_dry_run_readiness.sh` | accepted |
| ignored evidence inventory | `scripts/audit_evidence_inventory.sh` | accepted |
| active bridge implementation | `cable_offboard_active_bridge` | not present |
| Phase B approval | explicit user approval | not granted |

## 4. Latest Result

Latest evidence:

- summary: `data/results/dry_run_readiness_20260604_100331/dry_run_readiness_20260604_100331.txt`
- static checks: `data/results/dry_run_readiness_20260604_100331/static_repo_checks_20260604_100331.log`
- PX4 isolation: `data/results/dry_run_readiness_20260604_100331/px4_isolation_20260604_100331.log`
- Phase B preflight: `data/results/dry_run_readiness_20260604_100331/phase_b_preflight_20260604_100331.log`
- thresholds: `data/results/dry_run_readiness_20260604_100331/thresholds_20260604_100331.log`
- review template: `data/results/dry_run_readiness_20260604_100331/review_template_20260604_100331.log`
- evidence inventory: `data/results/evidence_inventory_20260604_130911/evidence_inventory_20260604_130911.txt`

Latest result:

- `decision=accepted_dry_run_readiness`
- `decision=accepted_evidence_inventory`
- `phase_b_approved=false`
- `active_bridge_present=false`
- `publishes_fmu_in=false`
- `evidence_present_count=11`
- `evidence_missing_count=0`

## 5. Next Allowed Work

Allowed without Phase B approval:

1. improve dry-run audits.
2. regenerate missing ignored evidence files.
3. add documentation and review templates.
4. add non-PX4 debug visualizations.
5. run `scripts/audit_evidence_inventory.sh` to confirm local evidence is still present.

Forbidden without Phase B approval:

1. creating `cable_offboard_active_bridge`.
2. publishing `/fmu/in/*` from cable-specific code.
3. setting `phase_b_user_approved:=true`.
4. starting cable active Offboard.
5. arming from the cable stack.
