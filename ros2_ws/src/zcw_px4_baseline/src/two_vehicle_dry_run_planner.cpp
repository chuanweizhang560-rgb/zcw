#include <chrono>
#include <cmath>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

#include <geometry_msgs/msg/point_stamped.hpp>
#include <px4_msgs/msg/vehicle_local_position.hpp>
#include <px4_msgs/msg/vehicle_status.hpp>
#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/string.hpp>

class TwoVehicleDryRunPlanner : public rclcpp::Node
{
public:
  TwoVehicleDryRunPlanner()
  : Node("two_vehicle_dry_run_planner")
  {
    publish_hz_ = declare_parameter<double>("publish_hz", 2.0);
    base_x_ = declare_parameter<double>("base_x", 0.0);
    base_y_ = declare_parameter<double>("base_y", 0.0);
    relay_radius_m_ = declare_parameter<double>("relay_radius_m", 800.0);
    goal_acceptance_radius_m_ = declare_parameter<double>("goal_acceptance_radius_m", 5.0);
    max_state_age_sec_ = declare_parameter<double>("max_state_age_sec", 2.0);
    v1_goal_x_ = declare_parameter<double>("vehicle_1_goal_x", -25.0);
    v1_goal_y_ = declare_parameter<double>("vehicle_1_goal_y", -10.0);
    v1_goal_z_ = declare_parameter<double>("vehicle_1_goal_z", -20.0);
    v2_goal_x_ = declare_parameter<double>("vehicle_2_goal_x", -12.5);
    v2_goal_y_ = declare_parameter<double>("vehicle_2_goal_y", -5.0);
    v2_goal_z_ = declare_parameter<double>("vehicle_2_goal_z", -12.0);

    if (publish_hz_ <= 0.0 || relay_radius_m_ <= 0.0 ||
      goal_acceptance_radius_m_ < 0.0 || max_state_age_sec_ <= 0.0)
    {
      throw std::runtime_error("invalid two_vehicle_dry_run_planner parameter");
    }

    const auto qos = rclcpp::SensorDataQoS();
    v1_position_sub_ = create_subscription<px4_msgs::msg::VehicleLocalPosition>(
      "/px4_1/fmu/out/vehicle_local_position", qos,
      [this](px4_msgs::msg::VehicleLocalPosition::SharedPtr msg) {
        v1_position_ = msg;
        v1_position_time_ = now();
      });
    v2_position_sub_ = create_subscription<px4_msgs::msg::VehicleLocalPosition>(
      "/px4_2/fmu/out/vehicle_local_position", qos,
      [this](px4_msgs::msg::VehicleLocalPosition::SharedPtr msg) {
        v2_position_ = msg;
        v2_position_time_ = now();
      });
    v1_status_sub_ = create_subscription<px4_msgs::msg::VehicleStatus>(
      "/px4_1/fmu/out/vehicle_status", qos,
      [this](px4_msgs::msg::VehicleStatus::SharedPtr msg) {
        v1_status_ = msg;
        v1_status_time_ = now();
      });
    v2_status_sub_ = create_subscription<px4_msgs::msg::VehicleStatus>(
      "/px4_2/fmu/out/vehicle_status", qos,
      [this](px4_msgs::msg::VehicleStatus::SharedPtr msg) {
        v2_status_ = msg;
        v2_status_time_ = now();
      });

    v1_goal_pub_ = create_publisher<geometry_msgs::msg::PointStamped>(
      "/zcw/multi_vehicle/dry_run/vehicle_1_goal", 10);
    v2_goal_pub_ = create_publisher<geometry_msgs::msg::PointStamped>(
      "/zcw/multi_vehicle/dry_run/vehicle_2_goal", 10);
    topology_pub_ = create_publisher<std_msgs::msg::String>(
      "/zcw/multi_vehicle/dry_run/topology_state", 10);
    safety_pub_ = create_publisher<std_msgs::msg::String>(
      "/zcw/multi_vehicle/dry_run/safety_state", 10);

    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz_)),
      [this]() { publish_dry_run(); });
  }

