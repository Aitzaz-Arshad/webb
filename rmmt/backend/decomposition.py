import numpy as np
import dill
import matplotlib.image as mpimg
from shapely.geometry import Polygon  # Added for polygon validation
from shapely.geometry import Polygon, Point  # Added Point import

class Cell:
    """Represents a single cell in the decomposed map."""
    def __init__(self):
        self.min_x, self.max_x = None, None
        self.left, self.right = list(), list()
        self.ceiling, self.floor = dict(), dict()
        self.center = (None, None)

def Boustrophedon_Cellular_Decomposition(test_case, obstacles_meters=None):
    """
    Decomposes a binary map image into convex cells using the Boustrophedon algorithm.
    Saves the decomposition result to a file using dill.
    Args:
        test_case (str): Directory containing the map.jpg file.
        obstacles_meters (list): Optional list of {'type': 'polygon', 'points': [(x, y), ...]} for validation.
    """
    def calculate_connectivity(slice):
        connectivity = 0
        connective_parts = []
        start_point = -1
        for i in range(len(slice)):
            if slice[i] == 0 and start_point != -1:
                connectivity += 1
                connective_parts.append((start_point, i))
                start_point = -1
            elif slice[i] == 1 and start_point == -1:
                start_point = i
        if start_point != -1:
            connectivity += 1
            connective_parts.append((start_point, len(slice)))
        return connectivity, connective_parts

    def get_adjacency_matrix(left_parts, right_parts) -> np.ndarray:
        adjacency_matrix = np.zeros([len(left_parts), len(right_parts)], dtype=bool)
        for i, left_part in enumerate(left_parts):
            for j, right_part in enumerate(right_parts):
                if min(left_part[1], right_part[1]) - max(left_part[0], right_part[0]) > 0:
                    adjacency_matrix[i, j] = True
        return adjacency_matrix

    def create_cells(decomposed, total_cells_number, obstacles_polygons=None):
        cells = [None]  # No cell with id 0
        for cell_id in range(1, total_cells_number + 1):
            cell = Cell()
            ys, xs = np.where(decomposed == cell_id)
            if len(xs) == 0 or len(ys) == 0:
                continue
                
            cell.min_x, cell.max_x = np.min(xs), np.max(xs)
            
            for y, x in zip(ys, xs):
                # update left
                if x == cell.min_x:
                    cell.left.append(y)
                # update right
                if x == cell.max_x:
                    cell.right.append(y)
                # update ceiling
                if (x not in cell.ceiling) or (y > cell.ceiling.get(x, -1)):
                    cell.ceiling[x] = y
                # update floor
                if (x not in cell.floor) or (y < cell.floor.get(x, H+1)):
                    cell.floor[x] = y
            
            # Calculate center and validate
            x_center = int((cell.min_x + cell.max_x) / 2)
            if x_center in cell.ceiling and x_center in cell.floor:
                y_center = int((cell.ceiling[x_center] + cell.floor[x_center]) / 2)
            else:  # Fallback for thin cells
                x_center, y_center = int(np.mean(xs)), int(np.mean(ys))
            
            # Validate center is not inside any obstacle (using original meters coordinates)
            if obstacles_polygons:
                center_meters = (x_center + min_x, y_center + min_y)  # Convert back to meters
                center_valid = True
                for poly in obstacles_polygons:
                    if Polygon(poly).contains(Point(center_meters[0], center_meters[1])):
                        center_valid = False
                        break
                if center_valid:
                    cell.center = (x_center, y_center)
                else:
                    # Fallback to nearest valid point (simplified approach)
                    cell.center = (x_center, y_center)  # TODO: Improve with nearest free point
            else:
                cell.center = (x_center, y_center)

            cells.append(cell)
        return cells

    # Load and process the binary image
    image = mpimg.imread(test_case + "/map.jpg")
    if len(image.shape) > 2:
        image = image[:, :, 0]
    H, W = image.shape
    binary_image = (image > 127)

    # Load obstacle data for validation (if provided)
    min_x, max_x, min_y, max_y = None, None, None, None  # To be set from dp_planner.py context
    obstacles_polygons = []
    if obstacles_meters:
        min_x = min(ob['points'][0][0] for ob in obstacles_meters if ob['points'])
        max_x = max(ob['points'][0][0] for ob in obstacles_meters if ob['points'])
        min_y = min(ob['points'][0][1] for ob in obstacles_meters if ob['points'])
        max_y = max(ob['points'][0][1] for ob in obstacles_meters if ob['points'])
        for obs in obstacles_meters:
            if obs['type'] in ['rectangle', 'polygon']:
                obstacles_polygons.append([(p[0] - min_x, p[1] - min_y) for p in obs['points']])

    last_connectivity = 0
    last_connectivity_parts = []
    last_cells = []
    total_cells_number = 0
    decomposed = np.zeros(binary_image.shape, dtype=int)

    for x in range(binary_image.shape[1]):
        current_slice = binary_image[:, x]
        connectivity, connective_parts = calculate_connectivity(current_slice)

        if last_connectivity == 0:
            current_cells = []
            for _ in range(connectivity):
                total_cells_number += 1
                current_cells.append(total_cells_number)
        elif connectivity == 0:
            current_cells = []
        else:
            adjacency_matrix = get_adjacency_matrix(last_connectivity_parts, connective_parts)
            current_cells = [0] * len(connective_parts)

            for i in range(last_connectivity):
                adj_sum = np.sum(adjacency_matrix[i, :])
                if adj_sum == 1:
                    j = np.where(adjacency_matrix[i, :])[0][0]
                    current_cells[j] = last_cells[i]
                elif adj_sum > 1:
                    for j in np.where(adjacency_matrix[i, :])[0]:
                        total_cells_number += 1
                        current_cells[j] = total_cells_number
            
            for j in range(connectivity):
                adj_sum = np.sum(adjacency_matrix[:, j])
                if adj_sum > 1:
                    total_cells_number += 1
                    current_cells[j] = total_cells_number
                elif adj_sum == 0:
                    total_cells_number += 1
                    current_cells[j] = total_cells_number

        for cell, slice_part in zip(current_cells, connective_parts):
            decomposed[slice_part[0]: slice_part[1], x] = cell

        last_connectivity = connectivity
        last_connectivity_parts = connective_parts
        last_cells = current_cells

    cells = create_cells(decomposed, total_cells_number, obstacles_polygons)
    with open(test_case + "/decomposed_result", "wb") as myfile:
        dill.dump([decomposed, total_cells_number, cells], myfile)