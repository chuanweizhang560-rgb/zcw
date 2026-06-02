# 执行手册

更新时间：2026-06-02 13:07:50 CST

本文件记录当前仓库的可执行入口和下一步操作顺序。

## 当前阶段

阶段 1：开源资产与上游项目审计。

当前不启动仿真，不训练 RL，不实现控制算法。

## 已确认环境

```text
Ubuntu 22.04.5 LTS
ROS 2 Humble
Gazebo Classic 11.10.2
```

## 本地第三方仓库

第一批外部候选已克隆到 `third_party/`，但不会提交进主仓库。版本和许可证见 `OPEN_SOURCE_AUDIT.md`。

## 下一步执行顺序

1. 复核 PX4 Classic 在 Ubuntu 22.04 + Gazebo 11 上是否能编译/运行。
2. 确认 `px4_msgs` / `px4_ros_com` 与选定 PX4 版本的分支。
3. 在 `ros2_ws/src/zcw_bringup` 中建立 PX4 Offboard launch 入口。
4. 在 `ros2_ws/src/zcw_sim_assets` 中建立 Gazebo 11 world/model 引用入口。
5. 只在单机 Offboard 悬停闭环稳定后，再进入风机/电缆任务。

## 不允许事项

1. 不从零写低层飞控。
2. 不从零做风机、电塔、导线模型。
3. 不把 RL 接到电机或姿态内环。
4. 不把 `third_party/` 下的上游源码提交进主仓库。
5. 不在 PX4 Classic 兼容性未确认前启动多机阶段。
