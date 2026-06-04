# Multi-Vehicle Readiness

This document records the upstream PX4/Gazebo Classic multi-vehicle boundary before any two-vehicle or four-vehicle experiment is started.

It does not approve multi-vehicle Offboard control.

## 1. Current Decision

The project may proceed toward multi-vehicle simulation only through official PX4 multi-instance entry points and staged read-only verification:

1. static upstream audit.
2. two-vehicle headless read-only startup. Accepted.
3. two-vehicle ROS 2 topic namespace audit. Accepted.
4. two-vehicle rule baseline only after read-only topics are isolated.
5. four-vehicle startup only after two-vehicle evidence is accepted.

No RL, role assignment, relay behavior or multi-vehicle Offboard control is approved by this document.

## 2. Upstream Audit Command

```bash
scripts/audit_multi_vehicle_upstream_readiness.sh
```

The audit is allowed to:

- inspect PX4 release/1.14 local upstream scripts.
- check Gazebo Classic multi-instance support.
- check PX4 instance-specific `MAV_SYS_ID`, `UXRCE_DDS_KEY` and DDS namespace setup.
- write summary files under `data/results/`.

The audit is not allowed to:

- start ROS, PX4, Gazebo or RViz.
- start Offboard.
- arm.
- publish `/fmu/in/*`.
- create a multi-vehicle controller.

## 3. Upstream Findings

Local PX4 release/1.14 contains:

- `Tools/simulation/gazebo-classic/sitl_multiple_run.sh`
- Gazebo Classic instance TCP port offset from `4560 + instance`.
- Gazebo Classic instance UDP port offset from `14560 + instance`.
- supported `iris` model in the multi-instance script.
- `MAV_SYS_ID = px4_instance + 1` in `rcS`.
- `UXRCE_DDS_KEY = px4_instance + 1` in `rcS`.
- nonzero instance DDS namespace `px4_<instance>` in `rcS`.
- MAVLink offboard/GCS port offsets in `px4-rc.mavlink`.

This is enough to plan a two-vehicle read-only smoke test. It is not enough to start multi-vehicle Offboard control.

## 4. Latest Result

Latest evidence:

- summary: `data/results/multi_vehicle_upstream_readiness_20260604_140726/multi_vehicle_upstream_readiness_20260604_140726.txt`

Expected accepted fields:

```text
decision=accepted_multi_vehicle_upstream_static_audit
starts_ros=false
starts_px4=false
starts_gazebo=false
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
multi_script_supported=true
rcs_namespace_supported=true
mavlink_ports_supported=true
```

Latest accepted result:

- `decision=accepted_multi_vehicle_upstream_static_audit`
- `reason=px4_release_1_14_contains_gazebo_classic_multi_instance_and_dds_namespace_support`
- `has_gazebo_classic_multi_script=true`
- `has_spawn_model_function=true`
- `has_instance_tcp_port_offset=true`
- `has_instance_udp_port_offset=true`
- `has_supported_iris_model=true`
- `has_mav_sys_id_per_instance=true`
- `has_uxrce_key_per_instance=true`
- `has_nonzero_px4_namespace=true`
- `has_uxrce_udp_default_port=true`
- `has_uxrce_start_udp=true`
- `has_mavlink_offboard_local_port_offset=true`
- `has_mavlink_offboard_remote_port_offset=true`
- `has_mavlink_gcs_local_port_offset=true`

## 5. Next Allowed Work

Two-vehicle read-only smoke:

```bash
scripts/verify_px4_gazebo_classic_multi_vehicle_readonly.sh
```

Latest evidence:

- summary: `data/results/multi_vehicle_readonly_20260604_141601/multi_vehicle_readonly_20260604_141601.txt`
- topics: `data/logs/multi_vehicle_topics_20260604_141601.log`
- forbidden publishers: `data/logs/multi_vehicle_forbidden_publishers_20260604_141601.log`
- agent log: `data/logs/multi_vehicle_agent_20260604_141601.log`
- Gazebo log: `data/logs/multi_vehicle_gzserver_20260604_141601.log`

Observed result:

```text
decision=accepted_multi_vehicle_readonly_smoke
starts_ros=true
starts_px4=true
starts_gazebo=true
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
num_vehicles=2
observed_px4_1_vehicle_status=true
observed_px4_2_vehicle_status=true
forbidden_publishers_zero=true
clean_gazebo_env=true
```

Topic evidence:

- `/px4_1/fmu/out/vehicle_status` observed.
- `/px4_2/fmu/out/vehicle_status` observed.
- `/px4_1/fmu/in/offboard_control_mode` publisher count: `0`.
- `/px4_1/fmu/in/trajectory_setpoint` publisher count: `0`.
- `/px4_1/fmu/in/vehicle_command` publisher count: `0`.
- `/px4_2/fmu/in/offboard_control_mode` publisher count: `0`.
- `/px4_2/fmu/in/trajectory_setpoint` publisher count: `0`.
- `/px4_2/fmu/in/vehicle_command` publisher count: `0`.

Allowed next:

1. document the two-vehicle read-only evidence in the main runbook.
2. add a two-vehicle rule-baseline design document.
3. keep two-vehicle Offboard disabled until the rule-baseline design is reviewed.
4. keep four-vehicle startup disabled until two-vehicle rule-baseline evidence is accepted.

Still forbidden until the two-vehicle rule-baseline design and evidence are accepted:

1. two-vehicle Offboard.
2. two-vehicle arming from project code.
3. four-vehicle startup.
4. multi-agent policy or role assignment.
