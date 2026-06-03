#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
#include <memory>
#include <sstream>
#include <string>

#include "geometry_msgs/msg/point_stamped.hpp"
#include "nav_msgs/msg/path.hpp"
#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/bool.hpp"
#include "std_msgs/msg/string.hpp"

using namespace std::chrono_literals;

namespace
{
double point_distance(
  const geometry_msgs::msg::Point & a,
  const geometry_msgs::msg::Point & b)
{
  const double dx = b.x - a.x;
  const double dy = b.y - a.y;
  const double dz = b.z - a.z;
  return std::sqrt(dx * dx + dy * dy + dz * dz);
}
}  // namespace

class LookaheadSafetyMonitor : public rclcpp::Node
{
public:
  LookaheadSafetyMonitor()
  : Node("lookahead_safety_monitor")
  {
    min_path_points_ = declare_parameter<int>("min_path_points", 3);
    max_target_to_path_m_ = declare_parameter<double>("max_target_to_path_m", 2.0);
    max_target_jump_m_ = declare_parameter<double>("max_target_jump_m", 25.0);
    max_data_age_sec_ = declare_parameter<double>("max_data_age_sec", 3.0);
    publish_hz_ = declare_parameter<double>("publish_hz", 5.0);

    if (min_path_points_ <= 0 || max_target_to_path_m_ < 0.0 ||
      max_target_jump_m_ < 0.0 || max_data_age_sec_ <= 0.0 || publish_hz_ <= 0.0)
    {
      throw std::runtime_error("invalid safety monitor parameter");
    }

    path_sub_ = create_subscription<nav_msgs::msg::Path>(
      "/zcw/cable/offset_path", rclcpp::QoS(1).transient_local().reliable(),
      [this](nav_msgs::msg::Path::SharedPtr msg) {
        latest_path_ = msg;
        last_path_time_ = now();
      });
    target_sub_ = create_subscription<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/lookahead_target", rclcpp::QoS(10),
      [this](geometry_msgs::msg::PointStamped::SharedPtr msg) {
        if (latest_target_) {
          last_target_jump_m_ = point_distance(latest_target_->point, msg->point);
        }
        latest_target_ = msg;
        last_target_time_ = now();
      });

    state_pub_ = create_publisher<std_msgs::msg::String>("/zcw/cable/tracking_state", 10);
    gate_pub_ = create_publisher<std_msgs::msg::Bool>("/zcw/cable/safety_gate", 10);
    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz_)),
      std::bind(&LookaheadSafetyMonitor::publish_state, this));
  }

private:
  void publish_state()
  {
    const auto t = now();
    std::string state = "WAITING_FOR_DATA";
    bool gate = false;
    double min_target_to_path_m = std::numeric_limits<double>::infinity();

    if (!latest_path_ || !latest_target_) {
      state = "WAITING_FOR_DATA";
    } else if (latest_path_->poses.size() < static_cast<std::size_t>(min_path_points_)) {
      state = "HOLD_PATH_TOO_SHORT";
    } else if ((t - last_path_time_).seconds() > max_data_age_sec_ ||
      (t - last_target_time_).seconds() > max_data_age_sec_)
    {
      state = "HOLD_STALE_DATA";
    } else {
      for (const auto & pose : latest_path_->poses) {
        min_target_to_path_m = std::min(
          min_target_to_path_m,
          point_distance(pose.pose.position, latest_target_->point));
      }
      if (min_target_to_path_m > max_target_to_path_m_) {
        state = "HOLD_TARGET_OFF_PATH";
      } else if (last_target_jump_m_ > max_target_jump_m_) {
        state = "HOLD_TARGET_JUMP";
      } else {
        state = "TRACK_READY";
        gate = true;
      }
    }

    std_msgs::msg::String state_msg;
    std::ostringstream out;
    out << state
        << "; path_points=" << (latest_path_ ? latest_path_->poses.size() : 0)
        << "; target_received=" << (latest_target_ ? "true" : "false")
        << "; min_target_to_path_m=";
    if (std::isfinite(min_target_to_path_m)) {
      out << min_target_to_path_m;
    } else {
      out << "nan";
    }
    out << "; last_target_jump_m=" << last_target_jump_m_;
    state_msg.data = out.str();
    state_pub_->publish(state_msg);

    std_msgs::msg::Bool gate_msg;
    gate_msg.data = gate;
    gate_pub_->publish(gate_msg);
  }

  int min_path_points_{3};
  double max_target_to_path_m_{2.0};
  double max_target_jump_m_{25.0};
  double max_data_age_sec_{3.0};
  double publish_hz_{5.0};
  double last_target_jump_m_{0.0};
  rclcpp::Time last_path_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_target_time_{0, 0, RCL_ROS_TIME};
  nav_msgs::msg::Path::SharedPtr latest_path_;
  geometry_msgs::msg::PointStamped::SharedPtr latest_target_;
  rclcpp::Subscription<nav_msgs::msg::Path>::SharedPtr path_sub_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr target_sub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr state_pub_;
  rclcpp::Publisher<std_msgs::msg::Bool>::SharedPtr gate_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<LookaheadSafetyMonitor>());
  } catch (const std::exception & e) {
    std::cerr << "lookahead_safety_monitor error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
