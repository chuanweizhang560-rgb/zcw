from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='zcw_px4_baseline',
            executable='offboard_waypoint_sequence',
            name='offboard_waypoint_sequence',
            output='screen',
            parameters=[{
                'waypoints_ned': [
                    0.0, 0.0, -5.0,
                    8.0, 0.0, -5.0,
                    8.0, 8.0, -5.0,
                    0.0, 8.0, -5.0,
                    0.0, 0.0, -5.0,
                ],
                'acceptance_radius_m': 1.0,
                'hold_ticks_required': 15,
            }],
        ),
    ])
