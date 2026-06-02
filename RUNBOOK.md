# 执行手册

更新时间：2026-06-02 13:35:10 CST

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

实测成功标志：

```text
Simulator connected on TCP port 4560.
Startup script returned successfully
```

注意事项：

1. 必须使用 clean env 启动，避免继承旧 `BS` 项目的 `GAZEBO_MODEL_PATH`、`GAZEBO_PLUGIN_PATH`、`LD_LIBRARY_PATH`。
2. PX4 release/1.14 的 Python 依赖要固定 `empy==3.3.4`，不能使用 PyPI 默认拉取到的 empy 4.x。
3. Ubuntu 22.04 上构建 Classic 插件需要 `ninja-build`、`python3.10-venv`、`libgstreamer-plugins-base1.0-dev`。
4. headless 验证脚本使用 timeout 退出；只要日志中出现上述成功标志，timeout 退出不是失败。

## 本地第三方仓库

第一批外部候选已克隆到 `third_party/`，但不会提交进主仓库。版本和许可证见 `OPEN_SOURCE_AUDIT.md`。

PX4 主仓库当前本地落点：

```text
third_party/PX4-Autopilot-release-1.14
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

## 下一步执行顺序

1. 清理并固定 `px4_msgs` / `px4_ros_com` 与 PX4 release/1.14 的分支或 commit。
2. 安装或构建 Micro XRCE-DDS Agent，验证 ROS 2 与 PX4 uORB bridge。
3. 在 `ros2_ws/src/zcw_bringup` 中建立 PX4 Offboard launch 入口。
4. 在 `ros2_ws/src/zcw_sim_assets` 中建立 Gazebo 11 world/model 引用入口。
5. 只在单机 Offboard 悬停闭环稳定后，再进入风机/电缆任务。

## 不允许事项

1. 不从零写低层飞控。
2. 不从零做风机、电塔、导线模型。
3. 不把 RL 接到电机或姿态内环。
4. 不把 `third_party/` 下的上游源码提交进主仓库。
5. 不在 PX4 Classic 兼容性未确认前启动多机阶段。
