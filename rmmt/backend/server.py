from flask import Flask, request, jsonify
from flask_cors import CORS
import multiprocessing
import tkinter as tk
from tkinter import simpledialog

from astar_modified import AStarPlanner
from dp_planner import DynamicProgrammingPlanner
from PSO_path_smothing import PathSmooting
from helper_data_prepration_planner_random import helper_DPR_obj

from copy import deepcopy
import matplotlib
try:
    matplotlib.use('TkAgg')
except:
    pass

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
import os
import json
import shutil
import open3d as o3d
import cv2
import logging
from typing import List, Tuple, Dict, Any
from matplotlib.patches import Polygon as MplPolygon
from matplotlib.patches import Circle as MplCircle

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# ===================================================================
# VISUALIZATION CONFIGURATION
# ===================================================================
ENABLE_WEB_MAP_VIZ = False      # DISABLED to prevent duplicate plots
ENABLE_MATPLOTLIB_VIZ = True   
VIZ_FLAG = 3 

# ===================================================================
# HELPER FUNCTIONS
# ===================================================================

def startup_logging():
    logger.info("Server starting up...")
    logger.info(f"Registered route: /.well-known/agent.json")
    logger.info(f"Registered route: /tasks/send")
    logger.info(f"Registered route: /upload-pcd")

def latlng_to_meters1(lat, lon, ref_lat, ref_lon):
    m_per_deg_lat = 111132.954 - 559.822 * np.cos(2 * np.radians(ref_lat)) + 1.175 * np.cos(4 * np.radians(ref_lat))
    m_per_deg_lon = 111319.488 * np.cos(np.radians(ref_lat))
    x = (lon - ref_lon) * m_per_deg_lon
    y = (lat - ref_lat) * m_per_deg_lat
    return x, y

def meters_to_latlng1(x, y, ref_lat, ref_lon):
    m_per_deg_lat = 111132.954 - 559.822 * np.cos(2 * np.radians(ref_lat)) + 1.175 * np.cos(4 * np.radians(ref_lat))
    m_per_deg_lon = 111319.488 * np.cos(np.radians(ref_lat))
    lon = x / m_per_deg_lon + ref_lon
    lat = y / m_per_deg_lat + ref_lat
    return lat, lon

def calculate_path_length(path):
    if len(path) < 2:
        return 0.0
    total_length = 0.0
    for i in range(len(path) - 1):
        dx = path[i+1][0] - path[i][0]
        dy = path[i+1][1] - path[i][1]
        total_length += np.sqrt(dx**2 + dy**2)
    return total_length

def check_point_collision(point, obstacles):
    try:
        x, y = float(point[0]), float(point[1])
        for obs in obstacles:
            if obs.get('type') in ['rectangle', 'polygon']:
                try:
                    points = np.array(obs.get('points', []))
                    if len(points) > 0:
                        if helper_DPR_obj.pointInObstacleListRect((x, y), [points]):
                            return True
                except Exception:
                    continue
            elif obs.get('type') == 'circle':
                center = obs.get('center')
                radius = obs.get('radius')
                if center and radius:
                    try:
                        cx, cy = float(center[0]), float(center[1])
                        dist = np.sqrt((x - cx)**2 + (y - cy)**2)
                        if dist <= radius:
                            return True
                    except Exception:
                        continue
        return False
    except Exception:
        return True

def validate_smooth_path_ENHANCED(smooth_path, obstacles, num_samples=300):
    try:
        if len(smooth_path) < 2:
            return True
        sample_indices = np.linspace(0, len(smooth_path) - 1, num_samples, dtype=int)
        for idx in sample_indices:
            point = smooth_path[idx]
            if check_point_collision(point, obstacles):
                return False
        return True
    except Exception as e:
        logger.error(f"Error in enhanced path validation: {e}")
        return False

