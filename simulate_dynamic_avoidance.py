#!/usr/bin/env python3
"""
Complete Navigation Pipeline (Infinite Auto-Reset Loop):
1. A* Grid Path Planning
2. Path Pruning (Line-of-sight shortcutting to remove grid jitter)
3. Cubic B-Spline Path Smoothing (continuous curve from Start to Goal)
4. MPC Local Controller with 2 Dynamic Obstacles
5. Continuous Loop: Automatically restarts from Start when Goal is reached!

Run natively on Windows with:
  cd d:\web\zz
  python simulate_dynamic_avoidance.py
"""

import math
import heapq
import numpy as np
import matplotlib.pyplot as plt
from scipy.interpolate import make_interp_spline

# ==========================================
# 1. GLOBAL PATH PLANNING (A* ALGORITHM)
# ==========================================
class AStarPlanner:
    def __init__(self, grid_size=0.5, bounds=(0, 10, 0, 10)):
        self.resolution = grid_size
        self.min_x, self.max_x, self.min_y, self.max_y = bounds
        self.width = int((self.max_x - self.min_x) / self.resolution)
        self.height = int((self.max_y - self.min_y) / self.resolution)

    def world_to_grid(self, x, y):
        gx = int((x - self.min_x) / self.resolution)
        gy = int((y - self.min_y) / self.resolution)
        return (gx, gy)

    def grid_to_world(self, gx, gy):
        wx = self.min_x + (gx + 0.5) * self.resolution
        wy = self.min_y + (gy + 0.5) * self.resolution
        return (wx, wy)

    def is_free(self, gx, gy, static_obstacles):
        wx, wy = self.grid_to_world(gx, gy)
        if not (self.min_x <= wx <= self.max_x and self.min_y <= wy <= self.max_y):
            return False
        for ox, oy, r in static_obstacles:
            if math.hypot(wx - ox, wy - oy) < (r + 0.35):  # Safety margin
                return False
        return True

    def is_line_free(self, p1, p2, static_obstacles, step_size=0.1):
        dist = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        steps = int(math.ceil(dist / step_size))
        for i in range(steps + 1):
            t = i / max(1, steps)
            x = p1[0] + t * (p2[0] - p1[0])
            y = p1[1] + t * (p2[1] - p1[1])
            gx, gy = self.world_to_grid(x, y)
            if not self.is_free(gx, gy, static_obstacles):
                return False
        return True

    def plan(self, start, goal, static_obstacles):
        start_g = self.world_to_grid(start[0], start[1])
        goal_g = self.world_to_grid(goal[0], goal[1])

        open_set = []
        heapq.heappush(open_set, (0.0, start_g))
        came_from = {}
        g_score = {start_g: 0.0}

        movements = [
            (0, 1, 1.0), (1, 0, 1.0), (0, -1, 1.0), (-1, 0, 1.0),
            (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)
        ]

        while open_set:
            _, current = heapq.heappop(open_set)

            if current == goal_g:
                path_grid = [current]
                while current in came_from:
                    current = came_from[current]
                    path_grid.append(current)
                path_grid.reverse()
                return [self.grid_to_world(gx, gy) for gx, gy in path_grid]

            for dx, dy, cost in movements:
                neighbor = (current[0] + dx, current[1] + dy)
                if not self.is_free(neighbor[0], neighbor[1], static_obstacles):
                    continue

                tentative_g = g_score[current] + cost
                if neighbor not in g_score or tentative_g < g_score[neighbor]:
                    came_from[neighbor] = current
                    g_score[neighbor] = tentative_g
                    h = math.hypot(goal_g[0] - neighbor[0], goal_g[1] - neighbor[1])
                    heapq.heappush(open_set, (tentative_g + h, neighbor))

        return [start, goal]


