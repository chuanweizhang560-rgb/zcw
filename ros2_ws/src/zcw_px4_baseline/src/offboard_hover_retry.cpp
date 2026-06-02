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
 * @brief PX4 Offboard hover baseline with command retries.
 *
 * This file is adapted from px4_ros_com's official offboard_control.cpp example.
 * Changes are limited to status subscription and repeated mode/arm commands for
 * deterministic SITL verification.
 */

#include <px4_msgs/msg/offboard_control_mode.hpp>
#include <px4_msgs/msg/trajectory_setpoint.hpp>
#include <px4_msgs/msg/vehicle_command.hpp>
#include <px4_msgs/msg/vehicle_status.hpp>
#include <rclcpp/rclcpp.hpp>

#include <chrono>
#include <cstdint>
#include <iostream>

using namespace std::chrono_literals;
using px4_msgs::msg::OffboardControlMode;
using px4_msgs::msg::TrajectorySetpoint;
using px4_msgs::msg::VehicleCommand;
using px4_msgs::msg::VehicleStatus;

class OffboardHoverRetry : public rclcpp::Node
{
public:
  OffboardHoverRetry() : Node("offboard_hover_retry")
  {
    auto qos_profile = rclcpp::QoS(rclcpp::KeepLast(1));
    qos_profile.best_effort();
    qos_profile.transient_local();

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

    timer_ = create_wall_timer(100ms, [this]() { timer_callback(); });
  }

private:
  rclcpp::TimerBase::SharedPtr timer_;

  rclcpp::Publisher<OffboardControlMode>::SharedPtr offboard_control_mode_publisher_;
  rclcpp::Publisher<TrajectorySetpoint>::SharedPtr trajectory_setpoint_publisher_;
  rclcpp::Publisher<VehicleCommand>::SharedPtr vehicle_command_publisher_;
  rclcpp::Subscription<VehicleStatus>::SharedPtr vehicle_status_subscriber_;

  VehicleStatus vehicle_status_{};
  bool have_vehicle_status_{false};
  uint64_t setpoint_counter_{0};

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

    RCLCPP_INFO_THROTTLE(get_logger(), *get_clock(), 5000, "Holding armed Offboard hover");
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
    TrajectorySetpoint msg{};
    msg.position = {0.0F, 0.0F, -5.0F};
    msg.yaw = -3.14F;
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
  std::cout << "Starting offboard hover retry node..." << std::endl;
  setvbuf(stdout, nullptr, _IONBF, BUFSIZ);
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<OffboardHoverRetry>());
  rclcpp::shutdown();
  return 0;
}
