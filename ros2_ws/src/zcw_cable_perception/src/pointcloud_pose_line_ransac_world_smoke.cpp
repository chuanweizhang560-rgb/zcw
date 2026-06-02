#include <algorithm>
#include <array>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <Eigen/Core>
#include <Eigen/Geometry>
#include <nav_msgs/msg/odometry.hpp>
#include <pcl/ModelCoefficients.h>
#include <pcl/common/transforms.h>
#include <pcl/filters/crop_box.h>
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

using PointT = pcl::PointXYZ;
using Cloud = pcl::PointCloud<PointT>;
using CloudPtr = Cloud::Ptr;

struct Bbox
{
  std::array<double, 3> min{
    std::numeric_limits<double>::infinity(),
    std::numeric_limits<double>::infinity(),
    std::numeric_limits<double>::infinity()};
  std::array<double, 3> max{
    -std::numeric_limits<double>::infinity(),
    -std::numeric_limits<double>::infinity(),
    -std::numeric_limits<double>::infinity()};
  bool valid{false};
};

struct FrameStats
{
  int frame_index{0};
  std::size_t raw_points{0};
  std::size_t finite_points{0};
  std::size_t roi_points{0};
  std::size_t inliers{0};
  double inlier_ratio{0.0};
  Bbox world_inlier_bbox;
};

Bbox compute_bbox(const Cloud & cloud)
{
  Bbox bbox;
  for (const auto & point : cloud.points) {
    bbox.min[0] = std::min<double>(bbox.min[0], point.x);
    bbox.min[1] = std::min<double>(bbox.min[1], point.y);
    bbox.min[2] = std::min<double>(bbox.min[2], point.z);
    bbox.max[0] = std::max<double>(bbox.max[0], point.x);
    bbox.max[1] = std::max<double>(bbox.max[1], point.y);
    bbox.max[2] = std::max<double>(bbox.max[2], point.z);
    bbox.valid = true;
  }
  return bbox;
}

void merge_bbox(Bbox & target, const Bbox & source)
{
  if (!source.valid) {
    return;
  }
  if (!target.valid) {
    target = source;
    return;
  }
  for (std::size_t i = 0; i < 3; ++i) {
    target.min[i] = std::min(target.min[i], source.min[i]);
    target.max[i] = std::max(target.max[i], source.max[i]);
  }
}
}  // namespace

class PointCloudPoseLineRansacWorldSmoke : public rclcpp::Node
{
public:
  PointCloudPoseLineRansacWorldSmoke()
  : Node("pointcloud_pose_line_ransac_world_smoke")
  {
    topic_ = declare_parameter<std::string>("topic", "/zcw/foggy_lidar/points");
    pose_topic_ = declare_parameter<std::string>("pose_topic", "/zcw/foggy_lidar/pose");
    output_dir_ = declare_parameter<std::string>("output_dir", "data/results");
    output_prefix_ = declare_parameter<std::string>("output_prefix", "pointcloud_line_ransac_world");
    frames_ = declare_parameter<int>("frames", 5);
    distance_threshold_ = declare_parameter<double>("distance_threshold_m", 0.35);
    min_inliers_ = declare_parameter<int>("min_inliers", 8);
    max_iterations_ = declare_parameter<int>("max_iterations", 200);
    crop_min_x_ = declare_parameter<double>("crop_min_x", -80.0);
    crop_max_x_ = declare_parameter<double>("crop_max_x", 80.0);
    crop_min_y_ = declare_parameter<double>("crop_min_y", -80.0);
    crop_max_y_ = declare_parameter<double>("crop_max_y", 80.0);
    crop_min_z_ = declare_parameter<double>("crop_min_z", -10.0);
    crop_max_z_ = declare_parameter<double>("crop_max_z", 10.0);
    apply_sensor_pose_in_link_ = declare_parameter<bool>("apply_sensor_pose_in_link", true);
    sensor_roll_rad_ = declare_parameter<double>("sensor_roll_rad", 0.0);
    sensor_pitch_rad_ = declare_parameter<double>("sensor_pitch_rad", 1.51);
    sensor_yaw_rad_ = declare_parameter<double>("sensor_yaw_rad", 0.0);

    if (frames_ <= 0) {
      frames_ = 1;
    }
    std::filesystem::create_directories(output_dir_);

    pose_subscription_ = create_subscription<nav_msgs::msg::Odometry>(
      pose_topic_,
      10,
      [this](nav_msgs::msg::Odometry::ConstSharedPtr msg) {
        latest_pose_ = *msg;
        pose_received_ = true;
      });

    cloud_subscription_ = create_subscription<sensor_msgs::msg::PointCloud2>(
      topic_,
      rclcpp::SensorDataQoS(),
      [this](sensor_msgs::msg::PointCloud2::ConstSharedPtr msg) {
        process(msg);
      });

    RCLCPP_INFO(get_logger(), "Waiting for pose topic %s and %d PointCloud2 frames on %s",
      pose_topic_.c_str(), frames_, topic_.c_str());
  }