def validate_control_points_segments(control_points, obstacles, samples_per_segment=50):
    try:
        if len(control_points) < 2:
            return True
        for i in range(len(control_points) - 1):
            p1 = np.array(control_points[i])
            p2 = np.array(control_points[i+1])
            for alpha in np.linspace(0, 1, samples_per_segment):
                test_point = p1 + alpha * (p2 - p1)
                if check_point_collision(test_point, obstacles):
                    return False
        return True
    except Exception as e:
        logger.error(f"Error validating control point segments: {e}")
        return False

def apply_path_smoothing_FIXED(pruned_path, obstacles=None):
    try:
        if len(pruned_path) < 3:
            return np.array(pruned_path), np.array(pruned_path)
        
        obstacles_for_smoothing = obstacles if obstacles is not None else []
        way_points_array = np.array(pruned_path)
        way_points = [way_points_array]
        shortest_path_length = calculate_path_length(pruned_path)
        axes_objects = None
        
        smooth_waypoints, control_waypoints = PathSmooting.smooth_path(
            way_points,
            shortest_path_length,
            axes_objects,
            obstacles_for_smoothing,
        )
        
        # Validation checks
        for i, cp in enumerate(control_waypoints):
            if check_point_collision(cp, obstacles_for_smoothing):
                return np.array(pruned_path), np.array(pruned_path)
        
        if not validate_control_points_segments(control_waypoints, obstacles_for_smoothing):
            return np.array(pruned_path), np.array(pruned_path)
        
        if not validate_smooth_path_ENHANCED(smooth_waypoints, obstacles_for_smoothing):
            return np.array(pruned_path), np.array(pruned_path)
        
        return smooth_waypoints, control_waypoints
    except Exception as e:
        logger.error(f"❌ EXCEPTION in path smoothing: {e}")
        return np.array(pruned_path), np.array(pruned_path)

def process_request_data(data):
    try:
        if not data.get('boundary') or not data['boundary'].get('points') or len(data['boundary']['points']) == 0:
            raise ValueError("Boundary points are missing or invalid")
        if not data.get('start') or not data.get('goal'):
            raise ValueError("Start or goal point is missing")
        ref_lat = data['boundary']['points'][0]['latitude']
        ref_lon = data['boundary']['points'][0]['longitude']
        start_x, start_y = latlng_to_meters1(data['start']['latitude'], data['start']['longitude'], ref_lat, ref_lon)
        goal_x, goal_y = latlng_to_meters1(data['goal']['latitude'], data['goal']['longitude'], ref_lat, ref_lon)
        boundary_points_m = [latlng_to_meters1(p['latitude'], p['longitude'], ref_lat, ref_lon) for p in data['boundary']['points']]
        min_x = min(p[0] for p in boundary_points_m)
        max_x = max(p[0] for p in boundary_points_m)
        min_y = min(p[1] for p in boundary_points_m)
        max_y = max(p[1] for p in boundary_points_m)
        boundary_m = {'bottom_left': (min_x, min_y), 'top_right': (max_x, max_y)}
        obstacles_m = []
        for obs in data.get('obstacles', []):
            if obs['type'] == 'rectangle':
                points_m = [latlng_to_meters1(p['latitude'], p['longitude'], ref_lat, ref_lon) for p in obs['points']]
                obstacles_m.append({'type': 'rectangle', 'points': points_m})
            elif obs['type'] == 'circle':
                center_x, center_y = latlng_to_meters1(obs['center']['latitude'], obs['center']['longitude'], ref_lat, ref_lon)
                obstacles_m.append({'type': 'circle', 'center': (center_x, center_y), 'radius': obs['radius']})
            elif obs['type'] == 'polygon':
                points_m = [latlng_to_meters1(p['latitude'], p['longitude'], ref_lat, ref_lon) for p in obs['points']]
                obstacles_m.append({'type': 'polygon', 'points': points_m})
        return (start_x, start_y), (goal_x, goal_y), obstacles_m, boundary_m, ref_lat, ref_lon
    except (KeyError, TypeError, ValueError) as e:
        raise ValueError(f"Invalid request data: {str(e)}")

# ===================================================================
# VISUALIZATION FUNCTIONS
# ===================================================================

