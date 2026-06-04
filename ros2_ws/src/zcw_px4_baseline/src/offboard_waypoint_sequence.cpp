/****************************************************************************
 *
 * Copyright 2020 PX4 Development Team. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 * list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software without
 * specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 ****************************************************************************/

/**
 * @brief PX4 Offboard waypoint-sequence baseline.
 *
 * This file is adapted from px4_ros_com's official offboard_control.cpp example.
 * It stays at the position-setpoint layer and lets PX4 handle vehicle control.
 */

#include <px4_msgs/msg/offboard_control_mode.hpp>
#include <px4_msgs/msg/trajectory_setpoint.hpp>
#include <px4_msgs/msg/vehicle_command.hpp>
#include <px4_msgs/msg/vehicle_local_position.hpp>
#include <px4_msgs/msg/vehicle_status.hpp>
#include <rclcpp/rclcpp.hpp>

#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace std::chrono_literals;
using px4_msgs::msg::OffboardControlMode;
using px4_msgs::msg::TrajectorySetpoint;
using px4_msgs::msg::VehicleCommand;
using px4_msgs::msg::VehicleLocalPosition;
using px4_msgs::msg::VehicleStatus;

class OffboardWaypointSequence : public rclcpp::Node
{
public:
  OffboardWaypointSequence() : Node("offboard_waypoint_sequence")
  {
    auto qos_profile = rclcpp::QoS(rclcpp::KeepLast(1));
    qos_profile.best_effort();
    qos_profile.transient_local();

    const auto flat_waypoints = declare_parameter<std::vector<double>>(
      "waypoints_ned",
      std::vector<double>{0.0, 0.0, -5.0, 8.0, 0.0, -5.0, 8.0, 8.0, -5.0, 0.0, 8.0, -5.0, 0.0, 0.0, -5.0});
    const auto yaws = declare_parameter<std::vector<double>>("yaws_rad", std::vector<double>{});
    acceptance_radius_m_ = declare_parameter<double>("acceptance_radius_m", 1.0);
    hold_ticks_required_ = declare_parameter<int>("hold_ticks_required", 15);

    if (flat_waypoints.size() < 3 || flat_waypoints.size() % 3 != 0) {
      throw std::runtime_error("waypoints_ned must contain triples: x y z");
    }
    if (!yaws.empty() && yaws.size() != flat_waypoints.size() / 3) {
      throw std::runtime_error("yaws_rad must be empty or contain one yaw per waypoint");
    }

    for (std::size_t i = 0; i < flat_waypoints.size(); i += 3) {
      waypoints_.push_back({
        static_cast<float>(flat_waypoints[i]),
        static_cast<float>(flat_waypoints[i + 1]),
        static_cast<float>(flat_waypoints[i + 2])});
    }
    for (const auto yaw : yaws) {
      yaws_.push_back(static_cast<float>(yaw));
    }
    if (yaws_.empty()) {
      yaws_.assign(waypoints_.size(), 0.0F);
    }

    offboard_control_mode_publisher_ =
      create_publisher<OffboardControlMode>("/fmu/in/offboard_control_mode", qos_profile);
    trajectory_setpoint_publisher_ =
      create_publisher<TrajectorySetpoint>("/fmu/in/trajectory_setpoint", qos_profile);
    vehicle_command_publisher_ =
      create_publisher<VehicleCommand>("/fmu/in/vehicle_command", qos_profile);

    vehicle_status_subscriber_ = create_subscription<VehicleStatus>(
      "/fmu/out/vehicle_status", qos_profile,
      [this](const VehicleStatus::SharedPtr msg) {
        vehicle_status_ = *msg;
        have_vehicle_status_ = true;
      });

    vehicle_local_position_subscriber_ = create_subscription<VehicleLocalPosition>(
      "/fmu/out/vehicle_local_position", qos_profile,
      [this](const VehicleLocalPosition::SharedPtr msg) {
        vehicle_local_position_ = *msg;
        have_local_position_ = true;
      });

    timer_ = create_wall_timer(100ms, [this]() { timer_callback(); });
  }

private:
  rclcpp::TimerBase::SharedPtr timer_;

  rclcpp::Publisher<OffboardControlMode>::SharedPtr offboard_control_mode_publisher_;
  rclcpp::Publisher<TrajectorySetpoint>::SharedPtr trajectory_setpoint_publisher_;
  rclcpp::Publisher<VehicleCommand>::SharedPtr vehicle_command_publisher_;
  rclcpp::Subscription<VehicleStatus>::SharedPtr vehicle_status_subscriber_;
  rclcpp::Subscription<VehicleLocalPosition>::SharedPtr vehicle_local_position_subscriber_;

