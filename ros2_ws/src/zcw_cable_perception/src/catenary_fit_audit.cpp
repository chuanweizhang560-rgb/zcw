#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <ceres/ceres.h>
#include <Eigen/Dense>

namespace
{
struct Candidate
{
  int frame{0};
  int line{0};
  int inliers{0};
  double inlier_ratio{0.0};
  double point_x{0.0};
  double point_y{0.0};
  double point_z{0.0};
  double dir_x{0.0};
  double dir_y{0.0};
  double dir_z{0.0};
  double min_x{0.0};
  double min_y{0.0};
  double min_z{0.0};
  double max_x{0.0};
  double max_y{0.0};
  double max_z{0.0};
};

struct Sample
{
  std::string group_id;
  double x{0.0};
  double y{0.0};
  double z{0.0};
};

struct Args
{
  std::string input_csv;
  std::string output_dir{"data/results"};
  std::string output_prefix{"catenary_fit_audit"};
  std::string group_mode{"yz"};
  double y_bin_size{2.0};
  double z_bin_size{3.0};
  double min_abs_dir_x{0.85};
  double max_abs_dir_y{0.05};
  double max_abs_dir_z{0.18};
  double min_x_span{40.0};
  double max_y_span{5.0};
  double max_z_span{18.0};
  int min_samples_per_group{6};
  double max_catenary_rmse{1.0};
  double max_quadratic_rmse{1.0};
};

struct FitResult
{
  std::string group_id;
  int samples{0};
  double mean_y{0.0};
  double min_x{std::numeric_limits<double>::infinity()};
  double max_x{-std::numeric_limits<double>::infinity()};
  double min_z{std::numeric_limits<double>::infinity()};
  double max_z{-std::numeric_limits<double>::infinity()};
  double catenary_a{0.0};
  double catenary_b{0.0};
  double catenary_c{0.0};
  double catenary_rmse{std::numeric_limits<double>::infinity()};
  double catenary_max_abs_error{std::numeric_limits<double>::infinity()};
  bool catenary_converged{false};
  double quad_p0{0.0};
  double quad_p1{0.0};
  double quad_p2{0.0};
  double quad_rmse{std::numeric_limits<double>::infinity()};
  double quad_max_abs_error{std::numeric_limits<double>::infinity()};
  bool accepted{false};
};

std::vector<std::string> split_csv_line(const std::string & line)
{
  std::vector<std::string> out;
  std::stringstream ss(line);
  std::string item;
  while (std::getline(ss, item, ',')) {
    out.push_back(item);
  }
  return out;
}

double to_double(const std::string & value) { return std::stod(value); }
int to_int(const std::string & value) { return std::stoi(value); }

std::vector<Candidate> read_candidates(const std::string & path)
{
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("failed to open input csv: " + path);
  }
  std::vector<Candidate> candidates;
  std::string line;
  bool first = true;
  while (std::getline(in, line)) {
    if (line.empty()) {
      continue;
    }
    if (first) {
      first = false;
      continue;
    }
    const auto cols = split_csv_line(line);
    if (cols.size() != 16) {
      throw std::runtime_error("unexpected csv column count in line: " + line);
    }
    Candidate c;
    c.frame = to_int(cols[0]);
    c.line = to_int(cols[1]);
    c.inliers = to_int(cols[2]);
    c.inlier_ratio = to_double(cols[3]);
    c.point_x = to_double(cols[4]);
    c.point_y = to_double(cols[5]);
    c.point_z = to_double(cols[6]);
    c.dir_x = to_double(cols[7]);
    c.dir_y = to_double(cols[8]);
    c.dir_z = to_double(cols[9]);
    c.min_x = to_double(cols[10]);
    c.min_y = to_double(cols[11]);
    c.min_z = to_double(cols[12]);
    c.max_x = to_double(cols[13]);
    c.max_y = to_double(cols[14]);
    c.max_z = to_double(cols[15]);
    if (c.dir_x < 0.0) {
      c.dir_x = -c.dir_x;
      c.dir_y = -c.dir_y;
      c.dir_z = -c.dir_z;
    }
    candidates.push_back(c);
  }
  return candidates;
}