def visualize_web_map_auto(data, save_plot=False):
    """Visualize the map drawn on web interface."""
    try:
        start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(data)
        
        fig, ax = plt.subplots(figsize=(12, 10))
        ax.set_aspect('equal')
        ax.grid(True, alpha=0.3, linestyle='--', linewidth=0.5)
        
        bl = boundary['bottom_left']
        tr = boundary['top_right']
        width = tr[0] - bl[0]
        height = tr[1] - bl[1]
        
        boundary_rect = patches.Rectangle(
            bl, width, height,
            linewidth=3, edgecolor='green', facecolor='lightgreen',
            alpha=0.15, linestyle='--', label='Workspace Boundary'
        )
        ax.add_patch(boundary_rect)
        
        padding = max(width, height) * 0.1
        ax.set_xlim(bl[0] - padding, tr[0] + padding)
        ax.set_ylim(bl[1] - padding, tr[1] + padding)
        
        for i, obs in enumerate(obstacles):
            if obs['type'] in ['rectangle', 'polygon']:
                points = np.array(obs['points'])
                poly = MplPolygon(
                    points, closed=True, edgecolor='red', facecolor='red',
                    alpha=0.5, linewidth=2.5
                )
                ax.add_patch(poly)
            elif obs['type'] == 'circle':
                circle = MplCircle(
                    obs['center'], obs['radius'],
                    edgecolor='red', facecolor='red',
                    alpha=0.5, linewidth=2.5
                )
                ax.add_patch(circle)
        
        if start:
            ax.plot(start[0], start[1], 'o', color='green', markersize=20, label='Start')
        if goal:
            ax.plot(goal[0], goal[1], 's', color='red', markersize=20, label='Goal')
        
        ax.legend(loc='upper right')
        ax.set_title(f"Web Map: {data.get('name', 'Unnamed')}")
        plt.show()
        
    except Exception as e:
        print(f"❌ Failed to visualize web map: {e}")

def ask_user_for_viz_flag_popup(initial_val=3):
    """
    Opens a robust pop-up dialog to ask for the visualization flag.
    Includes Option 5 for DP Grid.
    """
    try:
        # Create a hidden root window
        root = tk.Tk()
        root.withdraw() 
        root.attributes('-topmost', True) # Force it to appear on top
        
        # Define prompt text
        prompt = (
            "Select Visualization Mode:\n\n"
            "1: A* path only\n"
            "2: Smooth pathing\n"
            "3: Both paths \n"
            "4: Obstacle inflation\n"
            "5: DP Grid Decomposition"
        )
        
        # Show dialog
        flag = simpledialog.askinteger(
            "Visualization Settings", 
            prompt,
            parent=root,
            minvalue=1, 
            maxvalue=5,
            initialvalue=initial_val
        )
        
        root.destroy()
        
        if flag is None:
            return initial_val
            
        return flag

    except Exception as e:
        print(f"❌ Popup failed: {e}. Defaulting to {initial_val}.")
        return initial_val

def visualize_result_in_matplotlib(path_meters, pruned_path_meters, smooth_path_meters, 
                                 control_path_meters, obstacles_meters, boundary_meters, 
                                 start_meters, goal_meters, original_obstacles_meters=None, 
                                 flag=3, grid_data=None):
    try:
        from visualize_planning import visualize_from_server_response
        
        response_data = {
            'path': path_meters,
            'pruned_path': pruned_path_meters,
            'smooth_path': smooth_path_meters,
            'control_path': control_path_meters
        }
        
        viz = visualize_from_server_response(
            response_data=response_data,
            obstacles=obstacles_meters,
            boundary=boundary_meters,
            start=start_meters,
            goal=goal_meters,
            flag=flag,
            show_inflation=(flag == 4),
            original_obstacles=original_obstacles_meters,
            grid_data=grid_data
        )
        viz.show()
    except Exception as e:
        print(f"Failed to show matplotlib visualization: {e}")

