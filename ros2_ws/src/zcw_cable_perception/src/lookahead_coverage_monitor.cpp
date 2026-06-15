#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_set>

#include "geometry_msgs/msg/point.hpp"
#include "geometry_msgs/msg/point_stamped.hpp"
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

std::string printable(double value)
{
  if (!std::isfinite(value)) {
    return "nan";
  }
  std::ostringstream out;
  out << value;
  return out.str();
}
}  // namespace

class LookaheadCoverageMonitor : public rclcpp::Node
{
public:
  LookaheadCoverageMonitor()
  : Node("lookahead_coverage_monitor")
  {
    min_coverage_ratio_ = declare_parameter<double>("min_coverage_ratio", 0.80);
    max_target_to_path_m_ = declare_parameter<double>("max_target_to_path_m", 2.0);
    max_data_age_sec_ = declare_parameter<double>("max_data_age_sec", 3.0);
    publish_hz_ = declare_parameter<double>("publish_hz", 5.0);

    if (min_coverage_ratio_ < 0.0 || min_coverage_ratio_ > 1.0 ||
      max_target_to_path_m_ < 0.0 || max_data_age_sec_ <= 0.0 || publish_hz_ <= 0.0)
    {
      throw std::runtime_error("invalid coverage monitor parameter");
    }

    path_sub_ = create_subscription<nav_msgs::msg::Path>(
      "/zcw/cable/offset_path", rclcpp::QoS(1).transient_local().reliable(),
      [this](nav_msgs::msg::Path::SharedPtr msg) {
        const auto signature = path_signature(*msg);
        if (signature != latest_path_signature_) {
          covered_indices_.clear();
          target_samples_ = 0;
          latest_path_signature_ = signature;
        }
        latest_path_ = msg;
        last_path_time_ = now();
      });
    target_sub_ = create_subscription<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/lookahead_target", rclcpp::QoS(10),
      [this](geometry_msgs::msg::PointStamped::SharedPtr msg) {
        latest_target_ = msg;
        ++target_samples_;
        last_target_time_ = now();
        update_coverage(*msg);
      });
    tracking_sub_ = create_subscription<std_msgs::msg::String>(
      "/zcw/cable/tracking_state", rclcpp::QoS(10),
      [this](std_msgs::msg::String::SharedPtr msg) {
        latest_tracking_state_ = msg;
        last_tracking_time_ = now();
      });
    gate_sub_ = create_subscription<std_msgs::msg::Bool>(
      "/zcw/cable/safety_gate", rclcpp::QoS(10),
      [this](std_msgs::msg::Bool::SharedPtr msg) {
        latest_safety_gate_ = msg;
        last_gate_time_ = now();
      });

    coverage_pub_ = create_publisher<std_msgs::msg::String>(
      "/zcw/cable/dry_run/coverage_state", 10);
    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz_)),
      std::bind(&LookaheadCoverageMonitor::publish_state, this));
  }

private:
  void update_coverage(const geometry_msgs::msg::PointStamped & target)
  {
    if (!latest_path_ || latest_path_->poses.empty()) {
      return;
    }

    double best_distance = std::numeric_limits<double>::infinity();
    std::size_t best_index = 0;
    for (std::size_t i = 0; i < latest_path_->poses.size(); ++i) {
      const double d = distance(latest_path_->poses[i].pose.position, target.point);
      if (d < best_distance) {
        best_distance = d;
        best_index = i;
      }
    }
    last_target_to_path_m_ = best_distance;
    if (best_distance <= max_target_to_path_m_) {
      covered_indices_.insert(best_index);
    }
  }

  bool fresh(const rclcpp::Time & t, const rclcpp::Time & last) const
  {
    return last.nanoseconds() > 0 && (t - last).seconds() <= max_data_age_sec_;
  }

  std::string path_signature(const nav_msgs::msg::Path & path) const
  {
    std::ostringstream out;
    out << path.header.frame_id << ":" << path.poses.size();
    if (!path.poses.empty()) {
      const auto & first = path.poses.front().pose.position;
      const auto & last = path.poses.back().pose.position;
      out << ":" << first.x << "," << first.y << "," << first.z
          << ":" << last.x << "," << last.y << "," << last.z;
    }
    return out.str();
  }

  void publish_state()
  {
    const auto t = now();
    const std::size_t path_points = latest_path_ ? latest_path_->poses.size() : 0;
    const double coverage_ratio = path_points > 0 ?
      static_cast<double>(covered_indices_.size()) / static_cast<double>(path_points) : 0.0;
    const bool path_fresh = latest_path_ && fresh(t, last_path_time_);
    const bool target_fresh = latest_target_ && fresh(t, last_target_time_);
    const bool tracking_fresh = latest_tracking_state_ && fresh(t, last_tracking_time_);
    const bool gate_fresh = latest_safety_gate_ && fresh(t, last_gate_time_);
    const bool tracking_ready = tracking_fresh &&
      latest_tracking_state_->data.rfind("TRACK_READY", 0) == 0;
    const bool safety_gate = gate_fresh && latest_safety_gate_->data;
    const bool coverage_ready = path_fresh && target_fresh && tracking_ready && safety_gate &&
      coverage_ratio >= min_coverage_ratio_;

    std_msgs::msg::String msg;
    std::ostringstream out;
    out << "CABLE_COVERAGE_DRY_RUN"
        << "; dry_run=true"
        << "; learned_policy=false"
        << "; starts_offboard=false"
        << "; arms=false"
        << "; publishes_fmu_in=false"
        << "; path_points=" << path_points
        << "; covered_points=" << covered_indices_.size()
        << "; target_samples=" << target_samples_
        << "; coverage_ratio=" << coverage_ratio
        << "; min_coverage_ratio=" << min_coverage_ratio_
        << "; last_target_to_path_m=" << printable(last_target_to_path_m_)
        << "; path_fresh=" << (path_fresh ? "true" : "false")
        << "; target_fresh=" << (target_fresh ? "true" : "false")
        << "; tracking_ready=" << (tracking_ready ? "true" : "false")
        << "; safety_gate=" << (safety_gate ? "true" : "false")
        << "; coverage_ready=" << (coverage_ready ? "true" : "false");
    msg.data = out.str();
    coverage_pub_->publish(msg);
  }

  double min_coverage_ratio_{0.80};
  double max_target_to_path_m_{2.0};
  double max_data_age_sec_{3.0};
  double publish_hz_{5.0};
  double last_target_to_path_m_{std::numeric_limits<double>::infinity()};
  std::size_t target_samples_{0};
  std::unordered_set<std::size_t> covered_indices_;
  std::string latest_path_signature_;
  rclcpp::Time last_path_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_target_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_tracking_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time last_gate_time_{0, 0, RCL_ROS_TIME};
  nav_msgs::msg::Path::SharedPtr latest_path_;
  geometry_msgs::msg::PointStamped::SharedPtr latest_target_;
  std_msgs::msg::String::SharedPtr latest_tracking_state_;
  std_msgs::msg::Bool::SharedPtr latest_safety_gate_;
  rclcpp::Subscription<nav_msgs::msg::Path>::SharedPtr path_sub_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr target_sub_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr tracking_sub_;
  rclcpp::Subscription<std_msgs::msg::Bool>::SharedPtr gate_sub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr coverage_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<LookaheadCoverageMonitor>());
  } catch (const std::exception & e) {
    std::cerr << "lookahead_coverage_monitor error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
