# Current Evidence Matrix

This document records the current machine-checkable capability matrix.

It does not approve active cable control, multi-vehicle active Offboard, RL policy control, final inspection coverage, or defect detection.

## 1. Purpose

The matrix exists to make the current project state explicit:

- what the repository can currently claim from accepted evidence.
- what remains dry-run/read-only.
- what remains forbidden or not implemented.
- which evidence file backs each row.

The matrix audit is intentionally read-only. It does not start ROS, PX4, Gazebo, RViz, Offboard, arming, or `/fmu/in/*` publication.

## 2. Audit Command

```bash
scripts/audit_current_evidence_matrix.sh
```

Default inputs:

- cable dry-run acceptance: `data/results/cable_dry_run_acceptance_20260617_085648/cable_dry_run_acceptance_20260617_085648.txt`
- cable visual acceptance: `data/results/cable_visual_acceptance_20260617_085710/cable_visual_acceptance_20260617_085710.txt`
- wind rule-baseline acceptance: `data/results/wind_rule_baseline_acceptance_20260616_095017/wind_rule_baseline_acceptance_20260616_095017.txt`
- four-vehicle dry-run acceptance: `data/results/four_vehicle_dry_run_acceptance_20260616_090911/four_vehicle_dry_run_acceptance_20260616_090911.txt`
- project current acceptance: `data/results/project_current_acceptance_20260617_085710/project_current_acceptance_20260617_085710.txt`

## 3. Latest Accepted Result

- summary: `data/results/current_evidence_matrix_20260617_090333/current_evidence_matrix_20260617_090333.txt`
- matrix CSV: `data/results/current_evidence_matrix_20260617_090333/current_evidence_matrix_20260617_090333.csv`

Accepted fields:

```text
decision=accepted_current_evidence_matrix
positive_capability_count=5
accepted_positive_capability_count=5
forbidden_capability_count=4
forbidden_not_enabled=true
claims_current_evidence_matrix_pass=true
```

## 4. Current Positive Claims

| Area | Capability | Current Status | Boundary |
|---|---|---|---|
| cable | geometry tracking and lookahead dry-run | accepted | dry-run only, no PX4 active control |
| cable | all-groups RViz visual evidence | accepted | visual overlay only, no final inspection coverage |
| wind | single-vehicle rule-baseline motion, mapping and sampled occlusion coverage | accepted | rule baseline only, no final inspection coverage |
| multi-vehicle | four-vehicle topology, assignment and scoring dry-run | accepted | read-only/dry-run only, no active Offboard |
| project | integrated current status | accepted | current aggregate only, no RL or defect-detection claim |

## 5. Forbidden Or Not Implemented

| Capability | Current Status | Reason |
|---|---|---|
| cable Phase B active bridge | not approved | would publish active PX4 setpoints if implemented |
| multi-vehicle active Offboard | not approved | current four-vehicle work is read-only/dry-run |
| RL policy control | not implemented | current behavior is rule baseline only |
| image-level defect detection | not implemented | no defect model or dataset evidence exists |

## 6. Interpretation Rule

Use this matrix as the short handoff before starting a new node. If a future task wants to cross from dry-run/read-only into active control, the new node must first update this document and add a separate approval/review gate.