# ===================================================================
# VISUALIZATION WORKER FUNCTION (Runs in separate process)
# ===================================================================
def visualization_worker(params_data, path, pruned_path, smooth_waypoints, 
                         control_waypoints, inflated_obstacles, boundary, 
                         start, goal, original_obstacles, 
                         enable_web_viz, enable_matplotlib_viz, default_flag,
                         grid_data=None, skip_flag_popup=False):
    """
    This runs in a completely separate process.
    Handles grid_data argument for DP visualization.
    
    Args:
        skip_flag_popup: If True, uses default_flag without asking user
    """
    try:
        # Show web map first if enabled
        if enable_web_viz:
            visualize_web_map_auto(params_data, save_plot=True)
        
        # Ask for flag using POPUP (ONLY if not skipping)
        user_chosen_flag = default_flag
        if enable_matplotlib_viz and not skip_flag_popup:
            user_chosen_flag = ask_user_for_viz_flag_popup(initial_val=default_flag)
        
        # --- IF USER CHOSE FLAG 5 (DP GRID), COMPUTE IT NOW ---
        computed_grid_data = grid_data
        if user_chosen_flag == 5 and grid_data is None:
            logger.info("🔧 Flag 5 selected: Computing DP Grid decomposition...")
            try:
                # Extract map data from params
                start_pt, goal_pt, obstacles_m, boundary_m, ref_lat, ref_lon = process_request_data(params_data)
                
                # Use temp directory for on-demand decomposition
                temp_decomp_dir = "decomposition_temp_viz"
                os.makedirs(temp_decomp_dir, exist_ok=True)
                
                # Create DP planner to get grid
                dp_planner = DynamicProgrammingPlanner(
                    start=start_pt, 
                    goal=goal_pt, 
                    obstacles=obstacles_m, 
                    boundary=boundary_m,
                    decomposition_dir=temp_decomp_dir
                )
                computed_grid_data = dp_planner.get_grid_data()
                logger.info(f"✅ Grid computed: {computed_grid_data['total_cells']} cells")
                
            except Exception as e:
                logger.error(f"❌ Failed to compute DP grid: {e}")
                computed_grid_data = None
        
        # Show result
        if enable_matplotlib_viz:
            visualize_result_in_matplotlib(
                path_meters=path,
                pruned_path_meters=pruned_path,
                smooth_path_meters=smooth_waypoints,
                control_path_meters=control_waypoints,
                obstacles_meters=inflated_obstacles,
                boundary_meters=boundary,
                start_meters=start,
                goal_meters=goal,
                original_obstacles_meters=original_obstacles,
                flag=user_chosen_flag,
                grid_data=computed_grid_data
            )
            
        print("\n✅ Visualization process finished.")
    except Exception as e:
        print(f"❌ Error in visualization worker: {e}")

# ===================================================================
# ROUTES
# ===================================================================

@app.route("/.well-known/agent.json", methods=["GET"])
def agent_card():
    logger.info("Handling request for /.well-known/agent.json")
    return jsonify({
        "name": "PathPlannerAgent",
        "description": "Handles path planning, map management, and PCD processing for navigation.",
        "url": "http://localhost:5000", 
        "version": "1.0",
        "capabilities": {"streaming": False, "pushNotifications": False}
    })