bool passes_geometry_gate(const Candidate & c, const Args & args)
{
  const double x_span = c.max_x - c.min_x;
  const double y_span = c.max_y - c.min_y;
  const double z_span = c.max_z - c.min_z;
  return std::abs(c.dir_x) >= args.min_abs_dir_x &&
         std::abs(c.dir_y) <= args.max_abs_dir_y &&
         std::abs(c.dir_z) <= args.max_abs_dir_z &&
         x_span >= args.min_x_span &&
         y_span <= args.max_y_span &&
         z_span <= args.max_z_span;
}

std::string group_key_for(const Candidate & c, const Args & args)
{
  const int y_bin = static_cast<int>(std::floor(c.point_y / args.y_bin_size));
  const int z_bin = static_cast<int>(std::floor(c.point_z / args.z_bin_size));
  if (args.group_mode == "z") {
    return "z" + std::to_string(z_bin);
  }
  if (args.group_mode == "yz") {
    return "y" + std::to_string(y_bin) + "_z" + std::to_string(z_bin);
  }
  return "y" + std::to_string(y_bin);
}

std::vector<Sample> samples_from_candidate(const Candidate & c, const Args & args)
{
  const auto group_id = group_key_for(c, args);
  const double y = 0.5 * (c.min_y + c.max_y);
  const double z_mid = 0.5 * (c.min_z + c.max_z);
  return {
    Sample{group_id, c.min_x, y, c.min_z},
    Sample{group_id, c.point_x, c.point_y, c.point_z},
    Sample{group_id, c.max_x, y, c.max_z},
    Sample{group_id, 0.5 * (c.min_x + c.max_x), y, z_mid}};
}

struct CatenaryResidual
{
  CatenaryResidual(double x_in, double z_in) : x(x_in), z(z_in) {}

  template<typename T>
  bool operator()(const T * const params, T * residual) const
  {
    const T a = exp(params[0]);
    const T b = params[1];
    const T c = params[2];
    residual[0] = a * cosh((T(x) - b) / a) + c - T(z);
    return true;
  }

  double x;
  double z;
};

double catenary_eval(double a, double b, double c, double x)
{
  return a * std::cosh((x - b) / a) + c;
}

FitResult fit_group(const std::string & group_id, const std::vector<Sample> & samples)
{
  FitResult result;
  result.group_id = group_id;
  result.samples = static_cast<int>(samples.size());

  double sum_y = 0.0;
  double sum_x = 0.0;
  double sum_z = 0.0;
  for (const auto & s : samples) {
    sum_y += s.y;
    sum_x += s.x;
    sum_z += s.z;
    result.min_x = std::min(result.min_x, s.x);
    result.max_x = std::max(result.max_x, s.x);
    result.min_z = std::min(result.min_z, s.z);
    result.max_z = std::max(result.max_z, s.z);
  }
  result.mean_y = sum_y / static_cast<double>(samples.size());
  const double mean_x = sum_x / static_cast<double>(samples.size());
  const double mean_z = sum_z / static_cast<double>(samples.size());

  double params[3] = {std::log(10000.0), mean_x, mean_z - 10000.0};
  ceres::Problem problem;
  for (const auto & s : samples) {
    problem.AddResidualBlock(
      new ceres::AutoDiffCostFunction<CatenaryResidual, 1, 3>(
        new CatenaryResidual(s.x, s.z)),
      nullptr,
      params);
  }
  ceres::Solver::Options options;
  options.max_num_iterations = 100;
  options.linear_solver_type = ceres::DENSE_QR;
  options.minimizer_progress_to_stdout = false;
  ceres::Solver::Summary summary;
  ceres::Solve(options, &problem, &summary);

  result.catenary_a = std::exp(params[0]);
  result.catenary_b = params[1];
  result.catenary_c = params[2];
  result.catenary_converged = summary.IsSolutionUsable();

  double cat_sse = 0.0;
  double cat_max = 0.0;
  for (const auto & s : samples) {
    const double err = catenary_eval(result.catenary_a, result.catenary_b, result.catenary_c, s.x) - s.z;
    cat_sse += err * err;
    cat_max = std::max(cat_max, std::abs(err));
  }
  result.catenary_rmse = std::sqrt(cat_sse / static_cast<double>(samples.size()));
  result.catenary_max_abs_error = cat_max;

  Eigen::MatrixXd a(samples.size(), 3);
  Eigen::VectorXd z(samples.size());
  for (std::size_t i = 0; i < samples.size(); ++i) {
    a(static_cast<int>(i), 0) = 1.0;
    a(static_cast<int>(i), 1) = samples[i].x;
    a(static_cast<int>(i), 2) = samples[i].x * samples[i].x;
    z(static_cast<int>(i)) = samples[i].z;
  }
  const Eigen::Vector3d coeff = a.colPivHouseholderQr().solve(z);
  result.quad_p0 = coeff[0];
  result.quad_p1 = coeff[1];
  result.quad_p2 = coeff[2];

  double quad_sse = 0.0;
  double quad_max = 0.0;
  for (const auto & s : samples) {
    const double pred = result.quad_p0 + result.quad_p1 * s.x + result.quad_p2 * s.x * s.x;
    const double err = pred - s.z;
    quad_sse += err * err;
    quad_max = std::max(quad_max, std::abs(err));
  }
  result.quad_rmse = std::sqrt(quad_sse / static_cast<double>(samples.size()));
  result.quad_max_abs_error = quad_max;
  return result;
}

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