# ==========================================
# 2. PATH PRUNING (LINE OF SIGHT SHORTCUTTING)
# ==========================================
def prune_path(raw_path, planner, static_obstacles):
    if len(raw_path) <= 2:
        return raw_path

    pruned = [raw_path[0]]
    curr_idx = 0

    while curr_idx < len(raw_path) - 1:
        next_idx = len(raw_path) - 1
        found = False

        while next_idx > curr_idx + 1:
            p1 = raw_path[curr_idx]
            p2 = raw_path[next_idx]

            if planner.is_line_free(p1, p2, static_obstacles):
                pruned.append(p2)
                curr_idx = next_idx
                found = True
                break
            next_idx -= 1

        if not found:
            curr_idx += 1
            pruned.append(raw_path[curr_idx])

    return pruned


# ==========================================
# 3. PATH SMOOTHING (CUBIC B-SPLINE)
# ==========================================
def smooth_path(pruned_path, num_points=150):
    if len(pruned_path) < 3:
        return np.array(pruned_path)

    path_arr = np.array(pruned_path)
    x = path_arr[:, 0]
    y = path_arr[:, 1]

    distances = np.sqrt(np.diff(x)**2 + np.diff(y)**2)
    u = np.insert(np.cumsum(distances), 0, 0)
    if u[-1] == 0:
        return path_arr

    u_norm = u / u[-1]
    u_fine = np.linspace(0, 1, num_points)

    try:
        spl_x = make_interp_spline(u_norm, x, k=min(3, len(pruned_path) - 1))
        spl_y = make_interp_spline(u_norm, y, k=min(3, len(pruned_path) - 1))
        x_smooth = spl_x(u_fine)
        y_smooth = spl_y(u_fine)
    except Exception:
        x_smooth = np.interp(u_fine, u_norm, x)
        y_smooth = np.interp(u_fine, u_norm, y)

    return np.vstack((x_smooth, y_smooth)).T


# ==========================================
# 4. MPC LOCAL CONTROLLER
# ==========================================
class MPCController:
    def __init__(self, horizon=15, dt=0.1):
        self.N = horizon
        self.dt = dt
        self.max_v = 0.45
        self.max_w = 1.1
        self.safe_distance = 0.95

        self.w_path = 3.5
        self.w_obstacle = 90.0
        self.w_control = 0.2

    def solve(self, robot_pose, smoothed_path, dyn_obstacles):
        rx, ry, ryaw = robot_pose
        
        dists_to_path = np.hypot(smoothed_path[:, 0] - rx, smoothed_path[:, 1] - ry)
        target_idx = np.argmin(dists_to_path)

        ref_window = []
        for k in range(self.N):
            idx = min(target_idx + k, len(smoothed_path) - 1)
            ref_window.append(smoothed_path[idx])
        ref_window = np.array(ref_window)

        v_candidates = np.linspace(0.0, self.max_v, 8)
        w_candidates = np.linspace(-self.max_w, self.max_w, 23)

        best_cost = float('inf')
        best_v, best_w = 0.0, 0.0
        best_hx, best_hy = [], []

        for v in v_candidates:
            for w in w_candidates:
                x, y, yaw = rx, ry, ryaw
                cost = 0.0
                hx, hy = [], []

                dyn_pos_list = [obs['pos'].copy() for obs in dyn_obstacles]

                for k in range(self.N):
                    x += v * math.cos(yaw) * self.dt
                    y += v * math.sin(yaw) * self.dt
                    yaw += w * self.dt

                    hx.append(x)
                    hy.append(y)

                    ref_x, ref_y = ref_window[k]
                    cost += self.w_path * math.hypot(ref_x - x, ref_y - y)

                    for obs_idx, obs in enumerate(dyn_obstacles):
                        dyn_pos_list[obs_idx] += obs['vel'] * self.dt
                        d_dyn = math.hypot(dyn_pos_list[obs_idx][0] - x, dyn_pos_list[obs_idx][1] - y) - obs['radius']
                        if d_dyn < self.safe_distance:
                            cost += self.w_obstacle * ((self.safe_distance - d_dyn)**2)

                cost += self.w_control * (w**2) - 0.5 * v

                if cost < best_cost:
                    best_cost = cost
                    best_v, best_w = v, w
                    best_hx, best_hy = hx, hy

        return best_v, best_w, (best_hx, best_hy)


