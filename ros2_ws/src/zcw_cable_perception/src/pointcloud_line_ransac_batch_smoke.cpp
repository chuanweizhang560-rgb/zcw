#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <memory>
#include <numeric>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <Eigen/Core>
#include <pcl/ModelCoefficients.h>
#include <pcl/filters/crop_box.h>
#include <pcl/filters/extract_indices.h>
#include <pcl/filters/filter.h>
#include <pcl/filters/statistical_outlier_removal.h>
#include <pcl/filters/voxel_grid.h>
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

using Cloud = pcl::PointCloud<pcl::PointXYZI>;
using CloudPtr = Cloud::Ptr;

struct FrameStats
{
  int frame_index{0};
  std::size_t raw_points{0};
  std::size_t finite_points{0};
  std::size_t roi_points{0};
  std::size_t filtered_points{0};
  std::size_t inliers{0};
  double inlier_ratio{0.0};
  std::vector<float> coefficients;
};
}  // namespace

class PointCloudLineRansacBatchSmoke : public rclcpp::Node
{
public:
  PointCloudLineRansacBatchSmoke()
  : Node("pointcloud_line_ransac_batch_smoke")
  {
    topic_ = declare_parameter<std::string>("topic", "/zcw/foggy_lidar/points");
    output_dir_ = declare_parameter<std::string>("output_dir", "data/results");
    frames_ = declare_parameter<int>("frames", 5);
    distance_threshold_ = declare_parameter<double>("distance_threshold_m", 0.35);
    min_inliers_ = declare_parameter<int>("min_inliers", 8);
    max_iterations_ = declare_parameter<int>("max_iterations", 200);
    enable_crop_ = declare_parameter<bool>("enable_crop", true);
    crop_min_x_ = declare_parameter<double>("crop_min_x", -80.0);
    crop_max_x_ = declare_parameter<double>("crop_max_x", 80.0);
    crop_min_y_ = declare_parameter<double>("crop_min_y", -80.0);
    crop_max_y_ = declare_parameter<double>("crop_max_y", 80.0);
    crop_min_z_ = declare_parameter<double>("crop_min_z", -10.0);
    crop_max_z_ = declare_parameter<double>("crop_max_z", 10.0);
    voxel_leaf_m_ = declare_parameter<double>("voxel_leaf_m", 0.0);
    sor_mean_k_ = declare_parameter<int>("sor_mean_k", 0);
    sor_stddev_mul_ = declare_parameter<double>("sor_stddev_mul", 1.0);
    save_pcd_ = declare_parameter<bool>("save_pcd", true);

    if (frames_ <= 0) {
      frames_ = 1;
    }
    std::filesystem::create_directories(output_dir_);

    subscription_ = create_subscription<sensor_msgs::msg::PointCloud2>(
      topic_,
      rclcpp::SensorDataQoS(),
      [this](sensor_msgs::msg::PointCloud2::ConstSharedPtr msg) {
        process(msg);
      });

    RCLCPP_INFO(get_logger(), "Waiting for %d PointCloud2 frames on %s", frames_, topic_.c_str());
  }

  bool done() const { return done_; }
  int result_code() const { return result_code_; }

private:
  CloudPtr crop(const CloudPtr & input) const
  {
    if (!enable_crop_) {
      return input;
    }
    auto cropped = std::make_shared<Cloud>();
    pcl::CropBox<pcl::PointXYZI> crop_box;
    crop_box.setMin(Eigen::Vector4f(crop_min_x_, crop_min_y_, crop_min_z_, 1.0f));
    crop_box.setMax(Eigen::Vector4f(crop_max_x_, crop_max_y_, crop_max_z_, 1.0f));
    crop_box.setInputCloud(input);
    crop_box.filter(*cropped);
    return cropped;
  }

