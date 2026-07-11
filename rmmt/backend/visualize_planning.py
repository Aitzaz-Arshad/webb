"""
Path Planning Visualization Module
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
from matplotlib.patches import Polygon as MplPolygon
from matplotlib.patches import Circle as MplCircle

class PathPlanningVisualizer:
    
    SHOW_ASTAR = 1
    SHOW_SMOOTH = 2
    SHOW_BOTH = 3
    SHOW_OBSTACLES = 4
    SHOW_DP_GRID = 5
    
    def __init__(self, figsize=(14, 10)):
        self.fig, self.ax = plt.subplots(figsize=figsize)
        self.ax.set_aspect('equal')
        self.ax.grid(True, alpha=0.3, linestyle='--', linewidth=0.5)
        self.ax.set_xlabel('X (meters)', fontsize=12)
        self.ax.set_ylabel('Y (meters)', fontsize=12)
        self.ax.set_title('Path Planning Visualization', fontsize=14, fontweight='bold')
        
    def plot_boundary(self, boundary_dict):
        bl = boundary_dict['bottom_left']
        tr = boundary_dict['top_right']
        width = tr[0] - bl[0]
        height = tr[1] - bl[1]
        
        boundary_rect = patches.Rectangle(
            bl, width, height,
            linewidth=2, edgecolor='green', facecolor='none',
            linestyle='--', label='Workspace Boundary'
        )
        self.ax.add_patch(boundary_rect)
        padding = max(width, height) * 0.05
        self.ax.set_xlim(bl[0] - padding, tr[0] + padding)
        self.ax.set_ylim(bl[1] - padding, tr[1] + padding)
        
    def plot_obstacles(self, obstacles, show_inflation=False, original_obstacles=None):
        if show_inflation and original_obstacles:
            for obs in original_obstacles:
                self._plot_single_obstacle(obs, color='lightcoral', alpha=0.3, label='Original Obstacle', linestyle=':')
        
        for i, obs in enumerate(obstacles):
            label = 'Inflated Obstacle' if (show_inflation and i == 0) else None
            if not show_inflation: label = 'Obstacle' if i == 0 else None
            color = 'red' if not show_inflation else 'darkred'
            self._plot_single_obstacle(obs, color=color, alpha=0.5, label=label)
    
    def _plot_single_obstacle(self, obs, color='red', alpha=0.5, label=None, linestyle='-'):
        if obs.get('type') in ['rectangle', 'polygon']:
            points = np.array(obs.get('points', []))
            if len(points) > 0:
                poly = MplPolygon(points, closed=True, edgecolor=color, facecolor=color, alpha=alpha, linewidth=2, linestyle=linestyle, label=label)
                self.ax.add_patch(poly)
        elif obs.get('type') == 'circle':
            center = obs.get('center')
            radius = obs.get('radius')
            if center is not None and radius:
                circle = MplCircle(center, radius, edgecolor=color, facecolor=color, alpha=alpha, linewidth=2, linestyle=linestyle, label=label)
                self.ax.add_patch(circle)

    def plot_dp_grid(self, grid_data):
        """Plots the colored grid cells for Dynamic Programming."""
        if not grid_data or 'cells' not in grid_data:
            return

        print(f"Drawing {len(grid_data['cells'])} grid cells...")
        colors = ['#90EE90', '#D8BFD8', '#FFB6C1', '#87CEFA', '#F0E68C', '#FFE4B5'] 
        
        for i, cell in enumerate(grid_data['cells']):
            try:
                b = cell['bounds']
                x, y = b['min_x'], b['min_y']
                w, h = b['max_x'] - b['min_x'], b['max_y'] - b['min_y']
                
                # ZORDER 1: Background
                rect = patches.Rectangle((x, y), w, h, linewidth=1.5, edgecolor='gray', 
                                         facecolor=colors[i % len(colors)], alpha=0.5, zorder=1)
                self.ax.add_patch(rect)
                
                # Cell Number
                cx, cy = x + w/2, y + h/2
                self.ax.plot(cx, cy, 'o', color='white', markersize=14, zorder=2)
                self.ax.text(cx, cy, str(cell.get('cell_number','')), fontsize=9, 
                             ha='center', va='center', color='black', fontweight='bold', zorder=3)
            except: pass
        
        self.ax.add_patch(patches.Rectangle((0,0), 0,0, facecolor='lightgreen', alpha=0.5, label='Decomposition Cell'))

    def plot_start_goal(self, start, goal):
        self.ax.plot(start[0], start[1], 'o', color='green', markersize=15, label='Start', markeredgecolor='black', zorder=20)
        self.ax.plot(goal[0], goal[1], 's', color='red', markersize=15, label='Goal', markeredgecolor='black', zorder=20)
    
    def plot_astar_path(self, path_points, pruned_path_points=None):
        """Plots the main path line."""
        if len(path_points) > 0:
            path_array = np.array(path_points)
            # ZORDER 10: On top of grid (z=1) but below markers
            self.ax.plot(path_array[:, 0], path_array[:, 1], '-', color='blue', linewidth=2.5, label='Path', zorder=10)
        
        if pruned_path_points is not None and len(pruned_path_points) > 0:
            pruned_array = np.array(pruned_path_points)
            self.ax.plot(pruned_array[:, 0], pruned_array[:, 1], 'o', color='blue', markersize=6, zorder=11)
    
    def plot_smooth_path(self, smooth_points, control_points=None):
        if len(smooth_points) > 0:
            smooth_array = np.array(smooth_points)
            self.ax.plot(smooth_array[:, 0], smooth_array[:, 1], '-', color='cyan', linewidth=2.5, label='Smooth Path', zorder=15)
        
        if control_points is not None and len(control_points) > 0:
            control_array = np.array(control_points)
            # Control points as Diamonds ('D') on top
            self.ax.plot(control_array[:, 0], control_array[:, 1], 'D', color='orange', markersize=8, 
                        markeredgecolor='black', label='Control Points', zorder=20)

    def add_legend(self):
        handles, labels = self.ax.get_legend_handles_labels()
        by_label = dict(zip(labels, handles))
        self.ax.legend(by_label.values(), by_label.keys(), loc='upper right', fontsize=10)
    
    def show(self):
        plt.tight_layout()
        plt.show()

def visualize_from_server_response(response_data, obstacles, boundary, start, goal, 
                                   flag=3, show_inflation=False, original_obstacles=None,
                                   grid_data=None):
    
    viz = PathPlanningVisualizer(figsize=(14, 10))
    viz.plot_boundary(boundary)
    
    # ========================================================
    # MODE 5: DP GRID DECOMPOSITION + PATH (Like Reference Image)
    # ========================================================
    if flag == 5:
        # 1. Grid (Background)
        if grid_data:
            viz.plot_dp_grid(grid_data)
        
        # 2. Obstacles
        viz.plot_obstacles(obstacles, show_inflation=False)
        
        # 3. Path (Overlay on grid)
        path = response_data.get('path', [])
        pruned = response_data.get('pruned_path', [])
        if path:
            viz.plot_astar_path(path, pruned)

    # --- OTHER FLAGS ---
    elif flag == 4:
        viz.plot_obstacles(obstacles, show_inflation=True, original_obstacles=original_obstacles)
    else:
        viz.plot_obstacles(obstacles, show_inflation=False)
        
        should_show_astar = (flag == 1 or flag == 3)
        should_show_smooth = (flag == 2 or flag == 3)
        
        if should_show_astar:
            viz.plot_astar_path(response_data.get('path', []), response_data.get('pruned_path', []))
        
        if should_show_smooth:
            viz.plot_smooth_path(response_data.get('smooth_path', []), response_data.get('control_path', []))
    
    viz.plot_start_goal(start, goal)
    viz.add_legend()
    return viz