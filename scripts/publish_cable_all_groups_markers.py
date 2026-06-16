#!/usr/bin/env python3
import csv
import math
import sys
from collections import defaultdict

import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import ColorRGBA
from visualization_msgs.msg import Marker, MarkerArray


COLORS = [
    (0.10, 0.75, 0.30, 1.0),
    (0.10, 0.45, 0.95, 1.0),
    (0.95, 0.55, 0.10, 1.0),
    (0.85, 0.20, 0.85, 1.0),
    (0.95, 0.15, 0.15, 1.0),
]


def load_grouped_points(path, x_key="x", y_key="y", z_key="z"):
    groups = defaultdict(list)
    with open(path, newline="") as csv_file:
        for row in csv.DictReader(csv_file):
            groups[row["group_id"]].append(
                (
                    int(row.get("index", row.get("current_index", 0))),
                    float(row[x_key]),
                    float(row[y_key]),
                    float(row[z_key]),
                )
            )
    return {key: [p[1:] for p in sorted(value)] for key, value in groups.items()}


def load_grouped_targets(path):
    groups = defaultdict(list)
    with open(path, newline="") as csv_file:
        for row in csv.DictReader(csv_file):
            groups[row["group_id"]].append(
                (
                    int(row["current_index"]),
                    float(row["target_x"]),
                    float(row["target_y"]),
                    float(row["target_z"]),
                )
            )
    return {key: [p[1:] for p in sorted(value)] for key, value in groups.items()}


class CableAllGroupsMarkerPublisher(Node):
    def __init__(self):
        super().__init__("cable_all_groups_marker_publisher")
        self.declare_parameter("offset_path_csv", "")
        self.declare_parameter("targets_csv", "")
        self.declare_parameter("frame_id", "map")
        self.declare_parameter("publish_hz", 1.0)

        self.offset_path_csv = self.get_parameter("offset_path_csv").value
        self.targets_csv = self.get_parameter("targets_csv").value
        self.frame_id = self.get_parameter("frame_id").value
        publish_hz = float(self.get_parameter("publish_hz").value)
        if not self.offset_path_csv or not self.targets_csv:
            raise RuntimeError("offset_path_csv and targets_csv are required")
        if publish_hz <= 0.0 or not math.isfinite(publish_hz):
            raise RuntimeError("publish_hz must be positive")

        self.paths = load_grouped_points(self.offset_path_csv)
        self.targets = load_grouped_targets(self.targets_csv)
        self.group_ids = sorted(set(self.paths) & set(self.targets))
        if not self.group_ids:
            raise RuntimeError("no overlapping groups found")

        self.publisher = self.create_publisher(
            MarkerArray, "/zcw/cable/all_groups/markers", 1
        )
        self.timer = self.create_timer(1.0 / publish_hz, self.publish_markers)
        self.get_logger().info(
            f"Loaded {len(self.group_ids)} cable groups for RViz markers"
        )

    def color(self, index):
        r, g, b, a = COLORS[index % len(COLORS)]
        color = ColorRGBA()
        color.r = r
        color.g = g
        color.b = b
        color.a = a
        return color

    def point(self, xyz):
        from geometry_msgs.msg import Point

        msg = Point()
        msg.x = xyz[0]
        msg.y = xyz[1]
        msg.z = xyz[2]
        return msg

    def marker_base(self, marker_id, namespace, marker_type):
        marker = Marker()
        marker.header.stamp = self.get_clock().now().to_msg()
        marker.header.frame_id = self.frame_id
        marker.ns = namespace
        marker.id = marker_id
        marker.type = marker_type
        marker.action = Marker.ADD
        marker.pose.orientation.w = 1.0
        marker.lifetime.sec = 0
        return marker

    def publish_markers(self):
        markers = MarkerArray()
        for index, group_id in enumerate(self.group_ids):
            color = self.color(index)

            path_marker = self.marker_base(index, "offset_paths", Marker.LINE_STRIP)
            path_marker.scale.x = 0.45
            path_marker.color = color
            path_marker.points = [self.point(xyz) for xyz in self.paths[group_id]]
            markers.markers.append(path_marker)

            target_marker = self.marker_base(100 + index, "lookahead_targets", Marker.SPHERE_LIST)
            target_marker.scale.x = 1.4
            target_marker.scale.y = 1.4
            target_marker.scale.z = 1.4
            target_marker.color = color
            target_marker.points = [self.point(xyz) for xyz in self.targets[group_id]]
            markers.markers.append(target_marker)

            label_marker = self.marker_base(200 + index, "group_labels", Marker.TEXT_VIEW_FACING)
            first = self.paths[group_id][0]
            label_marker.pose.position.x = first[0]
            label_marker.pose.position.y = first[1] - 2.0
            label_marker.pose.position.z = first[2] + 3.0
            label_marker.scale.z = 2.5
            label_marker.color = color
            label_marker.text = group_id
            markers.markers.append(label_marker)

        self.publisher.publish(markers)


def main(argv=None):
    rclpy.init(args=argv)
    node = None
    try:
        node = CableAllGroupsMarkerPublisher()
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        return 0
    except Exception as exc:
        print(f"cable_all_groups_marker_publisher error: {exc}", file=sys.stderr)
        return 1
    finally:
        if node is not None:
            node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