# ==========================================
# 5. SIMULATION MAIN LOOP
# ==========================================
def run_simulation():
    start = (0.5, 0.5)
    goal = (9.5, 9.5)

    static_obstacles = [
        (3.0, 3.0, 0.8),
        (6.5, 6.0, 1.0),
        (3.5, 8.0, 0.7)
    ]

    print("🔍 1. Computing A* Global Path...")
    planner = AStarPlanner()
    raw_path = planner.plan(start, goal, static_obstacles)

    print("✂️ 2. Pruning A* Path (Line-of-Sight Shortcutting)...")
    pruned_path = prune_path(raw_path, planner, static_obstacles)

    print("✨ 3. Generating B-Spline Path Smoothing from Start to Goal...")
    smoothed_path = smooth_path(pruned_path, num_points=150)

    raw_arr = np.array(raw_path)
    pruned_arr = np.array(pruned_path)

    plt.figure(figsize=(10, 9))
    plt.ion()
    ax = plt.gca()

    # -------------------------------------------------------------
    # PHASE 1: SHOW A*, PRUNED & SMOOTHED PATH (2.5s PAUSE)
    # -------------------------------------------------------------
    print("📌 PHASE 1: Displaying A* Raw, Pruned, and Smoothed Paths (Start to Goal). Pausing 2.5 seconds...")
    ax.set_xlim(-0.5, 10.5)
    ax.set_ylim(-0.5, 10.5)
    ax.set_title("PHASE 1: A* Raw Grid -> Pruned Path -> B-Spline Smoothed Path", fontsize=13, fontweight='bold', color='darkblue')
    ax.set_xlabel("X (meters)")
    ax.set_ylabel("Y (meters)")
    ax.grid(True, linestyle='--', alpha=0.5)

    for ox, oy, r in static_obstacles:
        ax.add_patch(plt.Circle((ox, oy), r, color='gray', alpha=0.6))

    ax.plot(raw_arr[:, 0], raw_arr[:, 1], 'y:', linewidth=1.5, alpha=0.6, label="1. A* Raw Grid Path")
    ax.plot(pruned_arr[:, 0], pruned_arr[:, 1], 'o--', color='orange', linewidth=2.2, markersize=7, label="2. Pruned A* Path (Line-of-Sight)")
    ax.plot(smoothed_path[:, 0], smoothed_path[:, 1], 'c-', linewidth=3.2, label="3. B-Spline Smoothed Path (Start -> Goal)")

    ax.plot(start[0], start[1], 'go', markersize=12, label="Start Position")
    ax.plot(goal[0], goal[1], 'r*', markersize=18, label="Goal Position")

    ax.legend(loc='upper left', fontsize=9.5, framealpha=0.9)
    plt.draw()
    plt.pause(2.5)

    # -------------------------------------------------------------
    # PHASE 2: CONTINUOUS INFINITE RUN LOOP (AUTO RESET AT GOAL)
    # -------------------------------------------------------------
    print("🚀 PHASE 2: Starting Continuous Robot Execution Loop...")

    mpc = MPCController()
    lap_count = 1

    while True:
        print(f"\n🔄 Running Navigation Lap #{lap_count}...")
        
        robot_pose = [start[0], start[1], math.atan2(goal[1] - start[1], goal[0] - start[0])]
        robot_history = [[start[0], start[1]]]

        # Dynamic Obstacles with Clean Names (No Coordinates/Directions in Legend)
        dyn_obstacles = [
            {
                'name': 'Person 1',
                'pos': np.array([4.5, 3.2]),
                'vel': np.array([-0.16, 0.0]),
                'bounds_x': (0.1, 4.5),
                'radius': 0.55,
                'color': 'red'
            },
            {
                'name': 'Person 2',
                'pos': np.array([5.8, 4.0]),
                'vel': np.array([0.0, 0.16]),
                'bounds_y': (4.0, 7.2),
                'radius': 0.55,
                'color': 'magenta'
            }
        ]

        step = 0
        max_steps = 350

        while step < max_steps:
            # Move Dynamic Obstacles
            obs1 = dyn_obstacles[0]
            obs1['pos'] += obs1['vel'] * mpc.dt
            if obs1['pos'][0] <= obs1['bounds_x'][0] or obs1['pos'][0] >= obs1['bounds_x'][1]:
                obs1['vel'][0] *= -1.0

            obs2 = dyn_obstacles[1]
            obs2['pos'] += obs2['vel'] * mpc.dt
            if obs2['pos'][1] >= obs2['bounds_y'][1] or obs2['pos'][1] <= obs2['bounds_y'][0]:
                obs2['vel'][1] *= -1.0

            # Solve MPC Local Control
            v, w, mpc_horizon = mpc.solve(robot_pose, smoothed_path, dyn_obstacles)

            # Update Robot State
            robot_pose[0] += v * math.cos(robot_pose[2]) * mpc.dt
            robot_pose[1] += v * math.sin(robot_pose[2]) * mpc.dt
            robot_pose[2] += w * mpc.dt

            robot_history.append([robot_pose[0], robot_pose[1]])

            # Rendering Frame
            plt.clf()
            ax = plt.gca()
            ax.set_xlim(-0.5, 10.5)
            ax.set_ylim(-0.5, 10.5)
            ax.set_title(f"Lap #{lap_count} - MPC Dynamic Avoidance (Step {step})", fontsize=12, fontweight='bold')
            ax.set_xlabel("X (meters)")
            ax.set_ylabel("Y (meters)")
            ax.grid(True, linestyle='--', alpha=0.5)

            # Static Obstacles
            for ox, oy, r in static_obstacles:
                ax.add_patch(plt.Circle((ox, oy), r, color='gray', alpha=0.6))

            # Paths
            ax.plot(raw_arr[:, 0], raw_arr[:, 1], 'y:', linewidth=1.2, alpha=0.5, label="A* Raw Path")
            ax.plot(pruned_arr[:, 0], pruned_arr[:, 1], 'o--', color='orange', linewidth=2.0, markersize=5, label="Pruned A* Path")
            ax.plot(smoothed_path[:, 0], smoothed_path[:, 1], 'c-', linewidth=2.5, alpha=0.85, label="Smoothed Reference Path")

            # Render 2 Dynamic Obstacles
            for obs in dyn_obstacles:
                dp = obs['pos']
                ax.add_patch(plt.Circle((dp[0], dp[1]), obs['radius'], color=obs['color'], alpha=0.85, label=f"Dynamic: {obs['name']}"))
                ax.arrow(dp[0], dp[1], obs['vel'][0]*1.5, obs['vel'][1]*1.5, head_width=0.2, color='black')

            # MPC Real-Time Horizon (Blue)
            ax.plot(mpc_horizon[0], mpc_horizon[1], 'b--^', markersize=3, linewidth=2.0, label="MPC Predicted Horizon")

            # Robot Body & Executed Path
            rh = np.array(robot_history)
            ax.plot(rh[:, 0], rh[:, 1], 'g-', linewidth=3.0, label="Executed Trajectory")
            ax.add_patch(plt.Circle((robot_pose[0], robot_pose[1]), 0.3, color='green'))
            ax.arrow(robot_pose[0], robot_pose[1], 0.4*math.cos(robot_pose[2]), 0.4*math.sin(robot_pose[2]), head_width=0.15, color='black')

            # Goal
            ax.plot(goal[0], goal[1], 'r*', markersize=18, label="Goal")

            ax.legend(loc='upper left', fontsize=8.0, framealpha=0.9)
            plt.pause(0.03)

            # Check goal reach -> Reset & Restart Lap!
            if math.hypot(goal[0] - robot_pose[0], goal[1] - robot_pose[1]) < 0.4:
                print(f"🎉 Goal Reached! Resetting robot to Start...")
                plt.pause(1.0)
                lap_count += 1
                break

            step += 1

if __name__ == '__main__':
    run_simulation()
