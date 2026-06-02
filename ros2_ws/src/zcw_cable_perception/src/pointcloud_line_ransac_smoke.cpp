#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <memory>
#include <sstream>
#include <string>
#include <thread>

#include <pcl/ModelCoefficients.h>
#include <pcl/filters/extract_indices.h>
#include <pcl/filters/filter.h>
#include <pcl/io/pcd_io.h>
#include <pcl/point_cloud.h>
#include <pcl/point_types.h>
#include <pcl/segmentation/sac_segmentation.h>
#include <pcl_conversions/pcl_conversions.h>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>

namespace
{
std::string stamp_string()
{
  const auto now = std::chrono::system_clock::now();
  const auto time = std::chrono::system_clock::to_time_t(now);
  std::tm tm{};
  localtime_r(&time, &tm);
  std::ostringstream out;
  out << std::put_time(&tm, "%Y%m%d_%H%M%S");
  return out.str();
}
}  // namespace

class PointCloudLineRansacSmoke : public rclcpp::Node
{
public:
  PointCloudLineRansacSmoke()
  : Node("pointcloud_line_ransac_smoke")
  {
    topic_ = declare_parameter<std::string>("topic", "/zcw/foggy_lidar/points");
    output_dir_ = declare_parameter<std::string>("output_dir", "data/results");
    distance_threshold_ = declare_parameter<double>("distance_threshold_m", 0.35);
    min_inliers_ = declare_parameter<int>("min_inliers", 20);
    max_iterations_ = declare_parameter<int>("max_iterations", 200);

    std::filesystem::create_directories(output_dir_);

    subscription_ = create_subscription<sensor_msgs::msg::PointCloud2>(
      topic_,
      rclcpp::SensorDataQoS(),
      [this](sensor_msgs::msg::PointCloud2::ConstSharedPtr msg) {
        process(msg);
      });

    RCLCPP_INFO(get_logger(), "Waiting for PointCloud2 topic: %s", topic_.c_str());
  }

  bool done() const { return done_; }
  int result_code() const { return result_code_; }

private:
  void process(const sensor_msgs::msg::PointCloud2::ConstSharedPtr & msg)
  {
    if (done_) {
      return;
    }

    auto cloud = std::make_shared<pcl::PointCloud<pcl::PointXYZI>>();
    pcl::fromROSMsg(*msg, *cloud);
    const auto raw_points = cloud->size();

    std::vector<int> finite_indices;
    pcl::removeNaNFromPointCloud(*cloud, *cloud, finite_indices);
    const auto finite_points = cloud->size();

    const auto stamp = stamp_string();
    const auto raw_pcd = output_dir_ + "/foggy_lidar_raw_" + stamp + ".pcd";
    const auto inliers_pcd = output_dir_ + "/foggy_lidar_line_inliers_" + stamp + ".pcd";
    const auto result_txt = output_dir_ + "/foggy_lidar_line_ransac_" + stamp + ".txt";

    pcl::io::savePCDFileBinary(raw_pcd, *cloud);

    pcl::SACSegmentation<pcl::PointXYZI> segmentation;
    segmentation.setOptimizeCoefficients(true);
    segmentation.setModelType(pcl::SACMODEL_LINE);
    segmentation.setMethodType(pcl::SAC_RANSAC);
    segmentation.setMaxIterations(max_iterations_);
    segmentation.setDistanceThreshold(distance_threshold_);
    segmentation.setInputCloud(cloud);

    auto inliers = std::make_shared<pcl::PointIndices>();
    auto coefficients = std::make_shared<pcl::ModelCoefficients>();
    segmentation.segment(*inliers, *coefficients);

    pcl::ExtractIndices<pcl::PointXYZI> extract;
    extract.setInputCloud(cloud);
    extract.setIndices(inliers);
    auto inlier_cloud = std::make_shared<pcl::PointCloud<pcl::PointXYZI>>();
    extract.filter(*inlier_cloud);
    pcl::io::savePCDFileBinary(inliers_pcd, *inlier_cloud);

    const auto inlier_count = inliers->indices.size();
    const double inlier_ratio = finite_points == 0 ? 0.0 :
      static_cast<double>(inlier_count) / static_cast<double>(finite_points);

    std::ofstream result(result_txt);
    result << "topic: " << topic_ << "\n";
    result << "raw_points: " << raw_points << "\n";
    result << "finite_points: " << finite_points << "\n";
    result << "ransac_inliers: " << inlier_count << "\n";
    result << "ransac_inlier_ratio: " << inlier_ratio << "\n";
    result << "distance_threshold_m: " << distance_threshold_ << "\n";
    result << "max_iterations: " << max_iterations_ << "\n";
    result << "raw_pcd: " << raw_pcd << "\n";
    result << "inliers_pcd: " << inliers_pcd << "\n";
    result << "coefficients:";
    for (const auto value : coefficients->values) {
      result << " " << value;
    }
    result << "\n";

    RCLCPP_INFO(get_logger(), "raw_points=%zu finite_points=%zu ransac_inliers=%zu ratio=%.3f",
      raw_points, finite_points, inlier_count, inlier_ratio);
    RCLCPP_INFO(get_logger(), "result: %s", result_txt.c_str());

    result_code_ = inlier_count >= static_cast<size_t>(min_inliers_) ? 0 : 2;
    done_ = true;
  }

  std::string topic_;
  std::string output_dir_;
  double distance_threshold_{0.35};
  int min_inliers_{20};
  int max_iterations_{200};
  bool done_{false};
  int result_code_{1};
  rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr subscription_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<PointCloudLineRansacSmoke>();

  const auto start = std::chrono::steady_clock::now();
  const auto timeout = std::chrono::seconds(30);
  while (rclcpp::ok() && !node->done()) {
    rclcpp::spin_some(node);
    if (std::chrono::steady_clock::now() - start > timeout) {
      RCLCPP_ERROR(node->get_logger(), "Timed out waiting for point cloud.");
      rclcpp::shutdown();
      return 1;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  const int result_code = node->result_code();
  rclcpp::shutdown();
  return result_code;
}
