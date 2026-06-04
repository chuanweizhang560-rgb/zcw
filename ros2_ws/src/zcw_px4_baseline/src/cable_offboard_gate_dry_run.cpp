#include <chrono>
#include <cmath>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

#include <geometry_msgs/msg/point_stamped.hpp>
#include <nav_msgs/msg/odometry.hpp>
#include <px4_msgs/msg/vehicle_local_position.hpp>
#include <px4_msgs/msg/vehicle_status.hpp>
#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/bool.hpp>
#include <std_msgs/msg/string.hpp>

namespace
{
bool finite_point(const geometry_msgs::msg::PointStamped & point)
{
  return std::isfinite(point.point.x) && std::isfinite(point.point.y) &&
         std::isfinite(point.point.z);
}

bool finite_pose(const nav_msgs::msg::Odometry & odom)
{
  const auto & p = odom.pose.pose.position;
  return std::isfinite(p.x) && std::isfinite(p.y) && std::isfinite(p.z);
}

double distance_xy(
  const geometry_msgs::msg::PointStamped & a,
  const geometry_msgs::msg::PointStamped & b)
{
  const double dx = b.point.x - a.point.x;
  const double dy = b.point.y - a.point.y;
  return std::sqrt(dx * dx + dy * dy);
}
}  // namespace

class CableOffboardGateDryRun : public rclcpp::Node
{
public:
  CableOffboardGateDryRun()
  : Node("cable_offboard_gate_dry_run")
  {
    max_candidate_age_sec_ = declare_parameter<double>("max_candidate_age_sec", 0.5);
    max_bridge_state_age_sec_ = declare_parameter<double>("max_bridge_state_age_sec", 0.5);
    max_vehicle_status_age_sec_ = declare_parameter<double>("max_vehicle_status_age_sec", 1.0);
    max_local_position_age_sec_ = declare_parameter<double>("max_local_position_age_sec", 1.0);
    max_gazebo_pose_age_sec_ = declare_parameter<double>("max_gazebo_pose_age_sec", 2.0);
    max_horizontal_jump_m_ = declare_parameter<double>("max_horizontal_jump_m", 2.5);
    max_vertical_jump_m_ = declare_parameter<double>("max_vertical_jump_m", 0.5);
    publish_hz_ = declare_parameter<double>("publish_hz", 5.0);
    phase_b_user_approved_ = declare_parameter<bool>("phase_b_user_approved", false);
    reset_abort_latch_ = declare_parameter<bool>("reset_abort_latch", false);

    if (max_candidate_age_sec_ <= 0.0 || max_bridge_state_age_sec_ <= 0.0 ||
      max_vehicle_status_age_sec_ <= 0.0 || max_local_position_age_sec_ <= 0.0 ||
      max_gazebo_pose_age_sec_ <= 0.0 || max_horizontal_jump_m_ < 0.0 ||
      max_vertical_jump_m_ < 0.0 || publish_hz_ <= 0.0)
    {
      throw std::runtime_error("invalid offboard gate dry-run parameter");
    }

    const auto px4_qos = rclcpp::SensorDataQoS();
    vehicle_status_sub_ = create_subscription<px4_msgs::msg::VehicleStatus>(
      "/fmu/out/vehicle_status", px4_qos,
      [this](px4_msgs::msg::VehicleStatus::SharedPtr msg) {
        latest_vehicle_status_ = msg;
        last_vehicle_status_time_ = now();
      });
    local_position_sub_ = create_subscription<px4_msgs::msg::VehicleLocalPosition>(
      "/fmu/out/vehicle_local_position", px4_qos,
      [this](px4_msgs::msg::VehicleLocalPosition::SharedPtr msg) {
        latest_local_position_ = msg;
        last_local_position_time_ = now();
      });
    gazebo_pose_sub_ = create_subscription<nav_msgs::msg::Odometry>(
      "/zcw/depth_camera/pose", 10,
      [this](nav_msgs::msg::Odometry::SharedPtr msg) {
        latest_gazebo_pose_ = msg;
        last_gazebo_pose_time_ = now();
      });
    bridge_state_sub_ = create_subscription<std_msgs::msg::String>(
      "/zcw/cable/px4_bridge/state", 10,
      [this](std_msgs::msg::String::SharedPtr msg) {
        latest_bridge_state_ = msg;
        last_bridge_state_time_ = now();
      });
    bridge_ned_sub_ = create_subscription<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/px4_bridge/ned_setpoint_dry_run", 10,
      [this](geometry_msgs::msg::PointStamped::SharedPtr msg) {
        latest_bridge_ned_ = msg;
        last_bridge_ned_time_ = now();
      });

