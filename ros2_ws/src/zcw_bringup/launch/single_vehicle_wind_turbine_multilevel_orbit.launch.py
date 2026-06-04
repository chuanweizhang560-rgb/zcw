import math

from launch import LaunchDescription
from launch_ros.actions import Node


def _orbit_waypoints(center_x=-25.0, center_y=-25.0, radius=20.0):
    levels_ned = [-35.0, -27.333333, -19.666667, -12.0]
    points_per_level = 12
    waypoints = [0.0, 0.0, -8.0]
    yaws = [math.atan2(center_y, center_x)]

    for level_index, z in enumerate(levels_ned):
        point_range = range(points_per_level)
        if level_index % 2 == 1:
            point_range = reversed(range(points_per_level))
        for point in point_range:
            theta = 2.0 * math.pi * point / points_per_level
            x = center_x + radius * math.cos(theta)
            y = center_y + radius * math.sin(theta)
            waypoints.extend([x, y, z])
            yaws.append(math.atan2(center_y - y, center_x - x))

    return waypoints, yaws


def generate_launch_description():
    waypoints, yaws = _orbit_waypoints()
    return LaunchDescription([
        Node(
            package='zcw_px4_baseline',
            executable='offboard_waypoint_sequence',
            name='wind_turbine_multilevel_orbit_baseline',
            output='screen',
            parameters=[{
                'waypoints_ned': waypoints,
                'yaws_rad': yaws,
                'acceptance_radius_m': 3.0,
                'hold_ticks_required': 8,
            }],
        ),
    ])