  bool done() const { return done_; }
  int result_code() const { return result_code_; }

private:
  CloudPtr crop(const CloudPtr & input) const
  {
    auto cropped = std::make_shared<Cloud>();
    pcl::CropBox<PointT> crop_box;
    crop_box.setMin(Eigen::Vector4f(crop_min_x_, crop_min_y_, crop_min_z_, 1.0f));
    crop_box.setMax(Eigen::Vector4f(crop_max_x_, crop_max_y_, crop_max_z_, 1.0f));
    crop_box.setInputCloud(input);
    crop_box.filter(*cropped);
    return cropped;
  }

  Eigen::Affine3f world_transform_from_latest_pose() const
  {
    const auto & pose = latest_pose_.pose.pose;
    Eigen::Affine3f transform = Eigen::Affine3f::Identity();
    transform.translation() << static_cast<float>(pose.position.x),
      static_cast<float>(pose.position.y),
      static_cast<float>(pose.position.z);

    Eigen::Quaternionf q(
      static_cast<float>(pose.orientation.w),
      static_cast<float>(pose.orientation.x),
      static_cast<float>(pose.orientation.y),
      static_cast<float>(pose.orientation.z));
    if (q.norm() > 0.0f) {
      q.normalize();
      transform.linear() = q.toRotationMatrix();
    }

    if (apply_sensor_pose_in_link_) {
      Eigen::Affine3f sensor_pose = Eigen::Affine3f::Identity();
      const Eigen::Matrix3f sensor_rotation =
        (Eigen::AngleAxisf(static_cast<float>(sensor_yaw_rad_), Eigen::Vector3f::UnitZ()) *
        Eigen::AngleAxisf(static_cast<float>(sensor_pitch_rad_), Eigen::Vector3f::UnitY()) *
        Eigen::AngleAxisf(static_cast<float>(sensor_roll_rad_), Eigen::Vector3f::UnitX())).toRotationMatrix();
      sensor_pose.linear() = sensor_rotation;
      transform = transform * sensor_pose;
    }
    return transform;
  }

  FrameStats process_ransac(const CloudPtr & cloud, int frame_index, CloudPtr & inlier_cloud) const
  {
    FrameStats stats;
    stats.frame_index = frame_index;
    if (cloud->empty()) {
      inlier_cloud = std::make_shared<Cloud>();
      return stats;
    }

    pcl::SACSegmentation<PointT> segmentation;
    segmentation.setOptimizeCoefficients(true);
    segmentation.setModelType(pcl::SACMODEL_LINE);
    segmentation.setMethodType(pcl::SAC_RANSAC);
    segmentation.setMaxIterations(max_iterations_);
    segmentation.setDistanceThreshold(distance_threshold_);
    segmentation.setInputCloud(cloud);

    pcl::PointIndices::Ptr inliers(new pcl::PointIndices);
    pcl::ModelCoefficients::Ptr coefficients(new pcl::ModelCoefficients);
    segmentation.segment(*inliers, *coefficients);

    pcl::ExtractIndices<PointT> extract;
    extract.setInputCloud(cloud);
    extract.setIndices(inliers);
    inlier_cloud = std::make_shared<Cloud>();
    extract.filter(*inlier_cloud);

    stats.inliers = inliers->indices.size();
    stats.inlier_ratio = cloud->empty() ? 0.0 :
      static_cast<double>(stats.inliers) / static_cast<double>(cloud->size());
    return stats;
  }

