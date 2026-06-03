#include <chrono>
#include <cmath>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>

#include <geometry_msgs/msg/point_stamped.hpp>
#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/string.hpp>

namespace
{
bool finite_point(const geometry_msgs::msg::PointStamped & point)
{
  return std::isfinite(point.point.x) && std::isfinite(point.point.y) &&
         std::isfinite(point.point.z);
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

class CablePx4BridgeDryRun : public rclcpp::Node
{
public:
  CablePx4BridgeDryRun()
  : Node("cable_px4_bridge_dry_run")
  {
    max_candidate_age_sec_ = declare_parameter<double>("max_candidate_age_sec", 0.5);
    max_state_age_sec_ = declare_parameter<double>("max_state_age_sec", 0.5);
    max_ned_horizontal_jump_m_ = declare_parameter<double>("max_ned_horizontal_jump_m", 5.0);
    max_ned_vertical_jump_m_ = declare_parameter<double>("max_ned_vertical_jump_m", 2.0);
    publish_hz_ = declare_parameter<double>("publish_hz", 5.0);

    if (max_candidate_age_sec_ <= 0.0 || max_state_age_sec_ <= 0.0 ||
      max_ned_horizontal_jump_m_ < 0.0 || max_ned_vertical_jump_m_ < 0.0 ||
      publish_hz_ <= 0.0)
    {
      throw std::runtime_error("invalid bridge dry-run parameter");
    }

    candidate_sub_ = create_subscription<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/dry_run/candidate_setpoint", 10,
      [this](geometry_msgs::msg::PointStamped::SharedPtr msg) {
        latest_candidate_ = msg;
        last_candidate_time_ = now();
      });
    state_sub_ = create_subscription<std_msgs::msg::String>(
      "/zcw/cable/dry_run/state", 10,
      [this](std_msgs::msg::String::SharedPtr msg) {
        latest_state_ = msg;
        last_state_time_ = now();
      });

    bridge_state_pub_ = create_publisher<std_msgs::msg::String>("/zcw/cable/px4_bridge/state", 10);
    ned_setpoint_pub_ = create_publisher<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/px4_bridge/ned_setpoint_dry_run", 10);

    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz_)),
      std::bind(&CablePx4BridgeDryRun::publish_dry_run, this));
  }

private:
  void publish_dry_run()
  {
    const auto t = now();
    std::string state = "WAITING";
    double horizontal_jump_m = 0.0;
    double vertical_jump_m = 0.0;

    if (!latest_candidate_ || !latest_state_) {
      state = "WAITING";
    } else if ((t - last_candidate_time_).seconds() > max_candidate_age_sec_ ||
      (t - last_state_time_).seconds() > max_state_age_sec_)
    {
      state = "HOLD_STALE_DATA";
    } else if (latest_state_->data.rfind("TRACK_READY", 0) != 0) {
      state = "HOLD_DRY_RUN_STATE";
    } else if (!finite_point(*latest_candidate_)) {
      state = "HOLD_NONFINITE_CANDIDATE";
    } else {
      geometry_msgs::msg::PointStamped ned = map_to_debug_ned(*latest_candidate_, t);
      if (last_ned_setpoint_) {
        horizontal_jump_m = distance_xy(*last_ned_setpoint_, ned);
        vertical_jump_m = std::abs(ned.point.z - last_ned_setpoint_->point.z);
      }

      if (horizontal_jump_m > max_ned_horizontal_jump_m_) {
        state = "HOLD_NED_HORIZONTAL_JUMP";
      } else if (vertical_jump_m > max_ned_vertical_jump_m_) {
        state = "HOLD_NED_VERTICAL_JUMP";
      } else {
        state = "DRY_RUN_READY";
        last_ned_setpoint_ = std::make_shared<geometry_msgs::msg::PointStamped>(ned);
        ned_setpoint_pub_->publish(ned);
      }
    }

    std_msgs::msg::String state_msg;
    std::ostringstream out;
    out << state
        << "; phase=PHASE_A_DRY_RUN"
        << "; publishes_fmu_in=false"
        << "; map_to_ned=debug_x_y_neg_z"
        << "; horizontal_jump_m=" << horizontal_jump_m
        << "; vertical_jump_m=" << vertical_jump_m;
    state_msg.data = out.str();
    bridge_state_pub_->publish(state_msg);
  }

  geometry_msgs::msg::PointStamped map_to_debug_ned(
    const geometry_msgs::msg::PointStamped & map_point,
    const rclcpp::Time & stamp) const
  {
    geometry_msgs::msg::PointStamped ned;
    ned.header.stamp = stamp;
    ned.header.frame_id = "px4_local_ned_dry_run";
    ned.point.x = map_point.point.x;
    ned.point.y = map_point.point.y;
    ned.point.z = -map_point.point.z;
    return ned;
  }

  double max_candidate_age_sec_{0.5};
  double max_state_age_sec_{0.5};
  double max_ned_horizontal_jump_m_{5.0};
  double max_ned_vertical_jump_m_{2.0};
  double publish_hz_{5.0};
  rclcpp::Time last_candidate_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_state_time_{0, 0, RCL_ROS_TIME};
  geometry_msgs::msg::PointStamped::SharedPtr latest_candidate_;
  std_msgs::msg::String::SharedPtr latest_state_;
  geometry_msgs::msg::PointStamped::SharedPtr last_ned_setpoint_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr candidate_sub_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr state_sub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr bridge_state_pub_;
  rclcpp::Publisher<geometry_msgs::msg::PointStamped>::SharedPtr ned_setpoint_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<CablePx4BridgeDryRun>());
  } catch (const std::exception & e) {
    std::cerr << "cable_px4_bridge_dry_run error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
