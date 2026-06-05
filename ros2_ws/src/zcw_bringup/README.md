# zcw_bringup

ROS 2 bringup package for launch and configuration entry points.

当前包只提供工程入口，不实现控制、感知或学习算法。

当前 launch 入口：

- `single_vehicle_offboard_hover.launch.py`：启动 PX4 Offboard 悬停 baseline 节点。PX4 SITL、Gazebo Classic 和 Micro XRCE-DDS Agent 仍由脚本启动，以便严格控制 clean env。
- `single_vehicle_waypoint_sequence.launch.py`：启动 PX4 Offboard waypoint baseline 节点，用固定 NED 航点序列验证位置 setpoint 链路。
- `single_vehicle_wind_turbine_inspection.launch.py`：在 AerialCore 风机 world 上用固定几何航点验证最小风机巡检 baseline。
- `single_vehicle_wind_turbine_multilevel_orbit.launch.py`：在 AerialCore 风机 world 上用独立多高度层 orbit 航点和 yaw-to-center setpoint 验证规则风机巡检 baseline。
- `single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py`：15m 半径近距多高度层 orbit 候选，用于对比风机 depth useful return；不替代默认 20m baseline。
- `single_vehicle_cable_inspection.launch.py`：在 AerialCore 两塔导线 world 上用固定几何航点验证最小电缆巡检 baseline。
