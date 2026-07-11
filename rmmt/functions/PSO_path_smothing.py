import numpy as np
from numpy import random
from PSO_implimentation_mat_ import *
import matplotlib.pyplot as plt
from scipy.interpolate import CubicSpline
from obstacle_list import obstacle_list_value, obstacles_list
from collections import OrderedDict
from scipy.signal import savgol_filter
from copy import copy, deepcopy
from helper_data_prepration_planner_random import helper_DPR_obj

name_obstacleList = list(obstacles_list.keys()) 


class PathSmooting:

    def __init__(self):
        pass

    @staticmethod
    def plotway_points(way_points):
        """
        Plots a smooth path using cubic spline interpolation.
        """
        plt.plot(way_points[:, 0], way_points[:, 1], "g-", label="Smooth Path")
        plt.title("Cubic Spline Interpolation")
        plt.xlabel("x")
        plt.ylabel("y")

    @staticmethod
    def plotobstacles(obstacle_list_value, map_num):
        """
        Plots obstacles on a map based on the obstacle list.
        """
        i = 0
        for obs in obstacle_list_value[map_num]:
            if i == 0:
                plt.plot(obs[:, 0], obs[:, 1], "-r", linewidth=0.5, label="Obstacles")
                i = i + 1
            else:
                plt.plot(obs[:, 0], obs[:, 1], "-r", linewidth=0.5)

    @staticmethod
    def smooth_path(way_points, shortest_path_length, axes_objects, obstacles):
        """
        CONSERVATIVE smoothing: Only optimize every OTHER waypoint to minimize deviation
        """
        
        modified_array, flip = helper_DPR_obj.XstriclyIncreasingOrder(way_points[0])
        way_points[0] = modified_array 

        l = len(way_points[0])
        
        # If path is too short, return original
        if l < 3:
            return way_points[0], way_points[0]
        
        print(f"\nSmoothing path with {l} waypoints...")
        
        # STRATEGY: Only optimize every OTHER interior waypoint to stay close to A* path
        # Skip: 1st (start) and last (goal) - they are fixed
        # For paths with many waypoints, skip some to reduce deviation
        
        way_points_new = np.empty((0, 2))
        
        # Determine which waypoints to optimize based on path length
        if l <= 5:
            # Short path: optimize all interior points
            optimize_step = 1
        elif l <= 10:
            # Medium path: optimize every other point
            optimize_step = 2
        else:
            # Long path: optimize every 3rd point
            optimize_step = 3
        
        print(f"Optimization strategy: Every {optimize_step} waypoint(s)")
        
        # Always start with the first point
        way_points_new = np.array([way_points[0][0]])
        
        # Process waypoints
        for i in range(1, l - 1):  # Skip first and last
            
            # Decide if we should optimize this waypoint
            if i % optimize_step == 0:
                # Create a 3-point segment for PSO optimization
                if i == 1:
                    # First interior point: use [start, point, next]
                    ws = way_points[0][0:3]
                elif i == l - 2:
                    # Last interior point: use [prev, point, goal]
                    ws = way_points[0][-3:]
                else:
                    # Middle point: use [prev, point, next]
                    ws = way_points[0][i-1:i+2]
                
                print(f"  Optimizing waypoint {i}/{l-1}...")
                
                [boundryCondition, nVar] = helper_DPR_obj.boundryCondition(ws)

                Pso_optimizer = PsoOptimizer(
                    ws, shortest_path_length, boundryCondition, nVar, axes_objects, obstacles
                )
                Modiway_points_full = Pso_optimizer.optimization_smooth_path(ws, axes_objects)
                
                # Add the optimized middle point
                way_points_new = np.concatenate((way_points_new, Modiway_points_full[1].reshape(1, -1)))
            else:
                # Keep original waypoint without optimization
                way_points_new = np.concatenate((way_points_new, way_points[0][i].reshape(1, -1)))
        
        # Always end with the last point (goal)
        way_points_new = np.concatenate((way_points_new, way_points[0][-1].reshape(1, -1)))

        control_way_points = way_points_new
        
        print(f"Control points generated: {len(control_way_points)}")
        
        # Perform final cubic spline smoothing over the control points
        try:
            smoth_way_points, smoth_way_pointsLenght = helper_DPR_obj.smoothPathLength(
                control_way_points
            )
            print(f"Final smooth path: {len(smoth_way_points)} points, length: {smoth_way_pointsLenght:.2f}m")
        except Exception as e:
            print(f"ERROR in final smoothing: {e}")
            # Fallback to control points if spline fails
            smoth_way_points = control_way_points
            smoth_way_pointsLenght = helper_DPR_obj.lengthPath(
                control_way_points[:, 0], control_way_points[:, 1]
            )

        return [smoth_way_points, control_way_points]

    @staticmethod
    def find_curvature(smoth_way_points):
        """
        Calculates and plots the curvature of the smoothed path.
        """
        t = np.linspace(0, 160, 1000)
        x = smoth_way_points[:, 0]
        y = smoth_way_points[:, 1]
        window_size = 5
        poly_order = 2

        cs_x = CubicSpline(t, x)
        cs_y = CubicSpline(t, y)

        dx = cs_x(t, 1)
        dy = cs_y(t, 1)
        d2x = cs_x(t, 2)
        d2y = cs_y(t, 2)

        curvature = np.abs(dx * d2y - dy * d2x) / (dx**2 + dy**2) ** (3 / 2)
        window_size = 4
        poly_order = 2
        curvature = savgol_filter(curvature, window_size, poly_order)

        plt.figure(figsize=(12, 6))
        plt.subplot(1, 2, 1)
        plt.plot(x, y, label="Path")
        plt.xlabel("x")
        plt.ylabel("y")
        plt.title("Path")
        plt.legend()

        plt.subplot(1, 2, 2)
        plt.plot(t, curvature, label="Curvature")
        plt.xlabel("Parameter (t)")
        plt.ylabel("Curvature")
        plt.title("Curvature along the Path")
        plt.legend()

        plt.tight_layout()
        plt.show()