@app.route("/tasks/send", methods=["POST"])
def handle_task():
    try:
        task = request.get_json()
        task_id = task.get("id")
        parts = task["message"]["parts"]
        if not parts or len(parts) < 1:
            return jsonify({"error": "No message parts provided"}), 400
        operation = parts[0]["text"]
        params = parts[1]["text"] if len(parts) > 1 else "{}"
        params_data = json.loads(params)
    except (KeyError, IndexError, TypeError, ValueError) as e:
        return jsonify({"error": f"Invalid task format: {str(e)}"}), 400

    response_data = {}
    status_code = 200

    try:
        if operation == "plan-path":
            # A* PLANNER (WITH SMOOTHING)
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            inflated_obstacles = helper_DPR_obj.strching_obstacles(obstacles)
            
            planner = AStarPlanner(start=start, goal=goal, obstacles=inflated_obstacles, boundary=boundary)
            path, pruned_path = planner.planning()
            
            if not path:
                return jsonify({"error": "No path found"}), 404
            
            enable_smoothing = params_data.get("enable_smoothing", True)
            smooth_waypoints, control_waypoints = np.array(pruned_path), np.array(pruned_path)
            
            if enable_smoothing and len(pruned_path) >= 3:
                smooth_waypoints, control_waypoints = apply_path_smoothing_FIXED(
                    pruned_path, inflated_obstacles
                )
            
            def to_ll_custom(pts):
                return [{'latitude': lat, 'longitude': lon} for lat, lon in [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in pts]]

            resp_data = {
                "path": to_ll_custom(path),
                "pruned_path": to_ll_custom(pruned_path),
                "smooth_path": to_ll_custom(smooth_waypoints),
                "control_path": to_ll_custom(control_waypoints)
            }
            
            if ENABLE_MATPLOTLIB_VIZ:
                # Default Flag 3 for A* (Shows popup)
                p = multiprocessing.Process(target=visualization_worker, 
                    args=(params_data, path, pruned_path, smooth_waypoints, control_waypoints, 
                          inflated_obstacles, boundary, start, goal, obstacles, 
                          ENABLE_WEB_MAP_VIZ, ENABLE_MATPLOTLIB_VIZ, 3, None, False))
                p.start()

            return jsonify({"id": task_id, "status": {"state": "completed"}, 
                          "messages": [task["message"], {"role": "agent", "parts": [{"text": json.dumps(resp_data)}]}]})

        elif operation == "plan-path-dp":
            # DP PLANNER (GRID ONLY - NO SMOOTHING)
            name = params_data.get("name", "temp")
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            
            decomposition_dir = os.path.join("saved_maps", name, "decomposition") if name != "temp" else "decomposition_temp"
            os.makedirs(decomposition_dir, exist_ok=True)
            
            planner = DynamicProgrammingPlanner(start=start, goal=goal, obstacles=obstacles, boundary=boundary, decomposition_dir=decomposition_dir)
            path, pruned_path = planner.planning()
            
            # 1. Get Grid Data (CRITICAL for Option 5)
            grid_data = planner.get_grid_data()
            
            if not path:
                return jsonify({"error": "No path found"}), 404
                
            def to_ll_custom(pts):
                return [{'latitude': lat, 'longitude': lon} for lat, lon in [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in pts]]

            resp_data = {"path": to_ll_custom(path), "pruned_path": to_ll_custom(pruned_path)}
            
            if ENABLE_MATPLOTLIB_VIZ:
                # Default Flag 5 for DP. Smoothing arrays are empty.
                # skip_flag_popup=False (YOU WANT TO TYPE 5 YOURSELF)
                p = multiprocessing.Process(target=visualization_worker, 
                    args=(params_data, path, pruned_path, [], [], 
                          obstacles, boundary, start, goal, obstacles, 
                          False, True, 5, grid_data, False)) 
                p.start()
            
            return jsonify({"id": task_id, "status": {"state": "completed"}, 
                          "messages": [task["message"], {"role": "agent", "parts": [{"text": json.dumps(resp_data)}]}]})

        elif operation == "get-grid":
            name = params_data.get("name", "temp")
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            decomposition_dir = os.path.join("saved_maps", name, "decomposition") if name != "temp" else "decomposition_temp"
            if not os.path.exists(decomposition_dir):
                return jsonify({"error": "No decomposition found."}), 404
            planner = DynamicProgrammingPlanner(start=start, goal=goal, obstacles=obstacles, boundary=boundary, decomposition_dir=decomposition_dir)
            grid_data = planner.get_grid_data()
            cells_latlng = []
            for cell in grid_data['cells']:
                bounds = cell['bounds']
                cell_latlng = {
                    'cell_number': cell['cell_number'],
                    'center': {
                        'latitude': meters_to_latlng1(cell['center'][0], cell['center'][1], ref_lat, ref_lon)[0],
                        'longitude': meters_to_latlng1(cell['center'][0], cell['center'][1], ref_lat, ref_lon)[1]
                    },
                    'bounds': {
                        'min': {
                            'latitude': meters_to_latlng1(bounds['min_x'], bounds['min_y'], ref_lat, ref_lon)[0],
                            'longitude': meters_to_latlng1(bounds['min_x'], bounds['min_y'], ref_lat, ref_lon)[1]
                        },
                        'max': {
                            'latitude': meters_to_latlng1(bounds['max_x'], bounds['max_y'], ref_lat, ref_lon)[0],
                            'longitude': meters_to_latlng1(bounds['max_x'], bounds['max_y'], ref_lat, ref_lon)[1]
                        }
                    }
                }
                cells_latlng.append(cell_latlng)
            response_data = {'cells': cells_latlng, 'total_cells': grid_data['total_cells']}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "save-map":
            name = params_data.get("name")
            if not name:
                return jsonify({"error": "Map name is required"}), 400
            map_dir = os.path.join("saved_maps", name)
            os.makedirs(map_dir, exist_ok=True)
            json_path = os.path.join(map_dir, f"{name}.json")
            with open(json_path, "w") as f:
                json.dump(params_data, f)
            dummy_start = (0, 0)
            dummy_goal = (1, 1)
            _, _, obstacles, boundary, _, _ = process_request_data(params_data)
            decomposition_dir = os.path.join(map_dir, "decomposition")
            os.makedirs(decomposition_dir, exist_ok=True)
            try:
                DynamicProgrammingPlanner(dummy_start, dummy_goal, obstacles, boundary, decomposition_dir=decomposition_dir)
            except: pass
            response_data = {"success": True}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "load-map":
            name = params_data.get("name")
            if not name:
                return jsonify({"error": "Map name is required"}), 400
            json_path = os.path.join("saved_maps", name, f"{name}.json")
            if not os.path.exists(json_path):
                return jsonify({"error": "Map not found"}), 404
            with open(json_path, "r") as f:
                response_data = json.load(f)
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "list-maps":
            if not os.path.exists("saved_maps"):
                response_data = {"maps": []}
            else:
                maps = [d for d in os.listdir("saved_maps") if os.path.isdir(os.path.join("saved_maps", d))]
                response_data = {"maps": maps}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "delete-map":
            name = params_data.get("name")
            if not name:
                return jsonify({"error": "Map name is required"}), 400
            map_dir = os.path.join("saved_maps", name)
            if not os.path.exists(map_dir):
                return jsonify({"error": "Map not found"}), 404
            shutil.rmtree(map_dir)
            response_data = {"success": True}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        else:
            return jsonify({"error": f"Unknown operation: {operation}"}), 400

    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Error processing {operation}: {e}", exc_info=True)
        return jsonify({"error": f"Error during {operation}"}), 500

