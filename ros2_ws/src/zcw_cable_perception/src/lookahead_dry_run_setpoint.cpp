#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
#include <memory>
#include <sstream>
#include <string>

#include "geometry_msgs/msg/point.hpp"
#include "geometry_msgs/msg/point_stamped.hpp"
#include "geometry_msgs/msg/pose_stamped.hpp"
#include "nav_msgs/msg/path.hpp"
#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/bool.hpp"
#include "std_msgs/msg/string.hpp"

namespace
{
double distance(const geometry_msgs::msg::Point & a, const geometry_msgs::msg::Point & b)
{
  const double dx = b.x - a.x;
  const double dy = b.y - a.y;
  const double dz = b.z - a.z;
  return std::sqrt(dx * dx + dy * dy + dz * dz);
}

geometry_msgs::msg::PoseStamped point_to_pose(
  const geometry_msgs::msg::PointStamped & point,
  const rclcpp::Time & stamp)
{
  geometry_msgs::msg::PoseStamped pose;
  pose.header = point.header;
  pose.header.stamp = stamp;
  pose.pose.position = point.point;
  pose.pose.orientation.w = 1.0;
  return pose;
}

geometry_msgs::msg::Point step_toward(
  const geometry_msgs::msg::Point & from,
  const geometry_msgs::msg::Point & to,
  double max_step_m)
{
  const double d = distance(from, to);
  if (d <= max_step_m || d <= 1e-9) {
    return to;
  }
  geometry_msgs::msg::Point out;
  const double ratio = max_step_m / d;
  out.x = from.x + (to.x - from.x) * ratio;
  out.y = from.y + (to.y - from.y) * ratio;
  out.z = from.z + (to.z - from.z) * ratio;
  return out;
}
}  // namespace

class LookaheadDryRunSetpoint : public rclcpp::Node
{
public:
  LookaheadDryRunSetpoint()
  : Node("lookahead_dry_run_setpoint")
  {
    max_target_to_path_m_ = declare_parameter<double>("max_target_to_path_m", 2.0);
    max_candidate_jump_m_ = declare_parameter<double>("max_candidate_jump_m", 5.0);
    max_vertical_jump_m_ = declare_parameter<double>("max_vertical_jump_m", 2.0);
    max_candidate_speed_mps_ = declare_parameter<double>("max_candidate_speed_mps", 5.0);
    max_data_age_sec_ = declare_parameter<double>("max_data_age_sec", 1.0);
    max_history_points_ = declare_parameter<int>("max_history_points", 100);
    publish_hz_ = declare_parameter<double>("publish_hz", 5.0);

    if (max_target_to_path_m_ < 0.0 || max_candidate_jump_m_ < 0.0 ||
      max_vertical_jump_m_ < 0.0 || max_candidate_speed_mps_ < 0.0 ||
      max_data_age_sec_ <= 0.0 || max_history_points_ <= 0 || publish_hz_ <= 0.0)
    {
      throw std::runtime_error("invalid dry-run parameter");
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
        latest_target_ = msg;
        last_target_time_ = now();
      });
    state_sub_ = create_subscription<std_msgs::msg::String>(
      "/zcw/cable/tracking_state", rclcpp::QoS(10),
      [this](std_msgs::msg::String::SharedPtr msg) {
        latest_tracking_state_ = msg;
        last_state_time_ = now();
      });
    gate_sub_ = create_subscription<std_msgs::msg::Bool>(
      "/zcw/cable/safety_gate", rclcpp::QoS(10),
      [this](std_msgs::msg::Bool::SharedPtr msg) {
        latest_safety_gate_ = msg;
        last_gate_time_ = now();
      });

    state_pub_ = create_publisher<std_msgs::msg::String>("/zcw/cable/dry_run/state", 10);
    candidate_pub_ = create_publisher<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/dry_run/candidate_setpoint", 10);
    history_pub_ = create_publisher<nav_msgs::msg::Path>("/zcw/cable/dry_run/path", 10);

    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz_)),
      std::bind(&LookaheadDryRunSetpoint::publish_dry_run, this));
  }