if __name__ == "__main__":
    
    map_num = 11

    obts = deepcopy(obstacle_list_value[map_num])
    obts = helper_DPR_obj.strching_obstacles(obts)
    
    startPoint = [int(155), int(5)]
    endPoint = [int(5), int(155)]
    
    plt.figure("Welcome to figure 1")
    plt.xlim(0, 160)
    plt.ylim(0, 160)
    (StartL,) = plt.plot(startPoint[0], startPoint[1], "o", color="red", label="Start")
    (GoalL,) = plt.plot(endPoint[0], endPoint[1], "o", color="green", label="Goal")
    handles, labels = plt.gca().get_legend_handles_labels()
    by_label = OrderedDict(zip(labels, handles))

    plt.legend(by_label.values(), by_label.keys(), loc="upper left", prop={"size": 6})

    fig, axes_objects = plt.subplots(3, 2, sharex=True, sharey=True)

    plt.figure("Welcome to figure 1")
    PathSmooting.plotobstacles(obstacle_list_value, map_num) 

    way_points, waypoint_np, shortest_path_length = (
        helper_DPR_obj.shortest_pathand_length(startPoint, endPoint, obts)
    )
    
    [smoth_way_points, control_way_points] = PathSmooting.smooth_path(
        way_points, shortest_path_length, axes_objects, obts
    )
    
    print(control_way_points)
    (pathL,) = plt.plot(
        smoth_way_points[:, 0],
        smoth_way_points[:, 1],
        "-",
        color="blue",
        label="Smooth Path",
    )

    dsmoth_way_points = np.diff(smoth_way_points[:, 1]) / np.diff(
        smoth_way_points[:, 0]
    )
    ddsmoth_way_points = np.diff(dsmoth_way_points) / np.diff(smoth_way_points[0:-1, 0])
    dx = smoth_way_points[0:-1, 0]
    dxx = dx[0:-1]

    plt.xlim(0, 160)
    plt.ylim(0, 160)
    plt.subplots_adjust(wspace=0.05)
    plt.grid(True)
    
    PathSmooting.find_curvature(smoth_way_points)
    
    a = 5