  void process(const sensor_msgs::msg::PointCloud2::ConstSharedPtr & msg)
  {
    if (done_) {
      return;
    }
    if (!pose_received_) {
      RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 2000,
        "Waiting for pose before processing point clouds.");
      return;
    }

    auto cloud = std::make_shared<Cloud>();
    pcl::fromROSMsg(*msg, *cloud);

    FrameStats stats;
    stats.frame_index = static_cast<int>(frames_seen_);
    stats.raw_points = cloud->size();

    std::vector<int> finite_indices;
    pcl::removeNaNFromPointCloud(*cloud, *cloud, finite_indices);
    stats.finite_points = cloud->size();

    const auto roi_cloud = crop(cloud);
    stats.roi_points = roi_cloud->size();

    CloudPtr inlier_sensor;
    auto ransac_stats = process_ransac(roi_cloud, stats.frame_index, inlier_sensor);
    stats.inliers = ransac_stats.inliers;
    stats.inlier_ratio = ransac_stats.inlier_ratio;

    const auto transform = world_transform_from_latest_pose();
    auto filtered_world = std::make_shared<Cloud>();
    auto inlier_world = std::make_shared<Cloud>();
    pcl::transformPointCloud(*roi_cloud, *filtered_world, transform);
    pcl::transformPointCloud(*inlier_sensor, *inlier_world, transform);
    stats.world_inlier_bbox = compute_bbox(*inlier_world);
    merge_bbox(world_bbox_, stats.world_inlier_bbox);

    const auto frame = std::to_string(stats.frame_index);
    pcl::io::savePCDFileBinary(output_dir_ + "/frame_" + frame + "_filtered_sensor.pcd", *roi_cloud);
    pcl::io::savePCDFileBinary(output_dir_ + "/frame_" + frame + "_line_inliers_sensor.pcd", *inlier_sensor);
    pcl::io::savePCDFileBinary(output_dir_ + "/frame_" + frame + "_filtered_world.pcd", *filtered_world);
    pcl::io::savePCDFileBinary(output_dir_ + "/frame_" + frame + "_line_inliers_world.pcd", *inlier_world);

    stats_.push_back(stats);
    RCLCPP_INFO(get_logger(),
      "frame=%d raw=%zu finite=%zu roi=%zu inliers=%zu ratio=%.3f",
      stats.frame_index,
      stats.raw_points,
      stats.finite_points,
      stats.roi_points,
      stats.inliers,
      stats.inlier_ratio);