  CloudPtr filter(const CloudPtr & input) const
  {
    CloudPtr current = input;
    if (voxel_leaf_m_ > 0.0 && input->size() > 1) {
      auto voxel = std::make_shared<Cloud>();
      pcl::VoxelGrid<pcl::PointXYZI> voxel_grid;
      voxel_grid.setInputCloud(current);
      voxel_grid.setLeafSize(voxel_leaf_m_, voxel_leaf_m_, voxel_leaf_m_);
      voxel_grid.filter(*voxel);
      current = voxel;
    }

    if (sor_mean_k_ > 1 && current->size() > static_cast<std::size_t>(sor_mean_k_)) {
      auto denoised = std::make_shared<Cloud>();
      pcl::StatisticalOutlierRemoval<pcl::PointXYZI> sor;
      sor.setInputCloud(current);
      sor.setMeanK(sor_mean_k_);
      sor.setStddevMulThresh(sor_stddev_mul_);
      sor.filter(*denoised);
      current = denoised;
    }
    return current;
  }

  FrameStats run_ransac(const CloudPtr & cloud, int frame_index) const
  {
    FrameStats stats;
    stats.frame_index = frame_index;
    stats.filtered_points = cloud->size();

    if (cloud->empty()) {
      return stats;
    }

    pcl::SACSegmentation<pcl::PointXYZI> segmentation;
    segmentation.setOptimizeCoefficients(true);
    segmentation.setModelType(pcl::SACMODEL_LINE);
    segmentation.setMethodType(pcl::SAC_RANSAC);
    segmentation.setMaxIterations(max_iterations_);
    segmentation.setDistanceThreshold(distance_threshold_);
    segmentation.setInputCloud(cloud);

    pcl::PointIndices::Ptr inliers(new pcl::PointIndices);
    pcl::ModelCoefficients::Ptr coefficients(new pcl::ModelCoefficients);
    segmentation.segment(*inliers, *coefficients);

    stats.inliers = inliers->indices.size();
    stats.inlier_ratio = stats.filtered_points == 0 ? 0.0 :
      static_cast<double>(stats.inliers) / static_cast<double>(stats.filtered_points);
    stats.coefficients = coefficients->values;

    if (save_pcd_) {
      pcl::ExtractIndices<pcl::PointXYZI> extract;
      extract.setInputCloud(cloud);
      extract.setIndices(inliers);
      auto inlier_cloud = std::make_shared<Cloud>();
      extract.filter(*inlier_cloud);

      const auto frame = std::to_string(frame_index);
      pcl::io::savePCDFileBinary(output_dir_ + "/frame_" + frame + "_filtered.pcd", *cloud);
      pcl::io::savePCDFileBinary(output_dir_ + "/frame_" + frame + "_line_inliers.pcd", *inlier_cloud);
    }

    return stats;
  }

