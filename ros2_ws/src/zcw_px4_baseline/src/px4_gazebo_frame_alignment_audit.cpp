#include <chrono>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

#include <geometry_msgs/msg/point_stamped.hpp>
#include <nav_msgs/msg/odometry.hpp>
#include <px4_msgs/msg/vehicle_local_position.hpp>
#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/string.hpp>

namespace
{
bool finite3(double x, double y, double z)
{
  return std::isfinite(x) && std::isfinite(y) && std::isfinite(z);
}

std::string bool_text(bool value)
{
  return value ? "true" : "false";
}
}  // namespace

class Px4GazeboFrameAlignmentAudit : public rclcpp::Node
{
public:
  Px4GazeboFrameAlignmentAudit()
  : Node("px4_gazebo_frame_alignment_audit")
  {
    output_file_ = declare_parameter<std::string>("output_file", "");
    max_age_sec_ = declare_parameter<double>("max_age_sec", 2.0);
    max_debug_xy_error_m_ = declare_parameter<double>("max_debug_xy_error_m", 2.5);
    max_debug_z_error_m_ = declare_parameter<double>("max_debug_z_error_m", 0.5);
    if (output_file_.empty()) {
      throw std::runtime_error("output_file parameter is required");
    }
    if (max_age_sec_ <= 0.0 || max_debug_xy_error_m_ < 0.0 || max_debug_z_error_m_ < 0.0) {
      throw std::runtime_error("invalid audit parameter");
    }

    px4_local_sub_ = create_subscription<px4_msgs::msg::VehicleLocalPosition>(
      "/fmu/out/vehicle_local_position", rclcpp::SensorDataQoS(),
      [this](px4_msgs::msg::VehicleLocalPosition::SharedPtr msg) {
        px4_local_ = msg;
        px4_local_time_ = now();
      });
    gazebo_pose_sub_ = create_subscription<nav_msgs::msg::Odometry>(
      "/zcw/depth_camera/pose", 10,
      [this](nav_msgs::msg::Odometry::SharedPtr msg) {
        gazebo_pose_ = msg;
        gazebo_pose_time_ = now();
      });
    dry_run_state_sub_ = create_subscription<std_msgs::msg::String>(
      "/zcw/cable/dry_run/state", 10,
      [this](std_msgs::msg::String::SharedPtr msg) {
        dry_run_state_ = msg;
        dry_run_state_time_ = now();
      });
    bridge_state_sub_ = create_subscription<std_msgs::msg::String>(
      "/zcw/cable/px4_bridge/state", 10,
      [this](std_msgs::msg::String::SharedPtr msg) {
        bridge_state_ = msg;
        bridge_state_time_ = now();
      });
    map_candidate_sub_ = create_subscription<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/dry_run/candidate_setpoint", 10,
      [this](geometry_msgs::msg::PointStamped::SharedPtr msg) {
        map_candidate_ = msg;
        map_candidate_time_ = now();
      });
    bridge_ned_sub_ = create_subscription<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/px4_bridge/ned_setpoint_dry_run", 10,
      [this](geometry_msgs::msg::PointStamped::SharedPtr msg) {
        bridge_ned_ = msg;
        bridge_ned_time_ = now();
      });
  }

  bool ready() const
  {
    const auto t = now();
    return fresh(px4_local_time_, t) && fresh(gazebo_pose_time_, t) &&
           fresh(dry_run_state_time_, t) && fresh(bridge_state_time_, t) &&
           fresh(map_candidate_time_, t) && fresh(bridge_ned_time_, t) &&
           px4_local_ && gazebo_pose_ && dry_run_state_ && bridge_state_ &&
           map_candidate_ && bridge_ned_;
  }

  void write_summary()
  {
    if (!ready()) {
      throw std::runtime_error("audit summary requested before all inputs were fresh");
    }

    const auto & px4 = *px4_local_;
    const auto & pose = gazebo_pose_->pose.pose;
    const auto & candidate = *map_candidate_;
    const auto & ned = *bridge_ned_;

    const bool px4_finite = finite3(px4.x, px4.y, px4.z);
    const bool gazebo_finite = finite3(pose.position.x, pose.position.y, pose.position.z);
    const bool candidate_finite =
      finite3(candidate.point.x, candidate.point.y, candidate.point.z);
    const bool ned_finite = finite3(ned.point.x, ned.point.y, ned.point.z);
    const double expected_ned_z = -candidate.point.z;
    const double debug_ned_z_error = ned.point.z - expected_ned_z;
    const double debug_ned_xy_error = std::hypot(
      ned.point.x - candidate.point.x,
      ned.point.y - candidate.point.y);

    const bool dry_ready = dry_run_state_->data.rfind("TRACK_READY", 0) == 0;
    const bool bridge_ready = bridge_state_->data.rfind("DRY_RUN_READY", 0) == 0;
    const bool debug_transform_ok =
      candidate_finite && ned_finite && debug_ned_xy_error <= 1.0e-6 &&
      std::abs(debug_ned_z_error) <= 1.0e-6;
    const bool debug_transform_smoke_ok =
      candidate_finite && ned_finite && debug_ned_xy_error <= max_debug_xy_error_m_ &&
      std::abs(debug_ned_z_error) <= max_debug_z_error_m_;

    std::ofstream out(output_file_);
    if (!out) {
      throw std::runtime_error("failed to open output_file: " + output_file_);
    }
    out << std::setprecision(12);
    out << "decision="
        << ((px4_finite && gazebo_finite && dry_ready && bridge_ready && debug_transform_smoke_ok) ?
          "accepted_readonly_frame_sample_smoke" :
          "rejected_readonly_frame_sample_smoke")
        << "\n";
    out << "publishes_fmu_in=false\n";
    out << "scope=read_only_topic_sample_no_offboard_no_arm\n";
    out << "px4_local_position_topic=/fmu/out/vehicle_local_position\n";
    out << "gazebo_pose_topic=/zcw/depth_camera/pose\n";
    out << "map_candidate_topic=/zcw/cable/dry_run/candidate_setpoint\n";
    out << "bridge_ned_topic=/zcw/cable/px4_bridge/ned_setpoint_dry_run\n";
    out << "dry_run_state=" << dry_run_state_->data << "\n";
    out << "bridge_state=" << bridge_state_->data << "\n";
    out << "px4_local_finite=" << bool_text(px4_finite) << "\n";
    out << "px4_local_x=" << px4.x << "\n";
    out << "px4_local_y=" << px4.y << "\n";
    out << "px4_local_z=" << px4.z << "\n";
    out << "px4_xy_valid=" << bool_text(px4.xy_valid) << "\n";
    out << "px4_z_valid=" << bool_text(px4.z_valid) << "\n";
    out << "gazebo_pose_finite=" << bool_text(gazebo_finite) << "\n";
    out << "gazebo_world_x=" << pose.position.x << "\n";
    out << "gazebo_world_y=" << pose.position.y << "\n";
    out << "gazebo_world_z=" << pose.position.z << "\n";
    out << "map_candidate_frame=" << candidate.header.frame_id << "\n";
    out << "map_candidate_finite=" << bool_text(candidate_finite) << "\n";
    out << "map_candidate_x=" << candidate.point.x << "\n";
    out << "map_candidate_y=" << candidate.point.y << "\n";
    out << "map_candidate_z=" << candidate.point.z << "\n";
    out << "bridge_ned_frame=" << ned.header.frame_id << "\n";
    out << "bridge_ned_finite=" << bool_text(ned_finite) << "\n";
    out << "bridge_ned_x=" << ned.point.x << "\n";
    out << "bridge_ned_y=" << ned.point.y << "\n";
    out << "bridge_ned_z=" << ned.point.z << "\n";
    out << "debug_map_to_ned_expected_z=" << expected_ned_z << "\n";
    out << "debug_map_to_ned_xy_error_m=" << debug_ned_xy_error << "\n";
    out << "debug_map_to_ned_z_error_m=" << debug_ned_z_error << "\n";
    out << "max_debug_xy_error_m=" << max_debug_xy_error_m_ << "\n";
    out << "max_debug_z_error_m=" << max_debug_z_error_m_ << "\n";
    out << "dry_run_ready=" << bool_text(dry_ready) << "\n";
    out << "bridge_ready=" << bool_text(bridge_ready) << "\n";
    out << "debug_transform_exact_ok=" << bool_text(debug_transform_ok) << "\n";
    out << "debug_transform_smoke_ok=" << bool_text(debug_transform_smoke_ok) << "\n";
    out << "note=This smoke test samples PX4 local NED and Gazebo world pose in one time window. It does not prove closed-loop cable tracking.\n";
    done_ = true;
  }

  bool done() const
  {
    return done_;
  }