    ++frames_seen_;
    if (frames_seen_ >= static_cast<std::size_t>(frames_)) {
      write_summary();
      done_ = true;
    }
  }

  void write_summary()
  {
    const auto stamp = stamp_string();
    const auto summary_txt = output_dir_ + "/" + output_prefix_ + "_" + stamp + ".txt";
    const auto csv_path = output_dir_ + "/" + output_prefix_ + "_" + stamp + ".csv";

    std::ofstream csv(csv_path);
    csv << "frame,raw_points,finite_points,roi_points,ransac_inliers,ransac_inlier_ratio,"
        << "world_min_x,world_min_y,world_min_z,world_max_x,world_max_y,world_max_z\n";

    std::size_t min_inliers = std::numeric_limits<std::size_t>::max();
    std::size_t max_inliers = 0;
    std::size_t failed_frames = 0;
    double inlier_sum = 0.0;
    double ratio_sum = 0.0;

    for (const auto & stats : stats_) {
      min_inliers = std::min(min_inliers, stats.inliers);
      max_inliers = std::max(max_inliers, stats.inliers);
      inlier_sum += static_cast<double>(stats.inliers);
      ratio_sum += stats.inlier_ratio;
      if (stats.inliers < static_cast<std::size_t>(min_inliers_)) {
        ++failed_frames;
      }

      csv << stats.frame_index << ","
          << stats.raw_points << ","
          << stats.finite_points << ","
          << stats.roi_points << ","
          << stats.inliers << ","
          << stats.inlier_ratio << ",";
      if (stats.world_inlier_bbox.valid) {
        csv << stats.world_inlier_bbox.min[0] << ","
            << stats.world_inlier_bbox.min[1] << ","
            << stats.world_inlier_bbox.min[2] << ","
            << stats.world_inlier_bbox.max[0] << ","
            << stats.world_inlier_bbox.max[1] << ","
            << stats.world_inlier_bbox.max[2];
      } else {
        csv << ",,,,,";
      }
      csv << "\n";
    }

    if (stats_.empty()) {
      min_inliers = 0;
    }
    const double frame_count = static_cast<double>(stats_.size());
    const double mean_inliers = frame_count == 0.0 ? 0.0 : inlier_sum / frame_count;
    const double mean_ratio = frame_count == 0.0 ? 0.0 : ratio_sum / frame_count;

    std::ofstream summary(summary_txt);
    summary << "topic: " << topic_ << "\n";
    summary << "pose_topic: " << pose_topic_ << "\n";
    summary << "output_prefix: " << output_prefix_ << "\n";
    summary << "frames_requested: " << frames_ << "\n";
    summary << "frames_processed: " << stats_.size() << "\n";
    summary << "distance_threshold_m: " << distance_threshold_ << "\n";
    summary << "min_inliers: " << min_inliers_ << "\n";
    summary << "apply_sensor_pose_in_link: " << (apply_sensor_pose_in_link_ ? "true" : "false") << "\n";
    summary << "sensor_rpy_rad: " << sensor_roll_rad_ << " " << sensor_pitch_rad_ << " " << sensor_yaw_rad_ << "\n";
    summary << "min_ransac_inliers: " << min_inliers << "\n";
    summary << "max_ransac_inliers: " << max_inliers << "\n";
    summary << "mean_ransac_inliers: " << mean_inliers << "\n";
    summary << "mean_ransac_inlier_ratio: " << mean_ratio << "\n";
    summary << "failed_frames: " << failed_frames << "\n";
    if (world_bbox_.valid) {
      summary << "world_inlier_bbox_min: " << world_bbox_.min[0] << " " << world_bbox_.min[1] << " " << world_bbox_.min[2] << "\n";
      summary << "world_inlier_bbox_max: " << world_bbox_.max[0] << " " << world_bbox_.max[1] << " " << world_bbox_.max[2] << "\n";
    }
    summary << "csv: " << csv_path << "\n";

    result_code_ = failed_frames == 0 && stats_.size() == static_cast<std::size_t>(frames_) ? 0 : 2;
    RCLCPP_INFO(get_logger(), "summary: %s", summary_txt.c_str());
    RCLCPP_INFO(get_logger(), "csv: %s", csv_path.c_str());
  }

  std::string topic_;
  std::string pose_topic_;
  std::string output_dir_;
  std::string output_prefix_;
  int frames_{5};
  double distance_threshold_{0.35};
  int min_inliers_{8};
  int max_iterations_{200};
  double crop_min_x_{-80.0};
  double crop_max_x_{80.0};
  double crop_min_y_{-80.0};
  double crop_max_y_{80.0};
  double crop_min_z_{-10.0};
  double crop_max_z_{10.0};
  bool apply_sensor_pose_in_link_{true};
  double sensor_roll_rad_{0.0};
  double sensor_pitch_rad_{1.51};
  double sensor_yaw_rad_{0.0};
  bool pose_received_{false};
  nav_msgs::msg::Odometry latest_pose_;
  std::size_t frames_seen_{0};
  bool done_{false};
  int result_code_{1};
  std::vector<FrameStats> stats_;
  Bbox world_bbox_;
  rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr pose_subscription_;
  rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr cloud_subscription_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<PointCloudPoseLineRansacWorldSmoke>();

  const auto start = std::chrono::steady_clock::now();
  const auto timeout = std::chrono::seconds(75);
  while (rclcpp::ok() && !node->done()) {
    rclcpp::spin_some(node);
    if (std::chrono::steady_clock::now() - start > timeout) {
      RCLCPP_ERROR(node->get_logger(), "Timed out waiting for posed point clouds.");
      rclcpp::shutdown();
      return 1;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  const int result_code = node->result_code();
  rclcpp::shutdown();
  return result_code;
}
