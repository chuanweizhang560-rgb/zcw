# 执行手册

更新时间：2026-06-02 13:52:19 CST

本文件记录当前仓库的可执行入口和下一步操作顺序。

## 当前阶段

阶段 2：PX4 Classic / Gazebo 11 最小链路验证。

当前只验证单机 SITL 底座，不训练 RL，不实现控制算法。

## 已确认环境

```text
Ubuntu 22.04.5 LTS
ROS 2 Humble
Gazebo Classic 11.10.2
```

## 已实测链路

PX4 release/1.14 + Gazebo Classic 11 已完成 headless 最小链路验证。
PX4 release/1.14 + `px4_msgs release/1.14` + `px4_ros_com release/v1.14` + Micro XRCE-DDS Agent v2.2.1 已完成 ROS 2 bridge 验证。

实测成功标志：

```text
Simulator connected on TCP port 4560.
Startup script returned successfully
/fmu/out/vehicle_status
```

注意事项：

1. 必须使用 clean env 启动，避免继承旧 `BS` 项目的 `GAZEBO_MODEL_PATH`、`GAZEBO_PLUGIN_PATH`、`LD_LIBRARY_PATH`。
2. PX4 release/1.14 的 Python 依赖要固定 `empy==3.3.4`，不能使用 PyPI 默认拉取到的 empy 4.x。
3. Ubuntu 22.04 上构建 Classic 插件需要 `ninja-build`、`python3.10-venv`、`libgstreamer-plugins-base1.0-dev`。
4. headless 验证脚本使用 timeout 退出；只要日志中出现上述成功标志，timeout 退出不是失败。
5. Micro XRCE-DDS Agent v2.2.1 必须使用 clean build 目录和系统 `fmt`/`spdlog`，避免 conda include 路径导致 ABI/模板错误。

## 本地第三方仓库

第一批外部候选已克隆到 `third_party/`，但不会提交进主仓库。版本和许可证见 `OPEN_SOURCE_AUDIT.md`。

PX4 主仓库当前本地落点：

```text
third_party/PX4-Autopilot-release-1.14
third_party/px4_msgs                -> release/1.14, commit ffb6e80
third_party/px4_ros_com             -> release/v1.14, commit e18248d
third_party/Micro-XRCE-DDS-Agent-v2.2.1
```

## 可执行入口

准备 PX4 venv：

```bash
scripts/setup_px4_venv.sh
```

构建 PX4 和 Gazebo Classic 插件：

```bash
cd third_party/PX4-Autopilot-release-1.14
env PATH=/tmp/codex_zcw_px4_venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin PYTHON_EXECUTABLE=/tmp/codex_zcw_px4_venv/bin/python make px4_sitl_default sitl_gazebo-classic
```

headless 启动验证：

```bash
TIMEOUT_SEC=45 scripts/run_px4_gazebo_classic_headless.sh
```

构建 Micro XRCE-DDS Agent：

```bash
scripts/build_microxrce_agent.sh
```

ROS 2 bridge 验证：

```bash
scripts/verify_px4_ros2_bridge_headless.sh
```

## 下一步执行顺序

1. 在 `ros2_ws/src/zcw_bringup` 中建立 PX4 Offboard launch 入口。
2. 在 `ros2_ws/src/zcw_sim_assets` 中建立 Gazebo 11 world/model 引用入口。
3. 建立单机 Offboard 悬停 baseline，不接任务、不接学习。
4. 只在单机 Offboard 悬停闭环稳定后，再进入风机/电缆任务。

## 不允许事项

1. 不从零写低层飞控。
2. 不从零做风机、电塔、导线模型。
3. 不把 RL 接到电机或姿态内环。
4. 不把 `third_party/` 下的上游源码提交进主仓库。
5. 不在 PX4 Classic 兼容性未确认前启动多机阶段。
