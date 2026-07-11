import numpy as np

# CRITICAL: Increased safety margin for obstacle inflation
# This creates a buffer zone around obstacles to ensure the robot doesn't collide
ROBOT_BIGGEST_DIMENTION = 5

# Data splitting parameters for training
DATA_SPLIT_ratio = 8  # train and validation data split
data_split_count = 0  # temporary variable to save the data
total_data = 10  # Initialize the variable for total number of images


# Pre-defined obstacle configurations for testing
# All obstacles are defined as numpy arrays with [x, y] coordinates

obstacleList_Sparse = np.array(
    [
        [[5, 40], [35, 40], [35, 70], [5, 70], [5, 40]],
        [[40, 40], [60, 40], [60, 70], [40, 70], [40, 40]],
        [[10, 10], [45, 10], [45, 35], [10, 35], [10, 10]],
        [[65, 10], [75, 10], [75, 50], [65, 50], [65, 10]],
    ],
    dtype=np.int64,
)

obstacleList_Sparse_Concave_Complex = np.array(
    [
        [[5, 5], [10, 5], [10, 10], [5, 10], [5, 5]],
        [[12, 12], [17, 12], [17, 17], [12, 17], [12, 12]],
        [[20, 20], [25, 20], [25, 25], [20, 25], [20, 20]],
        [[28, 28], [33, 28], [33, 33], [28, 33], [28, 28]],
        [[36, 36], [41, 36], [41, 41], [36, 41], [36, 36]],
        [[44, 44], [49, 44], [49, 49], [44, 49], [44, 44]],
        [[52, 52], [57, 52], [57, 57], [52, 57], [52, 52]],
        [[60, 60], [65, 60], [65, 65], [60, 65], [60, 60]],
        [[12, 20], [17, 20], [17, 25], [12, 25], [12, 20]],
        [[12, 28], [17, 28], [17, 33], [12, 33], [12, 28]],
        [[12, 36], [17, 36], [17, 41], [12, 41], [12, 36]],
        [[12, 44], [17, 44], [17, 49], [12, 49], [12, 44]],
        [[12, 52], [17, 52], [17, 57], [12, 57], [12, 52]],
        [[12, 60], [17, 60], [17, 65], [12, 65], [12, 60]],
        [[20, 20], [25, 20], [25, 25], [20, 25], [20, 20]],
        [[20, 28], [25, 28], [25, 33], [20, 33], [20, 28]],
        [[20, 36], [25, 36], [25, 41], [20, 41], [20, 36]],
        [[20, 44], [25, 44], [25, 49], [20, 49], [20, 44]],
        [[20, 52], [25, 52], [25, 57], [20, 57], [20, 52]],
        [[20, 60], [25, 60], [25, 65], [20, 65], [20, 60]],
        [[28, 20], [37, 20], [37, 25], [28, 25], [28, 20]],
        [[28, 28], [37, 28], [37, 33], [28, 33], [28, 28]],
        [[28, 36], [37, 36], [37, 41], [28, 41], [28, 36]],
        [[28, 44], [37, 44], [37, 49], [28, 49], [28, 44]],
        [[28, 52], [37, 52], [37, 57], [28, 57], [28, 52]],
        [[28, 60], [37, 60], [37, 65], [28, 65], [28, 60]],
        [[38, 20], [53, 20], [53, 25], [38, 25], [38, 20]],
        [[38, 28], [53, 28], [53, 33], [38, 33], [38, 28]],
        [[38, 36], [53, 36], [53, 41], [38, 41], [38, 36]],
        [[38, 44], [53, 44], [53, 49], [38, 49], [38, 44]],
        [[38, 52], [53, 52], [53, 57], [38, 57], [38, 52]],
        [[38, 60], [53, 60], [53, 65], [38, 65], [38, 60]],
        [[55, 20], [67, 20], [67, 25], [55, 25], [55, 20]],
        [[55, 28], [67, 28], [67, 33], [55, 33], [55, 28]],
        [[55, 36], [67, 36], [67, 41], [55, 41], [55, 36]],
        [[55, 44], [67, 44], [67, 49], [55, 49], [55, 44]],
        [[55, 52], [67, 52], [67, 57], [55, 57], [55, 52]],
        [[55, 60], [67, 60], [67, 65], [55, 65], [55, 60]],
    ],
    dtype=np.int64,
)

