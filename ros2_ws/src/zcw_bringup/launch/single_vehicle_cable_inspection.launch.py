from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    # AerialCore power_towers_danube_wires_rescaled_autospawn.world places the
    # two-tower/wire asset around [-25, -25, 0]. These fixed waypoints form a
    # first cable-corridor baseline; later cable following should replace this
    # with PCL/catenary/Frenet tracking.
    return LaunchDescription([
        Node(
            package='zcw_px4_baseline',
            executable='offboard_waypoint_sequence',
            name='cable_waypoint_baseline',
            output='screen',
            parameters=[{
                'waypoints_ned': [
                    0.0, 0.0, -10.0,
                    -50.0, -35.0, -22.0,
                    -5.0, -25.0, -22.0,
                    -50.0, -15.0, -22.0,
                    -5.0, -5.0, -22.0,
                    -50.0, -35.0, -22.0,
                ],
                'acceptance_radius_m': 4.0,
                'hold_ticks_required': 10,
            }],
        ),
    ])