  void process(const sensor_msgs::msg::PointCloud2::ConstSharedPtr & msg)
  {
    if (done_) {
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
    const auto filtered_cloud = filter(roi_cloud);

    auto ransac_stats = run_ransac(filtered_cloud, stats.frame_index);
    ransac_stats.raw_points = stats.raw_points;
    ransac_stats.finite_points = stats.finite_points;
    ransac_stats.roi_points = stats.roi_points;
    stats_.push_back(ransac_stats);

    RCLCPP_INFO(get_logger(),
      "frame=%d raw=%zu finite=%zu roi=%zu filtered=%zu inliers=%zu ratio=%.3f",
      ransac_stats.frame_index,
      ransac_stats.raw_points,
      ransac_stats.finite_points,
      ransac_stats.roi_points,
      ransac_stats.filtered_points,
      ransac_stats.inliers,
      ransac_stats.inlier_ratio);

    ++frames_seen_;
    if (frames_seen_ >= static_cast<std::size_t>(frames_)) {
      write_summary();
      done_ = true;
    }
  }

  void write_summary()
  {
    const auto stamp = stamp_string();
    const auto summary_txt = output_dir_ + "/foggy_lidar_line_ransac_batch_" + stamp + ".txt";
    const auto csv_path = output_dir_ + "/foggy_lidar_line_ransac_batch_" + stamp + ".csv";

    std::ofstream csv(csv_path);
    csv << "frame,raw_points,finite_points,roi_points,filtered_points,ransac_inliers,"
        << "ransac_inlier_ratio,coefficients\n";

    std::size_t min_inliers = std::numeric_limits<std::size_t>::max();
    std::size_t max_inliers = 0;
    std::size_t failed_frames = 0;
    double ratio_sum = 0.0;
    double inlier_sum = 0.0;

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
          << stats.filtered_points << ","
          << stats.inliers << ","
          << stats.inlier_ratio << ",\"";
      for (std::size_t i = 0; i < stats.coefficients.size(); ++i) {
        if (i > 0) {
          csv << " ";
        }
        csv << stats.coefficients[i];
      }
      csv << "\"\n";
    }

    if (stats_.empty()) {
      min_inliers = 0;
    }
    const double frame_count = static_cast<double>(stats_.size());
    const double mean_inliers = frame_count == 0.0 ? 0.0 : inlier_sum / frame_count;
    const double mean_ratio = frame_count == 0.0 ? 0.0 : ratio_sum / frame_count;

    std::ofstream summary(summary_txt);
    summary << "topic: " << topic_ << "\n";
    summary << "frames_requested: " << frames_ << "\n";
    summary << "frames_processed: " << stats_.size() << "\n";
    summary << "distance_threshold_m: " << distance_threshold_ << "\n";
    summary << "max_iterations: " << max_iterations_ << "\n";
    summary << "min_inliers: " << min_inliers_ << "\n";
    summary << "enable_crop: " << (enable_crop_ ? "true" : "false") << "\n";
    summary << "crop_min: " << crop_min_x_ << " " << crop_min_y_ << " " << crop_min_z_ << "\n";
    summary << "crop_max: " << crop_max_x_ << " " << crop_max_y_ << " " << crop_max_z_ << "\n";
    summary << "voxel_leaf_m: " << voxel_leaf_m_ << "\n";
    summary << "sor_mean_k: " << sor_mean_k_ << "\n";
    summary << "sor_stddev_mul: " << sor_stddev_mul_ << "\n";
    summary << "min_ransac_inliers: " << min_inliers << "\n";
    summary << "max_ransac_inliers: " << max_inliers << "\n";
    summary << "mean_ransac_inliers: " << mean_inliers << "\n";
    summary << "mean_ransac_inlier_ratio: " << mean_ratio << "\n";
    summary << "failed_frames: " << failed_frames << "\n";
    summary << "csv: " << csv_path << "\n";

    result_code_ = failed_frames == 0 && stats_.size() == static_cast<std::size_t>(frames_) ? 0 : 2;
    RCLCPP_INFO(get_logger(), "summary: %s", summary_txt.c_str());
    RCLCPP_INFO(get_logger(), "csv: %s", csv_path.c_str());
  }

  std::string topic_;
  std::string output_dir_;
  int frames_{5};
  double distance_threshold_{0.35};
  int min_inliers_{8};
  int max_iterations_{200};
  bool enable_crop_{true};
  double crop_min_x_{-80.0};
  double crop_max_x_{80.0};
  double crop_min_y_{-80.0};
  double crop_max_y_{80.0};
  double crop_min_z_{-10.0};
  double crop_max_z_{10.0};
  double voxel_leaf_m_{0.0};
  int sor_mean_k_{0};
  double sor_stddev_mul_{1.0};
  bool save_pcd_{true};
  std::size_t frames_seen_{0};
  bool done_{false};
  int result_code_{1};
  std::vector<FrameStats> stats_;
  rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr subscription_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<PointCloudLineRansacBatchSmoke>();

  const auto start = std::chrono::steady_clock::now();
  const auto timeout = std::chrono::seconds(60);
  while (rclcpp::ok() && !node->done()) {
    rclcpp::spin_some(node);
    if (std::chrono::steady_clock::now() - start > timeout) {
      RCLCPP_ERROR(node->get_logger(), "Timed out waiting for batch point clouds.");
      rclcpp::shutdown();
      return 1;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  const int result_code = node->result_code();
  rclcpp::shutdown();
  return result_code;
}
