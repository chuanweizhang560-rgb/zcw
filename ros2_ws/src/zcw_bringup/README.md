# zcw_bringup

ROS 2 bringup package for launch and configuration entry points.

当前包只提供工程入口，不实现控制、感知或学习算法。

当前 launch 入口：

- `single_vehicle_offboard_hover.launch.py`：启动 PX4 Offboard 悬停 baseline 节点。PX4 SITL、Gazebo Classic 和 Micro XRCE-DDS Agent 仍由脚本启动，以便严格控制 clean env。