private:
  bool fresh(const rclcpp::Time & stamp, const rclcpp::Time & t) const
  {
    return stamp.nanoseconds() > 0 && (t - stamp).seconds() <= max_state_age_sec_;
  }

  static bool valid_position(const px4_msgs::msg::VehicleLocalPosition & msg)
  {
    return msg.xy_valid && msg.z_valid &&
           std::isfinite(msg.x) && std::isfinite(msg.y) && std::isfinite(msg.z);
  }

  static double distance_xy(double ax, double ay, double bx, double by)
  {
    const double dx = ax - bx;
    const double dy = ay - by;
    return std::sqrt(dx * dx + dy * dy);
  }

  geometry_msgs::msg::PointStamped goal_msg(double x, double y, double z) const
  {
    geometry_msgs::msg::PointStamped msg;
    msg.header.stamp = now();
    msg.header.frame_id = "px4_local_ned";
    msg.point.x = x;
    msg.point.y = y;
    msg.point.z = z;
    return msg;
  }

  void publish_dry_run()
  {
    const auto t = now();
    const bool v1_pose_ready = v1_position_ && fresh(v1_position_time_, t) &&
      valid_position(*v1_position_);
    const bool v2_pose_ready = v2_position_ && fresh(v2_position_time_, t) &&
      valid_position(*v2_position_);
    const bool v1_status_ready = v1_status_ && fresh(v1_status_time_, t);
    const bool v2_status_ready = v2_status_ && fresh(v2_status_time_, t);

    v1_goal_pub_->publish(goal_msg(v1_goal_x_, v1_goal_y_, v1_goal_z_));
    v2_goal_pub_->publish(goal_msg(v2_goal_x_, v2_goal_y_, v2_goal_z_));

    double v1_goal_distance = -1.0;
    double v2_goal_distance = -1.0;
    double vehicle_distance = -1.0;
    double v1_base_distance = -1.0;
    double v2_base_distance = -1.0;
    bool topology_ready = false;
    bool safety_ready = false;

    if (v1_pose_ready && v2_pose_ready) {
      v1_goal_distance = distance_xy(v1_position_->x, v1_position_->y, v1_goal_x_, v1_goal_y_);
      v2_goal_distance = distance_xy(v2_position_->x, v2_position_->y, v2_goal_x_, v2_goal_y_);
      vehicle_distance = distance_xy(v1_position_->x, v1_position_->y, v2_position_->x, v2_position_->y);
      v1_base_distance = distance_xy(v1_position_->x, v1_position_->y, base_x_, base_y_);
      v2_base_distance = distance_xy(v2_position_->x, v2_position_->y, base_x_, base_y_);
      topology_ready =
        vehicle_distance <= relay_radius_m_ &&
        v1_base_distance <= relay_radius_m_ &&
        v2_base_distance <= relay_radius_m_;
      safety_ready = topology_ready && v1_status_ready && v2_status_ready;
    }

    std_msgs::msg::String topology_msg;
    std::ostringstream topology;
    topology << (topology_ready ? "TOPOLOGY_READY" : "TOPOLOGY_HOLD")
             << "; dry_run=true"
             << "; publishes_fmu_in=false"
             << "; vehicle_distance_m=" << vehicle_distance
             << "; vehicle_1_base_distance_m=" << v1_base_distance
             << "; vehicle_2_base_distance_m=" << v2_base_distance
             << "; relay_radius_m=" << relay_radius_m_;
    topology_msg.data = topology.str();
    topology_pub_->publish(topology_msg);

    std_msgs::msg::String safety_msg;
    std::ostringstream safety;
    safety << (safety_ready ? "SAFETY_READY_DRY_RUN" : "SAFETY_HOLD")
           << "; dry_run=true"
           << "; starts_offboard=false"
           << "; arms=false"
           << "; publishes_fmu_in=false"
           << "; vehicle_1_pose_ready=" << (v1_pose_ready ? "true" : "false")
           << "; vehicle_2_pose_ready=" << (v2_pose_ready ? "true" : "false")
           << "; vehicle_1_status_ready=" << (v1_status_ready ? "true" : "false")
           << "; vehicle_2_status_ready=" << (v2_status_ready ? "true" : "false")
           << "; vehicle_1_goal_distance_m=" << v1_goal_distance
           << "; vehicle_2_goal_distance_m=" << v2_goal_distance
           << "; goal_acceptance_radius_m=" << goal_acceptance_radius_m_;
    safety_msg.data = safety.str();
    safety_pub_->publish(safety_msg);
  }

  double publish_hz_{2.0};
  double base_x_{0.0};
  double base_y_{0.0};
  double relay_radius_m_{800.0};
  double goal_acceptance_radius_m_{5.0};
  double max_state_age_sec_{2.0};
  double v1_goal_x_{-25.0};
  double v1_goal_y_{-10.0};
  double v1_goal_z_{-20.0};
  double v2_goal_x_{-12.5};
  double v2_goal_y_{-5.0};
  double v2_goal_z_{-12.0};
  rclcpp::Time v1_position_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time v2_position_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time v1_status_time_{0, 0, RCL_ROS_TIME};
  rclcpp::Time v2_status_time_{0, 0, RCL_ROS_TIME};
  px4_msgs::msg::VehicleLocalPosition::SharedPtr v1_position_;
  px4_msgs::msg::VehicleLocalPosition::SharedPtr v2_position_;
  px4_msgs::msg::VehicleStatus::SharedPtr v1_status_;
  px4_msgs::msg::VehicleStatus::SharedPtr v2_status_;
  rclcpp::Subscription<px4_msgs::msg::VehicleLocalPosition>::SharedPtr v1_position_sub_;
  rclcpp::Subscription<px4_msgs::msg::VehicleLocalPosition>::SharedPtr v2_position_sub_;
  rclcpp::Subscription<px4_msgs::msg::VehicleStatus>::SharedPtr v1_status_sub_;
  rclcpp::Subscription<px4_msgs::msg::VehicleStatus>::SharedPtr v2_status_sub_;
  rclcpp::Publisher<geometry_msgs::msg::PointStamped>::SharedPtr v1_goal_pub_;
  rclcpp::Publisher<geometry_msgs::msg::PointStamped>::SharedPtr v2_goal_pub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr topology_pub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr safety_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<TwoVehicleDryRunPlanner>());
  } catch (const std::exception & e) {
    std::cerr << "two_vehicle_dry_run_planner error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