void print_usage()
{
  std::cerr
    << "Usage: catenary_fit_audit --input <lines.csv> [options]\n"
    << "Options:\n"
    << "  --output-dir <dir>\n"
    << "  --output-prefix <name>\n"
    << "  --group-mode <y|z|yz>\n"
    << "  --y-bin-size <meters>\n"
    << "  --z-bin-size <meters>\n"
    << "  --max-catenary-rmse <meters>\n"
    << "  --max-quadratic-rmse <meters>\n";
}

Args parse_args(int argc, char ** argv)
{
  Args args;
  for (int i = 1; i < argc; ++i) {
    const std::string key = argv[i];
    auto require_value = [&](const std::string & option) -> std::string {
      if (i + 1 >= argc) {
        throw std::runtime_error("missing value for " + option);
      }
      return argv[++i];
    };
    if (key == "--input") {
      args.input_csv = require_value(key);
    } else if (key == "--output-dir") {
      args.output_dir = require_value(key);
    } else if (key == "--output-prefix") {
      args.output_prefix = require_value(key);
    } else if (key == "--group-mode") {
      args.group_mode = require_value(key);
    } else if (key == "--y-bin-size") {
      args.y_bin_size = to_double(require_value(key));
    } else if (key == "--z-bin-size") {
      args.z_bin_size = to_double(require_value(key));
    } else if (key == "--max-catenary-rmse") {
      args.max_catenary_rmse = to_double(require_value(key));
    } else if (key == "--max-quadratic-rmse") {
      args.max_quadratic_rmse = to_double(require_value(key));
    } else if (key == "--help" || key == "-h") {
      print_usage();
      std::exit(0);
    } else {
      throw std::runtime_error("unknown argument: " + key);
    }
  }
  if (args.input_csv.empty()) {
    throw std::runtime_error("--input is required");
  }
  if (args.group_mode != "y" && args.group_mode != "z" && args.group_mode != "yz") {
    throw std::runtime_error("--group-mode must be y, z, or yz");
  }
  return args;
}
}  // namespace

