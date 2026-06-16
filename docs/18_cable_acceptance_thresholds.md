# Cable Acceptance Thresholds

This document defines the current acceptance threshold contract for the cable inspection dry-run baseline.

It does not approve cable Phase B active control, PX4 `/fmu/in/*` publication, arming, Offboard mode switching, learned policy control, image-level defect detection, or final physical inspection completion.

## 1. Scope

Accepted scope:

- Cable inspection dry-run only.
- AerialCore `danube_wires` evidence already converted to audited CSV artifacts.
- Geometry chain based on mature libraries and existing audits:
  - PCL multiline RANSAC evidence.
  - Ceres/Eigen catenary fit evidence.
  - Offset path and lookahead target CSV evidence.
  - Read-only ROS/RViz visualization evidence.
- No active PX4 setpoint publication.

Out of scope:

- Cable Phase B active bridge.
- Real PX4 cable-tracking setpoint publication.
- Automatic arming or Offboard switching.
- Image-level defect detection.
- Learned policy/MARL control.
- Final physical inspection coverage claims.

## 2. Authoritative Audits

The current aggregate dry-run audit is:

```bash
scripts/audit_cable_dry_run_acceptance.sh
```

The current visual aggregate audit is:

```bash
scripts/audit_cable_visual_acceptance.sh
```

Both aggregate audits are read-only and must keep these boundary fields:

```text
starts_ros=false
starts_px4=false
starts_gazebo=false
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
```

Latest accepted threshold contract:

- `data/results/cable_acceptance_threshold_contract_20260616_152304/cable_acceptance_threshold_contract_20260616_152304.txt`

Latest accepted dry-run aggregate:

- `data/results/cable_dry_run_acceptance_20260616_152304/cable_dry_run_acceptance_20260616_152304.txt`

Latest accepted visual aggregate:

- `data/results/cable_visual_acceptance_20260616_152334/cable_visual_acceptance_20260616_152334.txt`

## 3. Default Thresholds

These values are the current default gate values in `scripts/audit_cable_dry_run_acceptance.sh`.

| Gate | Field | Threshold | Current accepted observation |
|---|---:|---:|---:|
| Accepted cable groups | `MIN_GROUPS` | `5` | `5` |
| Per-group dry-run coverage ratio | `MIN_COVERAGE_RATIO` | `0.80` | `0.840000000` |
| Offset clearance error | `MAX_CLEARANCE_ERROR_M` | `0.001m` | `0.000000000m` |
| Frame/source/target error | `MAX_FRAME_ERROR_M` | `0.001m` | `0.000000000m` |
| Lookahead distance error | `MAX_LOOKAHEAD_ERROR_M` | `0.01m` | `0.001200000m` |
| Forward tangent consistency | `MIN_FORWARD_DOT` | `0.99` | `0.999999005` |

## 4. Required Evidence Inputs

The aggregate dry-run audit must consume all of these evidence groups:

| Evidence group | Required source type | Current accepted source |
|---|---|---|
| Tracking envelope | offline offset path/centerline audit | `data/results/cable_tracking_envelope_20260615_093659/cable_tracking_envelope_20260615_093659.txt` |
| Frame contract | offline coordinate-contract audit | `data/results/cable_frame_contract_20260615_100822/cable_frame_contract_20260615_100822.txt` |
| All-groups coverage monitor summary | read-only coverage monitor aggregate | `data/results/lookahead_coverage_monitor_all_groups_20260615_100351/lookahead_coverage_monitor_all_groups_20260615_100351.txt` |
| All-groups coverage monitor CSV | per-group coverage rows | `data/results/lookahead_coverage_monitor_all_groups_20260615_100351/lookahead_coverage_monitor_all_groups_20260615_100351.csv` |
| All-groups RViz overlay | real RViz marker screenshot evidence | `data/results/cable_all_groups_rviz_overlay_20260616_093252/cable_all_groups_rviz_overlay_20260616_093252.txt` |

## 5. Pass Meaning

If `scripts/audit_cable_dry_run_acceptance.sh` passes, the allowed claim is:

```text
The cable geometry dry-run baseline has accepted tracking-envelope, frame-contract, and all-groups dry-run coverage evidence under the current repository thresholds.
```

If `scripts/audit_cable_visual_acceptance.sh` passes, the allowed claim is:

```text
The accepted cable dry-run geometry evidence is visible in a real RViz all-groups overlay, with no PX4/Gazebo/Offboard path active during the visual aggregate audit.
```

These are dry-run evidence claims only.

## 6. Non-Claims

Even when the audits pass, do not claim:

- cable Phase B active bridge approval.
- PX4 `/fmu/in/*` setpoint publication.
- automatic arming or Offboard mode switching.
- final cable inspection coverage.
- image-level defect detection.
- learned policy/MARL control.
- multi-vehicle active cable tracking.

Reason:

- The coverage monitor is a dry-run lookahead/path readiness metric.
- The RViz overlay proves geometry visibility, not active tracking safety.
- The catenary/offset/lookahead CSV chain is audited offline and still needs a separate active-control review before PX4 input publication.
- PX4 uXRCE-DDS can expose `/fmu/in/*` topics as subscriptions; before Phase B approval, publisher count must remain `0`.

## 7. Next Upgrade Gates

Before stronger cable claims, add at least one of these:

- A denser cable coverage model based on explicit cable surfels or sampled line segments.
- A documented active-control review that still does not implement Phase B active bridge.
- A mature open-source image-quality or defect-detection model, kept separate from the dry-run geometry baseline.
- A fresh real RViz or Gazebo screenshot only when it adds new evidence beyond the existing all-groups overlay.

## 8. Maintenance Rule

When changing any default threshold in `scripts/audit_cable_dry_run_acceptance.sh`, update this document and rerun:

```bash
scripts/audit_cable_acceptance_threshold_contract.sh
scripts/audit_cable_dry_run_acceptance.sh
scripts/audit_cable_visual_acceptance.sh
```
