from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    # AerialCore wind_turbine_autospawn.world places the turbine at about
    # [-25, -25, 0] in Gazebo/PX4 local ENU/NED-aligned world coordinates.
    return LaunchDescription([
        Node(
            package='zcw_px4_baseline',
            executable='offboard_waypoint_sequence',
            name='wind_turbine_waypoint_baseline',
            output='screen',
            parameters=[{
                'waypoints_ned': [
                    0.0, 0.0, -8.0,
                    -5.0, -25.0, -20.0,
                    -25.0, -5.0, -20.0,
                    -45.0, -25.0, -20.0,
                    -25.0, -45.0, -20.0,
                    -5.0, -25.0, -20.0,
                ],
                'acceptance_radius_m': 3.0,
                'hold_ticks_required': 10,
            }],
        ),
    ])