int main(int argc, char ** argv)
{
  try {
    const Args args = parse_args(argc, argv);
    std::filesystem::create_directories(args.output_dir);

    const auto candidates = read_candidates(args.input_csv);
    std::map<std::string, std::vector<Sample>> grouped_samples;
    int accepted_candidates = 0;
    for (const auto & c : candidates) {
      if (!passes_geometry_gate(c, args)) {
        continue;
      }
      ++accepted_candidates;
      for (const auto & sample : samples_from_candidate(c, args)) {
        grouped_samples[sample.group_id].push_back(sample);
      }
    }

    std::vector<FitResult> results;
    for (const auto & item : grouped_samples) {
      if (static_cast<int>(item.second.size()) < args.min_samples_per_group) {
        continue;
      }
      auto result = fit_group(item.first, item.second);
      result.accepted = result.catenary_converged &&
        result.catenary_rmse <= args.max_catenary_rmse &&
        result.quad_rmse <= args.max_quadratic_rmse;
      results.push_back(result);
    }

    const auto stamp = stamp_string();
    const auto summary_path = args.output_dir + "/" + args.output_prefix + "_" + stamp + ".txt";
    const auto fits_path = args.output_dir + "/" + args.output_prefix + "_fits_" + stamp + ".csv";
    const auto samples_path = args.output_dir + "/" + args.output_prefix + "_samples_" + stamp + ".csv";

    std::ofstream samples_csv(samples_path);
    samples_csv << "group_id,x,y,z\n";
    for (const auto & item : grouped_samples) {
      for (const auto & s : item.second) {
        samples_csv << s.group_id << "," << s.x << "," << s.y << "," << s.z << "\n";
      }
    }

    int accepted_fits = 0;
    std::ofstream fits_csv(fits_path);
    fits_csv << "group_id,samples,mean_y,min_x,max_x,min_z,max_z,"
             << "catenary_a,catenary_b,catenary_c,catenary_rmse,catenary_max_abs_error,catenary_converged,"
             << "quad_p0,quad_p1,quad_p2,quad_rmse,quad_max_abs_error,accepted\n";
    for (const auto & r : results) {
      if (r.accepted) {
        ++accepted_fits;
      }
      fits_csv << r.group_id << ","
               << r.samples << ","
               << r.mean_y << ","
               << r.min_x << ","
               << r.max_x << ","
               << r.min_z << ","
               << r.max_z << ","
               << r.catenary_a << ","
               << r.catenary_b << ","
               << r.catenary_c << ","
               << r.catenary_rmse << ","
               << r.catenary_max_abs_error << ","
               << (r.catenary_converged ? "true" : "false") << ","
               << r.quad_p0 << ","
               << r.quad_p1 << ","
               << r.quad_p2 << ","
               << r.quad_rmse << ","
               << r.quad_max_abs_error << ","
               << (r.accepted ? "true" : "false") << "\n";
    }

    std::ofstream summary(summary_path);
    summary << "input_csv: " << args.input_csv << "\n";
    summary << "total_candidates: " << candidates.size() << "\n";
    summary << "geometry_gate_candidates: " << accepted_candidates << "\n";
    summary << "group_mode: " << args.group_mode << "\n";
    summary << "y_bin_size: " << args.y_bin_size << "\n";
    summary << "z_bin_size: " << args.z_bin_size << "\n";
    summary << "groups_with_samples: " << grouped_samples.size() << "\n";
    summary << "fit_groups: " << results.size() << "\n";
    summary << "accepted_fits: " << accepted_fits << "\n";
    summary << "max_catenary_rmse: " << args.max_catenary_rmse << "\n";
    summary << "max_quadratic_rmse: " << args.max_quadratic_rmse << "\n";
    summary << "samples_csv: " << samples_path << "\n";
    summary << "fits_csv: " << fits_path << "\n";
    summary << "decision: "
            << (accepted_fits > 0 ? "accepted_catenary_fit_smoke" : "rejected_catenary_fit_smoke")
            << "\n";

    std::cout << "Catenary fit audit completed.\n";
    std::cout << "Summary: " << summary_path << "\n";
    std::cout << "Fits CSV: " << fits_path << "\n";
    std::cout << "Samples CSV: " << samples_path << "\n";
    std::cout << "Accepted fits: " << accepted_fits << "\n";
    return accepted_fits > 0 ? 0 : 2;
  } catch (const std::exception & e) {
    std::cerr << "catenary_fit_audit error: " << e.what() << "\n";
    print_usage();
    return 1;
  }
}
