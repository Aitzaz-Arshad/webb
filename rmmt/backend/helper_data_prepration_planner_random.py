import numpy as np
from numpy import random
import cv2
import csv
from io import StringIO
from glob import glob
from os import path
from obstacle_list import *
from pathlib import Path
from copy import copy, deepcopy
from scipy.signal import savgol_filter


# FIX: Imports AStarPlanner from the correct file name
from astar_modified import *
from scipy.interpolate import CubicSpline


# The `helper_DPR` class in Python provides various methods for path planning and obstacle
# manipulation, including functions for calculating path lengths, smoothing paths, and checking point
# collisions.
class helper_DPR:

    def __init__(self):
        pass

    def get_files_in(self, folder, pattern="*.png"):
        return glob(path.join(self, folder, pattern))

    def pointInRect(self, point, rect):
        x1, y1, w, h = rect
        x2, y2 = x1 + w, y1 + h
        x, y = point
        if x1 <= x and x <= x2:
            if y1 <= y and y <= y2:
                return True
        return False

    def pointInObstacleListRect(self, point, obstacleList_rect):
        colision = 0

        for rect in obstacleList_rect:

            w = rect[2, 0] - rect[0, 0]
            h = rect[2, 1] - rect[0, 1]
            reactng = [rect[0, 0], rect[0, 1], w, h]

            if self.pointInRect(point, reactng):
                colision = colision + 1
                return True

        return False

    def _inflate_single_obstacle(self, obs_points_array, margin):
        """
        Inflates a single obstacle polygon's coordinate array by the given margin (C-Space method).
        """
        obs = obs_points_array.astype(np.float64) 
        
        max_x = np.max(obs[:, 0])
        min_x = np.min(obs[:, 0])
        max_y = np.max(obs[:, 1])
        min_y = np.min(obs[:, 1])
        mid_x = (max_x + min_x) / 2
        mid_y = (max_y + min_y) / 2
        
        # Expand based on the midpoint projection
        obs[:, 0][obs[:, 0] <= mid_x] -= margin
        obs[:, 1][obs[:, 1] <= mid_y] -= margin
        obs[:, 0][obs[:, 0] > mid_x] += margin
        obs[:, 1][obs[:, 1] > mid_y] += margin
        
        # Convert back to integer for compatibility with A*
        return np.round(obs).astype(np.int64)

    def strching_obstacles(self, obts):
        """
        CRITICALLY CORRECTED: Iterates through obstacle DICTIONARIES (obts) and inflates the
        corresponding 'points' array for each one.
        """
        margin = ROBOT_BIGGEST_DIMENTION # Use the defined safety constant
        
        inflated_obstacles_list = []

        # obts is a list of dictionaries (from server input)
        for obs_dict in obts:
            # We must use a a copy to avoid permanent mutation
            new_obs_dict = deepcopy(obs_dict)
            
            # CRASH FIX: Check the type and ensure 'points' exists before processing
            if new_obs_dict.get('type') in ['rectangle', 'polygon'] and new_obs_dict.get('points') is not None and len(new_obs_dict['points']) > 0:
                
                # 1. Convert the list of tuples/lists back to a NumPy array for math
                points_array = np.array(new_obs_dict['points'])
                
                # 2. Apply the core inflation logic to the points array
                inflated_points = self._inflate_single_obstacle(points_array, margin)
                
                # 3. Update the dictionary with the new inflated points
                new_obs_dict['points'] = inflated_points
                
            inflated_obstacles_list.append(new_obs_dict)
            
        return inflated_obstacles_list

    def shortest_pathand_length(self, startPoint, endPoint, obts):
        """
        Calculates the shortest path and its length using A*.
        """
       
        # FIX: Correctly calls AStarPlanner with boundary limits [0, 160, 0, 160]
        a_star = AStarPlanner(startPoint, endPoint, obts, [0, 160, 0, 160])
        
        way_points = a_star.planning()  # path[0] for not prune and path[1] for prune
        p_path = np.array(way_points[1])
        path = np.array(way_points[0])
        l = self.lengthPath(p_path[:, 0], p_path[:, 1])
        return [p_path, path, l]

    def smoothPathLength(self, wayPoints):
        """
        CRITICAL FIX: Uses cubic spline interpolation to smooth a path, 
        safely filtering points to ensure strictly increasing X-coordinates.
        """
        
        # 1. Filter out numerically identical points
        x = wayPoints[:, 0].copy()
        y = wayPoints[:, 1].copy()
        
        # Identify indices where the X coordinate changes significantly (tolerance 1e-4)
        is_unique_x = np.concatenate(([True], np.abs(np.diff(x)) > 1e-4))
        
        # Filter the points array
        filtered_x = x[is_unique_x].tolist()
        filtered_y = y[is_unique_x].tolist()
        
        # Check if we have enough points left (min 2 points for a spline)
        if len(filtered_x) < 2:
            # If filtering failed, return the original path data
            return [wayPoints, self.lengthPath(x, y)] 

        # 2. Perform parametric Cubic Spline on filtered points (use a monotonic parameter 't')
        try:
            # Use cumulative distance as a monotonic parameter to avoid requiring x to be
            # strictly increasing. This also handles vertical segments and non-monotonic x.
            diffs = np.sqrt(np.diff(filtered_x) ** 2 + np.diff(filtered_y) ** 2)
            if diffs.size == 0:
                t = np.array([0.0, 1.0])
            else:
                t = np.concatenate(([0.0], np.cumsum(diffs)))

            # Normalize parameter to [0, 1]
            if t[-1] == 0:
                t_norm = np.linspace(0, 1, len(t))
            else:
                t_norm = t / t[-1]

            cs_x = CubicSpline(t_norm, filtered_x, bc_type="natural")
            cs_y = CubicSpline(t_norm, filtered_y, bc_type="natural")

            t_new = np.linspace(0.0, 1.0, 1000)
            x_new = cs_x(t_new)
            y_new = cs_y(t_new)

            return [np.array([x_new, y_new]).transpose(), self.lengthPath(x_new, y_new)]
        except Exception as e:
            # Final safety fallback
            print(f"CRITICAL ERROR in smoothPathLength: {e}")
            return [wayPoints, self.lengthPath(x, y)]


    def smoothPathLengthWithSteps(self, waypoints):
        """
        Calculates the length of a smooth path passing through given waypoints with steps.
        """
        l = len(waypoints)
        lengthPath = 0
        swaypoints_new = []

        for i in range(0, l - 2, 2):
            ws = []

            if i + 4 == l:
                ws = waypoints[i : i + 4, :]
            else:
                ws = waypoints[i : i + 3, :]

            # The smoothPathLength function (above) will now handle stability checks
            ws = self.XstriclyIncreasingOrder(ws) 
            ws = ws[0]
            
            try:
                # Perform the same filtering here for safety inside the loop
                x = ws[:, 0].copy()
                y = ws[:, 1].copy()
                is_unique_x = np.concatenate(([True], np.abs(np.diff(x)) > 1e-4))
                filtered_x = x[is_unique_x].tolist()
                filtered_y = y[is_unique_x].tolist()

                if len(filtered_x) < 2:
                    continue 
                # Parametric cubic spline using cumulative distance parameter
                diffs = np.sqrt(np.diff(filtered_x) ** 2 + np.diff(filtered_y) ** 2)
                if diffs.size == 0:
                    t = np.array([0.0, 1.0])
                else:
                    t = np.concatenate(([0.0], np.cumsum(diffs)))

                if t[-1] == 0:
                    t_norm = np.linspace(0, 1, len(t))
                else:
                    t_norm = t / t[-1]

                cs_x = CubicSpline(t_norm, filtered_x, bc_type="natural")
                cs_y = CubicSpline(t_norm, filtered_y, bc_type="natural")

                t_new = np.linspace(0.0, 1.0, 100)
                x_new = cs_x(t_new)
                y_new = cs_y(t_new)
                
                if i == 0:
                    swaypoints_new = deepcopy(np.array([x_new, y_new]).transpose())
                    swaypoints_new = np.delete(swaypoints_new, (-1), axis=0)
                    lengthPath = lengthPath + self.lengthPath(x_new, y_new)
                else:
                    swaypoints_new = np.concatenate(
                        (swaypoints_new, np.array([x_new, y_new]).transpose())
                    )
                    lengthPath = lengthPath + self.lengthPath(x_new, y_new)
                    swaypoints_new = np.delete(swaypoints_new, (-1), axis=0)
                    
            except Exception as e:
                # Log segment failure but continue the overall path generation
                print(f"WARNING: Segment smoothing failed: {e}")
                continue


        # Final verification and return
        if len(swaypoints_new) == 0:
            return [waypoints, self.lengthPath(waypoints[:, 0], waypoints[:, 1])]
            
        return [swaypoints_new, self.lengthPath(swaypoints_new[:, 0], swaypoints_new[:, 1])]


    def lengthPath(self, x, y):
        """
        Calculates the total length of a path defined by a series of x and y coordinates.
        """
        dist_array = (x[:-1] - x[1:]) ** 2 + (y[:-1] - y[1:]) ** 2

        np.sum(np.sqrt(dist_array))

        return np.sum(np.sqrt(dist_array))

    def CostFunction(self, smoothPathLength, shortest_path_length):
        """
        Calculates the absolute difference between smoothPathLength and shortest_path_length.
        """

        return abs(smoothPathLength - shortest_path_length)

    def XstriclyIncreasingOrder(self, waypoints):
        """
        Handles overall flip and ensures subsequent methods receive the data structure they expect.
        """
        flip = 0
        
        # 1. Handle overall flip if goal is behind start
        if waypoints[-1][0] < waypoints[0][0]:
            waypoints = np.flip(waypoints, axis=0)
            flip = 1

        # The point nudging logic is removed from here for stability.
        
        return [waypoints, flip]

    def boundryCondition(self, waypoints):
        """
        Calculates the boundary conditions for a set of waypoints.
        """

        minX = np.minimum(waypoints[0, 0], waypoints[1, 0])
        maxX = np.maximum(waypoints[0, 0], waypoints[1, 0])
        minY = np.minimum(waypoints[0, 1], waypoints[1, 1])
        maxY = np.maximum(waypoints[0, 1], waypoints[1, 1])

        boundryCondition = [minX, maxX, minY, maxY]
        nVar = len(waypoints[0, :])
        return [boundryCondition, nVar]

    def interpolate_middle_points(self, arr):

        interpolated_arr = []
        for i in range(len(arr) - 1):
            mid_point = (arr[i] + arr[i + 1]) / 2

            interpolated_arr.append(arr[i])
            interpolated_arr.append(mid_point)
        interpolated_arr.append(arr[-1])
        return np.array(interpolated_arr)

    def interpolate_waypoints(self, way_points):
        x = way_points[:, 0]
        y = way_points[:, 1]
        inter_polated_x = self.interpolate_middle_points(x)
        inter_polated_y = self.interpolate_middle_points(y)
        inter_polated_waypoints = np.vstack((inter_polated_x, inter_polated_y))
        return inter_polated_waypoints.T

    def interpolate_middle_points_reduce(self, arr):

        interpolated_arr = []
        for i in range(0, (len(arr) - 1), 2):
            mid_point = (arr[i] + arr[i + 1]) / 2

            interpolated_arr.append(arr[i])

            interpolated_arr.append(mid_point)

            interpolated_arr.append(arr[-1])
        return np.array(interpolated_arr)

    def find_curvature_discontinuties(self, smoth_way_points):
        t = np.linspace(0, 160, 1000)
        x = smoth_way_points[:, 0]
        y = smoth_way_points[:, 1]

        # Create cubic splines for x(t) and y(t)
        cs_x = CubicSpline(t, x)
        cs_y = CubicSpline(t, y)

        # Compute the first and second derivatives
        dx = cs_x(t, 1)
        dy = cs_y(t, 1)
        d2x = cs_x(t, 2)
        d2y = cs_y(t, 2)

        # Calculate the curvature using the formula
        curvature = np.abs(dx * d2y - dy * d2x) / (dx**2 + dy**2) ** (3 / 2)

        d_curvature = np.diff(curvature)
        positive_edges = (d_curvature[:-1] < 0) & (d_curvature[1:] >= 0)
        negative_edges = (d_curvature[:-1] >= 0) & (d_curvature[1:] < 0)

        # Count the edges
        num_positive_edges = np.sum(positive_edges)
        num_negative_edges = np.sum(negative_edges)
        total_edges = num_positive_edges + num_negative_edges
        return total_edges

# CRITICAL FIX: Create the globally accessible instance here
helper_DPR_obj = helper_DPR()