  VehicleStatus vehicle_status_{};
  VehicleLocalPosition vehicle_local_position_{};
  bool have_vehicle_status_{false};
  bool have_local_position_{false};
  uint64_t setpoint_counter_{0};

  std::vector<std::array<float, 3>> waypoints_;
  std::vector<float> yaws_;
  std::size_t waypoint_index_{0};
  double acceptance_radius_m_{1.0};
  int hold_ticks_required_{15};
  int hold_ticks_{0};

  void timer_callback()
  {
    publish_offboard_control_mode();
    publish_trajectory_setpoint();

    if (setpoint_counter_ < 10) {
      setpoint_counter_++;
      return;
    }

    if (!have_vehicle_status_ ||
        vehicle_status_.nav_state != VehicleStatus::NAVIGATION_STATE_OFFBOARD) {
      publish_vehicle_command(VehicleCommand::VEHICLE_CMD_DO_SET_MODE, 1.0F, 6.0F);
      RCLCPP_INFO_THROTTLE(
        get_logger(), *get_clock(), 2000, "Requesting Offboard mode");
      return;
    }

    if (vehicle_status_.arming_state != VehicleStatus::ARMING_STATE_ARMED) {
      publish_vehicle_command(VehicleCommand::VEHICLE_CMD_COMPONENT_ARM_DISARM, 1.0F);
      RCLCPP_INFO_THROTTLE(get_logger(), *get_clock(), 2000, "Requesting arm");
      return;
    }

    update_waypoint_progress();
  }

  void update_waypoint_progress()
  {
    if (!have_local_position_ || waypoint_index_ >= waypoints_.size()) {
      return;
    }

    const auto & target = waypoints_[waypoint_index_];
    const double dx = static_cast<double>(vehicle_local_position_.x) - target[0];
    const double dy = static_cast<double>(vehicle_local_position_.y) - target[1];
    const double dz = static_cast<double>(vehicle_local_position_.z) - target[2];
    const double distance = std::sqrt(dx * dx + dy * dy + dz * dz);

    if (distance <= acceptance_radius_m_) {
      hold_ticks_++;
    } else {
      hold_ticks_ = 0;
    }

    if (hold_ticks_ >= hold_ticks_required_ && waypoint_index_ + 1 < waypoints_.size()) {
      waypoint_index_++;
      hold_ticks_ = 0;
      const auto & next_target = waypoints_[waypoint_index_];
      RCLCPP_INFO(
        get_logger(), "Advancing to waypoint %zu: [%.2f, %.2f, %.2f], yaw %.2f",
        waypoint_index_, next_target[0], next_target[1], next_target[2], yaws_[waypoint_index_]);
    } else if (waypoint_index_ + 1 == waypoints_.size()) {
      RCLCPP_INFO_THROTTLE(
        get_logger(), *get_clock(), 5000, "Holding final waypoint %zu", waypoint_index_);
    }
  }

  void publish_offboard_control_mode()
  {
    OffboardControlMode msg{};
    msg.position = true;
    msg.velocity = false;
    msg.acceleration = false;
    msg.attitude = false;
    msg.body_rate = false;
    msg.timestamp = now_us();
    offboard_control_mode_publisher_->publish(msg);
  }

  void publish_trajectory_setpoint()
  {
    const auto & target = waypoints_[waypoint_index_];
    TrajectorySetpoint msg{};
    msg.position = {target[0], target[1], target[2]};
    msg.yaw = yaws_[waypoint_index_];
    msg.timestamp = now_us();
    trajectory_setpoint_publisher_->publish(msg);
  }

  void publish_vehicle_command(uint16_t command, float param1 = 0.0F, float param2 = 0.0F)
  {
    VehicleCommand msg{};
    msg.param1 = param1;
    msg.param2 = param2;
    msg.command = command;
    msg.target_system = 1;
    msg.target_component = 1;
    msg.source_system = 1;
    msg.source_component = 1;
    msg.from_external = true;
    msg.timestamp = now_us();
    vehicle_command_publisher_->publish(msg);
  }

  uint64_t now_us()
  {
    return get_clock()->now().nanoseconds() / 1000;
  }
};

int main(int argc, char * argv[])
{
  std::cout << "Starting offboard waypoint sequence node..." << std::endl;
  setvbuf(stdout, nullptr, _IONBF, BUFSIZ);
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<OffboardWaypointSequence>());
  rclcpp::shutdown();
  return 0;
}