private:
  bool fresh(const rclcpp::Time & stamp, const rclcpp::Time & now_time) const
  {
    return stamp.nanoseconds() > 0 && (now_time - stamp).seconds() <= max_age_sec_;
  }

  std::string output_file_;
  double max_age_sec_{2.0};
  double max_debug_xy_error_m_{2.5};
  double max_debug_z_error_m_{0.5};
  bool done_{false};
  rclcpp::Time px4_local_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time gazebo_pose_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time dry_run_state_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time bridge_state_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time map_candidate_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time bridge_ned_time_{0, 0, RCL_ROS_TIME};
  px4_msgs::msg::VehicleLocalPosition::SharedPtr px4_local_;
  nav_msgs::msg::Odometry::SharedPtr gazebo_pose_;
  std_msgs::msg::String::SharedPtr dry_run_state_;
  std_msgs::msg::String::SharedPtr bridge_state_;
  geometry_msgs::msg::PointStamped::SharedPtr map_candidate_;
  geometry_msgs::msg::PointStamped::SharedPtr bridge_ned_;
  rclcpp::Subscription<px4_msgs::msg::VehicleLocalPosition>::SharedPtr px4_local_sub_;
  rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr gazebo_pose_sub_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr dry_run_state_sub_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr bridge_state_sub_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr map_candidate_sub_;
  rclcpp::Subscription<geometry_msgs::msg::PointStamped>::SharedPtr bridge_ned_sub_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    auto node = std::make_shared<Px4GazeboFrameAlignmentAudit>();
    const auto start = std::chrono::steady_clock::now();
    const auto timeout = std::chrono::seconds(20);
    rclcpp::WallRate rate(20.0);
    while (rclcpp::ok() && !node->done()) {
      rclcpp::spin_some(node);
      if (node->ready()) {
        node->write_summary();
        break;
      }
      if (std::chrono::steady_clock::now() - start > timeout) {
        throw std::runtime_error("timed out waiting for read-only frame inputs");
      }
      rate.sleep();
    }
  } catch (const std::exception & e) {
    std::cerr << "px4_gazebo_frame_alignment_audit error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