@app.route("/upload-pcd", methods=["POST"])
def upload_pcd():
    try:
        if "pcd_file" not in request.files:
            return jsonify({"error": "No PCD file provided"}), 400
        file = request.files["pcd_file"]
        name = request.form.get("name")
        ref_lat = float(request.form.get("ref_lat"))
        ref_lon = float(request.form.get("ref_lon"))
        if not name:
            return jsonify({"error": "Map name is required"}), 400
        map_dir = os.path.join("saved_maps", name)
        os.makedirs(map_dir, exist_ok=True)
        pcd_path = os.path.join(map_dir, "map.pcd")
        file.save(pcd_path)
        pcd = o3d.io.read_point_cloud(pcd_path)
        if pcd.is_empty():
            raise ValueError("PCD file is empty or invalid")
        pcd = pcd.voxel_down_sample(voxel_size=0.005)
        points_3d = np.asarray(pcd.points)
        if points_3d.size == 0:
            raise ValueError("No points after downsampling")
        plane_model, inliers = pcd.segment_plane(distance_threshold=0.01, ransac_n=3, num_iterations=1000)
        outlier_cloud = pcd.select_by_index(inliers, invert=True)
        points_3d_filtered = np.asarray(outlier_cloud.points)
        if points_3d_filtered.size == 0:
            points_2d = np.array([]).reshape(0, 2)
        else:
            z_range = (0.1, 2.0)
            filtered_points = points_3d_filtered[(points_3d_filtered[:, 2] > z_range[0]) & (points_3d_filtered[:, 2] <= z_range[1])]
            points_2d = filtered_points[:, :2] if filtered_points.size > 0 else np.array([]).reshape(0, 2)
        obstacles: List[Dict[str, Any]] = []
        all_points_2d = points_3d[:, :2]
        if points_2d.size > 0:
            min_x_grid, min_y_grid = points_2d.min(axis=0)
            max_x_grid, max_y_grid = points_2d.max(axis=0)
            width = int((max_x_grid - min_x_grid) / 0.005) + 1
            height = int((max_y_grid - min_y_grid) / 0.005) + 1
            if width > 0 and height > 0:
                grid = np.zeros((height, width), dtype=np.uint8)
                for pt in points_2d:
                    x_idx = int((pt[0] - min_x_grid) / 0.005)
                    y_idx = int((pt[1] - min_y_grid) / 0.005)
                    if 0 <= x_idx < width and 0 <= y_idx < height:
                        grid[y_idx, x_idx] = 255
                num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(grid, connectivity=8)
                for i in range(1, num_labels):
                    area = stats[i, cv2.CC_STAT_AREA]
                    if area > 10:
                        x = stats[i, cv2.CC_STAT_LEFT] * 0.005 + min_x_grid
                        y = stats[i, cv2.CC_STAT_TOP] * 0.005 + min_y_grid
                        w = stats[i, cv2.CC_STAT_WIDTH] * 0.005
                        h = stats[i, cv2.CC_STAT_HEIGHT] * 0.005
                        p1 = meters_to_latlng1(x, y, ref_lat, ref_lon)
                        p2 = meters_to_latlng1(x + w, y, ref_lat, ref_lon)
                        p3 = meters_to_latlng1(x + w, y + h, ref_lat, ref_lon)
                        p4 = meters_to_latlng1(x, y + h, ref_lat, ref_lon)
                        obstacles.append({
                            "type": "rectangle",
                            "points": [
                                {"latitude": p1[0], "longitude": p1[1]},
                                {"latitude": p2[0], "longitude": p2[1]},
                                {"latitude": p3[0], "longitude": p3[1]},
                                {"latitude": p4[0], "longitude": p4[1]}
                            ]
                        })
        min_x_m, min_y_m = all_points_2d.min(axis=0)
        max_x_m, max_y_m = all_points_2d.max(axis=0)
        bl = meters_to_latlng1(min_x_m, min_y_m, ref_lat, ref_lon)
        tr = meters_to_latlng1(max_x_m, max_y_m, ref_lat, ref_lon)
        boundary = {"points": [{"latitude": bl[0], "longitude": bl[1]}, {"latitude": tr[0], "longitude": tr[1]}]}
        map_data = {"name": name, "boundary": boundary, "obstacles": obstacles, "ref_lat": ref_lat, "ref_lon": ref_lon}
        json_path = os.path.join(map_dir, f"{name}.json")
        with open(json_path, "w") as f:
            json.dump(map_data, f)
        try:
            dummy_start_m = (0, 0)
            dummy_goal_m = (1, 1)
            _, _, obstacles_processed, boundary_processed, _, _ = process_request_data(map_data)
            decomposition_dir = os.path.join(map_dir, "decomposition")
            os.makedirs(decomposition_dir, exist_ok=True)
            DynamicProgrammingPlanner(dummy_start_m, dummy_goal_m, obstacles_processed, boundary_processed, decomposition_dir=decomposition_dir)
        except: pass
        return jsonify({
            "id": request.form.get("task_id", "unknown"),
            "status": {"state": "completed"},
            "messages": [
                {"role": "user", "parts": [{"text": "upload-pcd"}]},
                {"role": "agent", "parts": [{"text": json.dumps({"boundary": boundary, "obstacles": obstacles})}]}
            ]
        })
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        return jsonify({"error": "PCD processing error"}), 500

if __name__ == "__main__":
    startup_logging()
    app.run(host="0.0.0.0", port=5000, debug=True)