private:
  void publish_dry_run()
  {
    const auto t = now();
    std::string state = "WAITING";
    double target_to_path_m = std::numeric_limits<double>::infinity();
    double candidate_jump_m = 0.0;
    double candidate_vertical_jump_m = 0.0;
    double candidate_speed_mps = 0.0;

    if (!latest_path_ || !latest_target_ || !latest_tracking_state_ || !latest_safety_gate_) {
      state = "WAITING";
    } else if (!fresh(t, last_path_time_) || !fresh(t, last_target_time_) ||
      !fresh(t, last_state_time_) || !fresh(t, last_gate_time_))
    {
      state = "HOLD_STALE_DATA";
    } else if (!latest_safety_gate_->data) {
      state = "HOLD_SAFETY_GATE_FALSE";
    } else if (latest_tracking_state_->data.rfind("TRACK_READY", 0) != 0) {
      state = "HOLD_TRACKING_STATE";
    } else if (latest_path_->poses.empty()) {
      state = "HOLD_EMPTY_PATH";
    } else {
      target_to_path_m = min_target_to_path_distance();
      if (target_to_path_m > max_target_to_path_m_) {
        state = "HOLD_TARGET_OFF_PATH";
      } else {
        const double dt = last_candidate_time_.nanoseconds() > 0 ?
          std::max((t - last_candidate_time_).seconds(), 1e-6) : 1.0;
        geometry_msgs::msg::PointStamped candidate = *latest_target_;
        candidate.header.stamp = t;
        if (last_candidate_) {
          const double max_speed_step_m = max_candidate_speed_mps_ * dt;
          const double max_step_m = std::min(max_candidate_jump_m_, max_speed_step_m);
          candidate.point = step_toward(last_candidate_->point, latest_target_->point, max_step_m);
        }
        candidate_jump_m = last_candidate_ ? distance(last_candidate_->point, candidate.point) : 0.0;
        candidate_vertical_jump_m = last_candidate_ ?
          std::abs(candidate.point.z - last_candidate_->point.z) : 0.0;
        candidate_speed_mps = candidate_jump_m / dt;

        if (candidate_vertical_jump_m > max_vertical_jump_m_) {
          state = "HOLD_VERTICAL_JUMP";
        } else if (candidate_speed_mps > max_candidate_speed_mps_) {
          state = "HOLD_CANDIDATE_SPEED";
        } else {
          state = "TRACK_READY";
          last_candidate_ = std::make_shared<geometry_msgs::msg::PointStamped>(candidate);
          last_candidate_time_ = t;
          append_history(*last_candidate_);
          candidate_pub_->publish(*last_candidate_);
        }
      }
    }

    std_msgs::msg::String msg;
    std::ostringstream out;
    out << state
        << "; target_to_path_m=" << printable(target_to_path_m)
        << "; candidate_jump_m=" << candidate_jump_m
        << "; candidate_vertical_jump_m=" << candidate_vertical_jump_m
        << "; candidate_speed_mps=" << candidate_speed_mps
        << "; publishes_px4=false";
    msg.data = out.str();
    state_pub_->publish(msg);
    history_pub_->publish(history_);
  }

  bool fresh(const rclcpp::Time & t, const rclcpp::Time & last) const
  {
    return last.nanoseconds() > 0 && (t - last).seconds() <= max_data_age_sec_;
  }

  double min_target_to_path_distance() const
  {
    double out = std::numeric_limits<double>::infinity();
    for (const auto & pose : latest_path_->poses) {
      out = std::min(out, distance(pose.pose.position, latest_target_->point));
    }
    return out;
  }

  std::string printable(double value) const
  {
    if (!std::isfinite(value)) {
      return "nan";
    }
    std::ostringstream out;
    out << value;
    return out.str();
  }

  void append_history(const geometry_msgs::msg::PointStamped & point)
  {
    history_.header = point.header;
    history_.poses.push_back(point_to_pose(point, point.header.stamp));
    while (history_.poses.size() > static_cast<std::size_t>(max_history_points_)) {
      history_.poses.erase(history_.poses.begin());
    }
  }

  double max_target_to_path_m_{2.0};
  double max_candidate_jump_m_{5.0};
  double max_vertical_jump_m_{2.0};
  double max_candidate_speed_mps_{5.0};
  double max_data_age_sec_{1.0};
  int max_history_points_{100};
  double publish_hz_{5.0};
  rclcpp::Time last_path_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_target_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_state_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_gate_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_candidate_time_{0, 0, RCL_ROS_TIME};
  nav_msgs::msg::Path::SharedPtr latest_path_;
  geometry_msgs::msg::PointStamped::SharedPtr latest_target_;
  std_msgs::msg::String::SharedPtr latest_tracking_state_;
  std_msgs::msg::Bool::SharedPtr latest_safety_gate_;
  geometry_msgs::msg::PointStamped::SharedPtr last_candidate_;
  nav_msgs::msg::Path history_;
  rclcpp::Subscription<nav_msgs::msg::Path>::SharedPtr path_sub_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr target_sub_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr state_sub_;
  rclcpp::Subscription<std_msgs::msg::Bool>::SharedPtr gate_sub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr state_pub_;
  rclcpp::Publisher<geometry_msgs::msg::PointStamped>::SharedPtr candidate_pub_;
  rclcpp::Publisher<nav_msgs::msg::Path>::SharedPtr history_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<LookaheadDryRunSetpoint>());
  } catch (const std::exception & e) {
    std::cerr << "lookahead_dry_run_setpoint error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