obstacleList_Sparse_complex = np.array(
    [
        [[5, 5], [10, 5], [10, 10], [5, 10], [5, 5]],
        [[12, 12], [17, 12], [17, 17], [12, 17], [12, 12]],
        [[12, 20], [17, 20], [17, 25], [12, 25], [12, 20]],
        [[12, 28], [17, 28], [17, 33], [12, 33], [12, 28]],
        [[12, 36], [17, 36], [17, 41], [12, 41], [12, 36]],
        [[12, 44], [17, 44], [17, 49], [12, 49], [12, 44]],
        [[12, 52], [17, 52], [17, 57], [12, 57], [12, 52]],
        [[12, 60], [17, 60], [17, 65], [12, 65], [12, 60]],
        [[20, 20], [23, 20], [23, 25], [20, 25], [20, 20]],
        [[20, 28], [23, 28], [23, 33], [20, 33], [20, 28]],
        [[20, 36], [23, 36], [23, 41], [20, 41], [20, 36]],
        [[20, 44], [23, 44], [23, 49], [20, 49], [20, 44]],
        [[20, 52], [23, 52], [23, 57], [20, 57], [20, 52]],
        [[20, 60], [23, 60], [23, 65], [20, 65], [20, 60]],
        [[28, 20], [37, 20], [37, 25], [28, 25], [28, 20]],
        [[28, 28], [37, 28], [37, 33], [28, 33], [28, 28]],
        [[28, 36], [37, 36], [37, 41], [28, 41], [28, 36]],
        [[28, 44], [37, 44], [37, 49], [28, 49], [28, 44]],
        [[28, 52], [37, 52], [37, 57], [28, 57], [28, 52]],
        [[28, 60], [37, 60], [37, 65], [28, 65], [28, 60]],
        [[40, 20], [50, 20], [50, 25], [40, 25], [40, 20]],
        [[40, 28], [50, 28], [50, 33], [40, 33], [40, 28]],
        [[40, 36], [50, 36], [50, 41], [40, 41], [40, 36]],
        [[40, 44], [50, 44], [50, 49], [40, 49], [40, 44]],
        [[40, 52], [50, 52], [50, 57], [40, 57], [40, 52]],
        [[40, 60], [50, 60], [50, 65], [40, 65], [40, 60]],
        [[55, 20], [67, 20], [67, 25], [55, 25], [55, 20]],
        [[55, 28], [67, 28], [67, 33], [55, 33], [55, 28]],
        [[55, 36], [67, 36], [67, 41], [55, 41], [55, 36]],
        [[55, 44], [67, 44], [67, 49], [55, 49], [55, 44]],
        [[55, 52], [67, 52], [67, 57], [55, 57], [55, 52]],
        [[55, 60], [67, 60], [67, 65], [55, 65], [55, 60]],
    ],
    dtype=np.int64,
)

obstacleList_Concave_narrow_Passage = np.array(
    [
        [[6, 68], [74, 68], [74, 70], [6, 70], [6, 68]],
        [[6, 25], [8, 25], [8, 68], [6, 68], [6, 25]],
        [[70, 5], [74, 5], [74, 68], [70, 68], [70, 5]],
        [[6, 5], [70, 5], [70, 9], [6, 9], [6, 5]],
    ],
    dtype=np.int64,
)

obstacleList_Concave = np.array(
    [
        [[20, 60], [60, 60], [60, 70], [20, 70], [20, 60]],
        [[10, 30], [20, 30], [20, 50], [10, 50], [10, 30]],
        [[20, 10], [60, 10], [60, 30], [20, 30], [20, 10]],
    ],
    dtype=np.int64,
)

obstacleList_Concave_with_obstacle = np.array(
    [
        [[20, 60], [60, 60], [60, 70], [20, 70], [20, 60]],
        [[20, 30], [30, 30], [30, 60], [20, 60], [20, 30]],
        [[20, 10], [60, 10], [60, 30], [20, 30], [20, 10]],
    ],
    dtype=np.int64,
)

obstacleList_Narrow_passage = np.array(
    [
        [[20, 10], [30, 10], [30, 70], [20, 70], [20, 10]],
        [[60, 5], [70, 5], [70, 70], [60, 70], [60, 5]],
    ],
    dtype=np.int64,
)

M1 = np.array(
    [
        [[45, 10], [65, 10], [65, 75], [45, 75], [45, 10]],
        [[70, 45], [80, 45], [80, 55], [70, 55], [70, 45]],
        [[20, 45], [40, 45], [40, 55], [20, 55], [20, 45]],
    ],
    dtype=np.int64,
)

M2 = np.array(
    [
        [[20, 30], [40, 30], [40, 40], [20, 40], [20, 30]],
        [[20, 40], [30, 40], [30, 55], [20, 55], [20, 40]],
        [[20, 55], [80, 55], [80, 65], [20, 65], [20, 55]],
        [[70, 40], [80, 40], [80, 55], [70, 55], [70, 40]],
        [[60, 30], [80, 30], [80, 40], [60, 40], [60, 30]],
    ],
    dtype=np.int64,
)

M3 = np.array(
    [
        [[40, 15], [60, 15], [60, 65], [40, 65], [40, 15]],
        [[65, 40], [67, 40], [67, 55], [65, 55], [65, 40]],
    ],
    dtype=np.int64,
)

