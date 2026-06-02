# scripts

启动、检查、评估和训练入口脚本放在这里。

脚本只能做工程编排，不能隐藏核心算法实现。

## 当前脚本

- `setup_px4_venv.sh`：基于系统 Python 3.10 建立 PX4 release/1.14 专用 venv，并固定 `empy==3.3.4`。
- `run_px4_gazebo_classic_headless.sh`：用 clean env 启动 PX4 SITL + Gazebo Classic headless，并把运行日志写入 `data/logs/`。
- `build_microxrce_agent.sh`：用 eProsima Micro-XRCE-DDS-Agent v2.2.1 和系统 FastDDS/FastCDR 构建 `MicroXRCEAgent`。
- `verify_px4_ros2_bridge_headless.sh`：启动 Micro XRCE-DDS Agent、PX4/Gazebo headless，并验证 ROS 2 中出现 `/fmu/out/vehicle_status`。
- `verify_px4_offboard_hover.sh`：运行基于 `px4_ros_com` 官方示例派生的 `zcw_px4_baseline/offboard_hover_retry`，验证单机进入 armed Offboard 悬停状态。
