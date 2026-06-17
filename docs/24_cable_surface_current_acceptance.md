# Cable Surface Current Acceptance

This document records the current cable surface coverage progression boundary.

It does not approve active control. It does not claim final cable inspection coverage.

## 1. Accepted Inputs

Current aggregate command:

```bash
scripts/audit_cable_surface_current_acceptance.sh
```

Latest accepted result:

- summary: `data/results/cable_surface_current_acceptance_20260617_161107/cable_surface_current_acceptance_20260617_161107.txt`

Inputs:

- C1 visible-side summary: `data/results/cable_visible_side_surface_coverage_offline_20260617_093538/cable_visible_side_surface_coverage_offline_20260617_093538.txt`
- C2 multiview candidate summary: `data/results/cable_multiview_surface_candidate_offline_20260617_094219/cable_multiview_surface_candidate_offline_20260617_094219.txt`
- C2 multiview union summary: `data/results/cable_multiview_surface_union_offline_20260617_094233/cable_multiview_surface_union_offline_20260617_094233.txt`
- Cable dry-run acceptance summary: `data/results/cable_dry_run_acceptance_20260617_085648/cable_dry_run_acceptance_20260617_085648.txt`

## 2. Current Result

```text
decision=accepted_cable_surface_current_acceptance
reason=surface_progression_ready_but_final_claim_blocked
c1_visible_side_ok=true
c2_candidate_ok=true
c2_union_ok=true
dry_run_ok=true
final_claim_blocked=true
c2_global_min_total_surface_coverage_upper_bound_ratio=0.875000000
c2_global_min_visible_side_coverage_upper_bound_ratio=1.000000000
claims_active_control_approval=false
claims_final_cable_inspection_coverage=false
claims_cable_surface_progression_current_acceptance_pass=true
```

## 3. Allowed Claim

The current allowed claim is:

```text
cable_surface_progression_current_acceptance_pass=true
```

Meaning:

- visible-side C1 is accepted.
- side A / side B multiview C2 candidate is accepted.
- C2 union FOV upper-bound characterization is accepted.
- dry-run cable geometry readiness is accepted.

## 4. Non-Claims

Do not claim:

- final cable inspection coverage.
- active PX4 cable tracking.
- occlusion-certified surface coverage.
- defect detection.
- learned policy control.

Active control remains blocked until explicitly approved.