M4 = np.array(
    [
        [[25, 0], [45, 0], [45, 18], [25, 18], [25, 0]],
        [[60, 0], [80, 0], [80, 18], [60, 18], [60, 0]],
        [[30, 25], [50, 25], [50, 40], [30, 40], [30, 25]],
        [[75, 25], [95, 25], [95, 40], [75, 40], [75, 25]],
        [[25, 55], [45, 55], [45, 65], [25, 65], [25, 55]],
        [[60, 55], [80, 55], [80, 65], [60, 65], [60, 55]],
        [[75, 80], [95, 80], [95, 95], [75, 95], [75, 80]],
        [[40, 80], [65, 80], [65, 95], [40, 95], [40, 80]],
        [[5, 80], [30, 80], [30, 95], [5, 95], [5, 80]],
    ],
    dtype=np.int64,
)

MobileRobotWorkspace = 10 * np.array(
    [
        [[7, 0], [9, 0], [9, 6], [7, 6], [7, 0]],
        [[4, 2], [7, 2], [7, 3], [4, 3], [4, 2]],
        [[12, 4], [16, 4], [16, 6], [12, 6], [12, 4]],
        [[2, 6], [4, 6], [4, 9], [2, 9], [2, 6]],
        [[0, 9], [8, 9], [8, 11.5], [0, 11.5], [0, 9]],
        [[12, 7], [13, 7], [13, 12], [12, 12], [12, 7]],
        [[10, 12], [16, 12], [16, 13], [10, 13], [10, 12]],
        [[4, 12], [6, 12], [6, 16], [4, 16], [4, 12]],
    ],
    dtype=np.int64,
)


# Dictionary mapping obstacle names to their configurations
obstacle_list_value = [
    "",  # Index 0: No obstacles
    M1,
    M2,
    M3,
    M4,
    obstacleList_Sparse,
    obstacleList_Concave_narrow_Passage,
    obstacleList_Concave_with_obstacle,
    obstacleList_Narrow_passage,
    obstacleList_Sparse_complex,
    obstacleList_Sparse_Concave_Complex,
    MobileRobotWorkspace,
]

obstacle_list_name = [
    "no_obs",
    "M1",
    "M2",
    "M3",
    "M4",
    "Sparse",
    "Concave_narrow_Passage",
    "Concave complex",
    "Narrow Passage",
    "Sparse_complex",
    "Sparse_Concave_Complex",
    "MobileRobotWorkspace",
]

# Create dictionary for easy lookup
obstacles_list = dict(zip(obstacle_list_name, obstacle_list_value))


# Helper functions for obstacle conversion (used by server)
def convert_numpy_obstacles_to_dict(numpy_obstacles):
    """
    Converts numpy array obstacles to dictionary format used by server
    This is useful for testing with predefined obstacle sets
    """
    obstacle_dicts = []
    
    for obs_array in numpy_obstacles:
        # Each obstacle is a closed polygon (first point == last point)
        # Convert to list of tuples
        points = [(float(pt[0]), float(pt[1])) for pt in obs_array[:-1]]  # Exclude duplicate last point
        
        obstacle_dicts.append({
            'type': 'polygon',
            'points': points
        })
    
    return obstacle_dicts


def convert_dict_obstacles_to_numpy(dict_obstacles):
    """
    Converts dictionary obstacles (from server) to numpy format
    Used for compatibility with original test code
    """
    numpy_obstacles = []
    
    for obs in dict_obstacles:
        if obs.get('type') in ['rectangle', 'polygon']:
            points = obs.get('points', [])
            if points:
                # Close the polygon if not already closed
                points_array = np.array(points)
                if not np.array_equal(points_array[0], points_array[-1]):
                    points_array = np.vstack([points_array, points_array[0]])
                numpy_obstacles.append(points_array)
    
    return numpy_obstacles


# Testing and validation
if __name__ == "__main__":
    try:
        print("=" * 60)
        print("OBSTACLE LIST CONFIGURATION")
        print("=" * 60)
        print(f"Robot Safety Margin: {ROBOT_BIGGEST_DIMENTION} meters")
        print(f"Total Obstacle Configurations: {len(obstacles_list)}")
        print("\nAvailable Maps:")
        
        for i, name in enumerate(obstacle_list_name):
            if name != "no_obs":
                obs_data = obstacle_list_value[i]
                if isinstance(obs_data, np.ndarray) and obs_data.size > 0:
                    print(f"  [{i:2d}] {name:30s} - {len(obs_data)} obstacles")
        
        print("\n" + "=" * 60)
        print("TESTING OBSTACLE CONVERSION")
        print("=" * 60)
        
        # Test conversion functions
        test_map = M1
        print(f"\nTesting with M1 (3 obstacles):")
        print(f"Original numpy format shape: {test_map.shape}")
        
        # Convert to dict
        dict_format = convert_numpy_obstacles_to_dict(test_map)
        print(f"Converted to dict format: {len(dict_format)} obstacles")
        print(f"Sample obstacle: {dict_format[0]}")
        
        # Convert back to numpy
        numpy_format = convert_dict_obstacles_to_numpy(dict_format)
        print(f"Converted back to numpy: {len(numpy_format)} obstacles")
        
        print("\n✓ Obstacle list properly configured!")
        print("=" * 60)
        
    except Exception as e:
        print(f"ERROR: Obstacle list is not properly defined!")
        print(f"Error details: {e}")
        import traceback
        traceback.print_exc()