    state_pub_ = create_publisher<std_msgs::msg::String>("/zcw/cable/offboard_gate/state", 10);
    phase_b_allowed_pub_ =
      create_publisher<std_msgs::msg::Bool>("/zcw/cable/offboard_gate/phase_b_allowed", 10);
    approved_ned_pub_ = create_publisher<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/offboard_gate/ned_setpoint_approved_dry_run", 10);

    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz_)),
      std::bind(&CableOffboardGateDryRun::publish_gate, this));
  }

private:
  bool fresh(const rclcpp::Time & stamp, const rclcpp::Time & t, double max_age_sec) const
  {
    return stamp.nanoseconds() > 0 && (t - stamp).seconds() <= max_age_sec;
  }

  void publish_gate()
  {
    const auto t = now();
    std::string state = "WAITING_FOR_INPUTS";
    std::string reason = "missing_inputs";
    double horizontal_jump_m = 0.0;
    double vertical_jump_m = 0.0;
    bool px4_ready = false;
    bool bridge_ready = false;
    bool candidate_ready = false;
    bool gazebo_ready = false;
    bool unexpected_armed = false;

    if (reset_abort_latch_) {
      abort_latched_ = false;
    }

    if (latest_vehicle_status_) {
      unexpected_armed =
        latest_vehicle_status_->arming_state == px4_msgs::msg::VehicleStatus::ARMING_STATE_ARMED;
      if (unexpected_armed) {
        abort_latched_ = true;
        abort_reason_ = "unexpected_armed_in_dry_run";
      }
    }

    if (!latest_bridge_state_ || !latest_bridge_ned_ || !latest_vehicle_status_ ||
      !latest_local_position_ || !latest_gazebo_pose_)
    {
      state = "WAITING_FOR_INPUTS";
      reason = "missing_inputs";
    } else {
      bridge_ready =
        fresh(last_bridge_state_time_, t, max_bridge_state_age_sec_) &&
        latest_bridge_state_->data.rfind("DRY_RUN_READY", 0) == 0;
      candidate_ready =
        fresh(last_bridge_ned_time_, t, max_candidate_age_sec_) &&
        finite_point(*latest_bridge_ned_);
      px4_ready =
        fresh(last_vehicle_status_time_, t, max_vehicle_status_age_sec_) &&
        fresh(last_local_position_time_, t, max_local_position_age_sec_) &&
        std::isfinite(latest_local_position_->x) &&
        std::isfinite(latest_local_position_->y) &&
        std::isfinite(latest_local_position_->z) &&
        latest_local_position_->xy_valid &&
        latest_local_position_->z_valid;
      gazebo_ready =
        fresh(last_gazebo_pose_time_, t, max_gazebo_pose_age_sec_) &&
        finite_pose(*latest_gazebo_pose_);

      if (!bridge_ready) {
        state = "HOLD_BRIDGE_NOT_READY";
        reason = "bridge_not_ready_or_stale";
      } else if (!candidate_ready) {
        abort_latched_ = true;
        abort_reason_ = "candidate_stale_or_nonfinite";
        state = "HOLD_ABORT";
        reason = abort_reason_;
      } else if (!px4_ready || !gazebo_ready) {
        state = "HOLD_PX4_NOT_READY";
        reason = "px4_or_gazebo_pose_not_ready";
      } else if (last_approved_ned_) {
        horizontal_jump_m = distance_xy(*last_approved_ned_, *latest_bridge_ned_);
        vertical_jump_m = std::abs(latest_bridge_ned_->point.z - last_approved_ned_->point.z);
        if (horizontal_jump_m > max_horizontal_jump_m_ ||
          vertical_jump_m > max_vertical_jump_m_)
        {
          abort_latched_ = true;
          abort_reason_ = "setpoint_jump_exceeded";
          state = "HOLD_ABORT";
          reason = abort_reason_;
        }
      }

      if (abort_latched_) {
        state = "HOLD_ABORT";
        reason = abort_reason_;
      } else if (bridge_ready && candidate_ready && px4_ready && gazebo_ready) {
        state = "PHASE_B_READY_DRY_RUN";
        reason = phase_b_user_approved_ ? "user_approved_but_dry_run_executable" :
          "user_not_approved_dry_run_only";
        last_approved_ned_ =
          std::make_shared<geometry_msgs::msg::PointStamped>(*latest_bridge_ned_);
        approved_ned_pub_->publish(*latest_bridge_ned_);
      }
    }

    std_msgs::msg::Bool allowed_msg;
    allowed_msg.data = false;
    phase_b_allowed_pub_->publish(allowed_msg);

    std_msgs::msg::String state_msg;
    std::ostringstream out;
    out << state
        << "; reason=" << reason
        << "; phase_b_allowed=false"
        << "; publishes_fmu_in=false"
        << "; user_approved=" << (phase_b_user_approved_ ? "true" : "false")
        << "; bridge_ready=" << (bridge_ready ? "true" : "false")
        << "; candidate_ready=" << (candidate_ready ? "true" : "false")
        << "; px4_ready=" << (px4_ready ? "true" : "false")
        << "; gazebo_ready=" << (gazebo_ready ? "true" : "false")
        << "; abort_latched=" << (abort_latched_ ? "true" : "false")
        << "; horizontal_jump_m=" << horizontal_jump_m
        << "; vertical_jump_m=" << vertical_jump_m;
    state_msg.data = out.str();
    state_pub_->publish(state_msg);
  }

  double max_candidate_age_sec_{0.5};
  double max_bridge_state_age_sec_{0.5};
  double max_vehicle_status_age_sec_{1.0};
  double max_local_position_age_sec_{1.0};
  double max_gazebo_pose_age_sec_{2.0};
  double max_horizontal_jump_m_{2.5};
  double max_vertical_jump_m_{0.5};
  double publish_hz_{5.0};
  bool phase_b_user_approved_{false};
  bool reset_abort_latch_{false};
  bool abort_latched_{false};
  std::string abort_reason_{"none"};
  rclcpp::Time last_vehicle_status_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_local_position_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_gazebo_pose_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_bridge_state_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_bridge_ned_time_{0, 0, RCL_ROS_TIME};
  px4_msgs::msg::VehicleStatus::SharedPtr latest_vehicle_status_;
  px4_msgs::msg::VehicleLocalPosition::SharedPtr latest_local_position_;
  nav_msgs::msg::Odometry::SharedPtr latest_gazebo_pose_;
  std_msgs::msg::String::SharedPtr latest_bridge_state_;
  geometry_msgs::msg::PointStamped::SharedPtr latest_bridge_ned_;
  geometry_msgs::msg::PointStamped::SharedPtr last_approved_ned_;
  rclcpp::Subscription<px4_msgs::msg::VehicleStatus>::SharedPtr vehicle_status_sub_;
  rclcpp::Subscription<px4_msgs::msg::VehicleLocalPosition>::SharedPtr local_position_sub_;
  rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr gazebo_pose_sub_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr bridge_state_sub_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr bridge_ned_sub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr state_pub_;
  rclcpp::Publisher<std_msgs::msg::Bool>::SharedPtr phase_b_allowed_pub_;
  rclcpp::Publisher<geometry_msgs::msg::PointStamped>::SharedPtr approved_ned_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<CableOffboardGateDryRun>());
  } catch (const std::exception & e) {
    std::cerr << "cable_offboard_gate_dry_run error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
