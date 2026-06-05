#include <memory>
#include <string>

#include <geometry_msgs/msg/transform_stamped.hpp>
#include <nav_msgs/msg/odometry.hpp>
#include <rclcpp/rclcpp.hpp>
#include <tf2_ros/transform_broadcaster.h>

class OdomChildFrameBridge : public rclcpp::Node
{
public:
  OdomChildFrameBridge()
  : Node("odom_child_frame_bridge")
  {
    input_topic_ = declare_parameter<std::string>("input_topic", "/zcw/depth_camera/pose");
    output_topic_ = declare_parameter<std::string>("output_topic", "/zcw/rtabmap/odom_camera_link");
    target_child_frame_ = declare_parameter<std::string>("target_child_frame", "camera_link");
    override_parent_frame_ = declare_parameter<std::string>("override_parent_frame", "");
    publish_tf_ = declare_parameter<bool>("publish_tf", true);

    if (publish_tf_) {
      tf_broadcaster_ = std::make_unique<tf2_ros::TransformBroadcaster>(*this);
    }

    pub_ = create_publisher<nav_msgs::msg::Odometry>(output_topic_, 10);
    sub_ = create_subscription<nav_msgs::msg::Odometry>(
      input_topic_, 10,
      [this](const nav_msgs::msg::Odometry::SharedPtr msg) {
        nav_msgs::msg::Odometry out = *msg;
        if (!override_parent_frame_.empty()) {
          out.header.frame_id = override_parent_frame_;
        }
        out.child_frame_id = target_child_frame_;
        pub_->publish(out);

        if (publish_tf_ && tf_broadcaster_) {
          geometry_msgs::msg::TransformStamped tf;
          tf.header = out.header;
          tf.child_frame_id = out.child_frame_id;
          tf.transform.translation.x = out.pose.pose.position.x;
          tf.transform.translation.y = out.pose.pose.position.y;
          tf.transform.translation.z = out.pose.pose.position.z;
          tf.transform.rotation = out.pose.pose.orientation;
          tf_broadcaster_->sendTransform(tf);
        }
      });

    RCLCPP_INFO(
      get_logger(),
      "Bridging Odometry %s -> %s with child_frame_id=%s publish_tf=%s",
      input_topic_.c_str(), output_topic_.c_str(), target_child_frame_.c_str(),
      publish_tf_ ? "true" : "false");
  }

private:
  std::string input_topic_;
  std::string output_topic_;
  std::string target_child_frame_;
  std::string override_parent_frame_;
  bool publish_tf_{true};
  rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr sub_;
  rclcpp::Publisher<nav_msgs::msg::Odometry>::SharedPtr pub_;
  std::unique_ptr<tf2_ros::TransformBroadcaster> tf_broadcaster_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<OdomChildFrameBridge>());
  rclcpp::shutdown();
  return 0;
}
