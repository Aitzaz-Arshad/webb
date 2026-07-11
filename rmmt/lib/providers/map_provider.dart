// lib/providers/map_provider.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_planning/api/api_service.dart';
import 'package:path_planning/models/map_data.dart';
import 'package:path_planning/models/obstacle.dart';
import 'package:path_planning/utils/geo_utils.dart';

enum DrawingMode {
  none,
  boundary,
  obstacleRect,
  obstacleCircle,
  setStart,
  setEnd,
}

enum PlanningAlgorithm { aStar, dynamicProgramming }

// NEW: Model for grid cell data
class GridCell {
  final int cellNumber;
  final LatLng center;
  final LatLng minBound;
  final LatLng maxBound;

  GridCell({
    required this.cellNumber,
    required this.center,
    required this.minBound,
    required this.maxBound,
  });

  factory GridCell.fromJson(Map<String, dynamic> json) {
    return GridCell(
      cellNumber: json['cell_number'],
      center: LatLng(
        json['center']['latitude'],
        json['center']['longitude'],
      ),
      minBound: LatLng(
        json['bounds']['min']['latitude'],
        json['bounds']['min']['longitude'],
      ),
      maxBound: LatLng(
        json['bounds']['max']['latitude'],
        json['bounds']['max']['longitude'],
      ),
    );
  }
}

class MapProvider extends ChangeNotifier {
  DrawingMode _drawingMode = DrawingMode.none;
  DrawingMode get drawingMode => _drawingMode;

  Obstacle? _boundary;
  Obstacle? get boundary => _boundary;

  List<Obstacle> _obstacles = [];
  List<Obstacle> get obstacles => _obstacles;

  LatLng? _startPoint;
  LatLng? get startPoint => _startPoint;

  LatLng? _endPoint;
  LatLng? get endPoint => _endPoint;

  List<LatLng> _unprunedPath = [];
  List<LatLng> get unprunedPath => _unprunedPath;

  List<LatLng> _prunedPath = [];
  List<LatLng> get prunedPath => _prunedPath;

  // --- ADDED: Smooth Path Variables ---
  List<LatLng> _smoothPath = [];
  List<LatLng> get smoothPath => _smoothPath;

  List<LatLng> _controlPath = [];
  List<LatLng> get controlPath => _controlPath;
  // --- END ADDED ---

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  PlanningAlgorithm? _loadingAlgorithm;
  PlanningAlgorithm? get loadingAlgorithm => _loadingAlgorithm;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  LatLng _initialCenter = const LatLng(
    51.509364,
    -0.128928,
  );
  LatLng get initialCenter => _initialCenter;

  List<String> _savedMapNames = [];
  List<String> get savedMapNames => _savedMapNames;

  String? _currentMapName;
  String? get currentMapName => _currentMapName;

  LatLng? _tempStartPoint;

  // NEW: Grid-related properties
  List<GridCell> _gridCells = [];
  List<GridCell> get gridCells => _gridCells;

  bool _showGrid = false;
  bool get showGrid => _showGrid;

  bool _isLoadingGrid = false;
  bool get isLoadingGrid => _isLoadingGrid;

  PlanningAlgorithm? _lastUsedAlgorithm;
  PlanningAlgorithm? get lastUsedAlgorithm => _lastUsedAlgorithm;

  final ApiService _apiService = ApiService();

  MapProvider() {
    _determinePosition();
    _loadSavedMaps();
  }

  void setBoundaryAndObstacles(Obstacle boundary, List<Obstacle> obstacles) {
    _boundary = boundary;
    _obstacles = obstacles;
    _unprunedPath = [];
    _prunedPath = [];
    _smoothPath = []; 
    _controlPath = []; 
    _gridCells = []; 
    _showGrid = false;

    if (boundary.points != null && boundary.points!.isNotEmpty) {
      double avgLat =
          boundary.points!.map((p) => p.latitude).reduce((a, b) => a + b) /
          boundary.points!.length;
      double avgLon =
          boundary.points!.map((p) => p.longitude).reduce((a, b) => a + b) /
          boundary.points!.length;
      _initialCenter = LatLng(avgLat, avgLon);
    }

    notifyListeners();
  }

  void setCurrentMapName(String name) {
    _currentMapName = name;
    notifyListeners();
  }

  // NEW: Toggle grid visibility
  void toggleGridVisibility() {
    _showGrid = !_showGrid;
    notifyListeners();
  }

  // NEW: Fetch grid data from backend
  Future<void> fetchGridData() async {
    if (_startPoint == null || _endPoint == null || _boundary == null) {
      _errorMessage = 'Please set a boundary, start, and end point first.';
      notifyListeners();
      return;
    }

    if (_currentMapName == null) {
      _errorMessage = 'Please save or load a map first.';
      notifyListeners();
      return;
    }

    _isLoadingGrid = true;
    _errorMessage = '';
    notifyListeners();

    final mapData = MapData(
      name: _currentMapName!,
      boundary: _boundary!,
      obstacles: _obstacles,
      startPoint: _startPoint,
      endPoint: _endPoint,
    );

    try {
      final result = await _apiService.getGridData(mapData);
      _gridCells = (result['cells'] as List)
          .map((cell) => GridCell.fromJson(cell))
          .toList();
      _showGrid = true;
      print('Fetched ${_gridCells.length} grid cells');
    } catch (e) {
      _errorMessage = 'Failed to fetch grid: $e';
      print('Error fetching grid: $e');
    } finally {
      _isLoadingGrid = false;
      notifyListeners();
    }
  }

  Future<void> _loadSavedMaps() async {
    try {
      _savedMapNames = await _apiService.listMaps();
      print('Loaded map names: $_savedMapNames');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load saved maps: $e';
      print('Error loading saved maps: $e');
      notifyListeners();
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _errorMessage = 'Location services are disabled.';
      notifyListeners();
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _errorMessage = 'Location permissions are denied.';
        notifyListeners();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _errorMessage = 'Location permissions are permanently denied.';
      notifyListeners();
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      _initialCenter = LatLng(position.latitude, position.longitude);
      print('Updated initial center: $_initialCenter');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Could not get location: $e';
      print('Error getting location: $e');
      notifyListeners();
    }
  }

  void setDrawingMode(DrawingMode mode) {
    _drawingMode = mode;
    _tempStartPoint = null;
    notifyListeners();
  }

  void handleMapTap(LatLng point) {
    switch (_drawingMode) {
      case DrawingMode.boundary:
      case DrawingMode.obstacleRect:
        _handleRectDrawing(point);
        break;
      case DrawingMode.obstacleCircle:
        _handleCircleDrawing(point);
        break;
      case DrawingMode.setStart:
        _startPoint = point;
        _drawingMode = DrawingMode.none;
        break;
      case DrawingMode.setEnd:
        _endPoint = point;
        _drawingMode = DrawingMode.none;
        break;
      case DrawingMode.none:
        break;
    }
    notifyListeners();
  }

  void _handleRectDrawing(LatLng point) {
    if (_tempStartPoint == null) {
      _tempStartPoint = point;
    } else {
      final corner1 = _tempStartPoint!;
      final corner2 = point;
      _tempStartPoint = null;

      final rectPoints = [
        corner1,
        LatLng(corner1.latitude, corner2.longitude),
        corner2,
        LatLng(corner2.latitude, corner1.longitude),
      ];

      final newObstacle = Obstacle(
        type: ObstacleType.rectangle,
        points: rectPoints,
      );

      if (_drawingMode == DrawingMode.boundary) {
        _boundary = newObstacle;
      } else {
        _obstacles.add(newObstacle);
      }
      _drawingMode = DrawingMode.none;
      notifyListeners();
    }
  }

  void _handleCircleDrawing(LatLng point) {
    if (_tempStartPoint == null) {
      _tempStartPoint = point;
    } else {
      final center = _tempStartPoint!;
      final radiusPoint = point;
      _tempStartPoint = null;

      final radius = GeoUtils.calculateDistance(center, radiusPoint);
      final newObstacle = Obstacle(
        type: ObstacleType.circle,
        center: center,
        radius: radius,
      );

      _obstacles.add(newObstacle);
      _drawingMode = DrawingMode.none;
      notifyListeners();
    }
  }

  Future<void> saveMap(String name) async {
    if (name.isEmpty || _boundary == null) {
      _errorMessage = 'Please provide a valid name and set a boundary.';
      print('Save map failed: Empty name or no boundary');
      notifyListeners();
      return;
    }
    final mapData = MapData(
      name: name,
      boundary: _boundary!,
      obstacles: List.from(_obstacles),
      startPoint: _startPoint,
      endPoint: _endPoint,
    );
    try {
      await _apiService.saveMap(mapData);
      _currentMapName = name;
      print('Saved map: $name');
      await _loadSavedMaps();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to save map: $e';
      print('Error saving map: $e');
      notifyListeners();
    }
  }

  Future<void> loadMap(String name) async {
    try {
      print('Loading map: $name');
      final data = await _apiService.loadMap(name);
      print('Received map data: $data');
      final mapData = MapData.fromJson(data);
      setBoundaryAndObstacles(
        mapData.boundary,
        mapData.obstacles,
      );
      _startPoint = mapData.startPoint;
      _endPoint = mapData.endPoint;
      _currentMapName = name;
      _unprunedPath = [];
      _prunedPath = [];
      _smoothPath = []; 
      _controlPath = []; 
      _gridCells = []; 
      _showGrid = false;
      _errorMessage = '';
      print(
        'Loaded map: $name, boundary: $_boundary, obstacles: $_obstacles, start: $_startPoint, end: $_endPoint',
      );
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load map: $e';
      print('Error loading map: $e');
      notifyListeners();
    }
  }

  Future<void> deleteMap(String name) async {
    try {
      print('Deleting map: $name');
      await _apiService.deleteMap(name);
      _savedMapNames.remove(name);
      if (_currentMapName == name) {
        _currentMapName = null;
        clearPathAndPoints();
      }
      _errorMessage = '';
      print('Successfully deleted map: $name');
      await _loadSavedMaps();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete map: $e';
      print('Error deleting map: $e');
      notifyListeners();
    }
  }

  Future<void> calculatePath(PlanningAlgorithm algorithm) async {
    if (_startPoint == null || _endPoint == null || _boundary == null) {
      _errorMessage = 'Please set a boundary, start, and end point.';
      print('Calculate path failed: Missing boundary, start, or end point');
      notifyListeners();
      return;
    }

    if (algorithm == PlanningAlgorithm.dynamicProgramming &&
        _currentMapName == null) {
      _errorMessage =
          'Please save or load a map first for Dynamic Programming.';
      print('Calculate path failed: No map loaded for DP');
      notifyListeners();
      return;
    }

    _isLoading = true;
    _loadingAlgorithm = algorithm;
    _lastUsedAlgorithm = algorithm; // NEW: Track last used algorithm
    _errorMessage = '';
    _unprunedPath = [];
    _prunedPath = [];
    _smoothPath = []; // Clear smooth path
    _controlPath = []; // Clear control path
    _gridCells = []; // NEW: Clear grid when recalculating path
    _showGrid = false;
    notifyListeners();

    final mapData = MapData(
      name: algorithm == PlanningAlgorithm.dynamicProgramming
          ? _currentMapName!
          : 'current',
      boundary: _boundary!,
      obstacles: _obstacles,
      startPoint: _startPoint,
      endPoint: _endPoint,
    );

    try {
      final result = algorithm == PlanningAlgorithm.aStar
          ? await _apiService.getPath(mapData)
          : await _apiService.getPathWithDP(mapData);
      _unprunedPath = result['path'] as List<LatLng>;
      _prunedPath = result['pruned_path'] as List<LatLng>;

      // --- CRITICAL: Store smooth path data from API ---
      if (result.containsKey('smooth_path')) {
        _smoothPath = result['smooth_path'] as List<LatLng>;
      }
      if (result.containsKey('control_path')) {
        _controlPath = result['control_path'] as List<LatLng>;
      }
      // --- END CRITICAL ---

      print(
        'Calculated path: unpruned=${_unprunedPath.length}, pruned=${_prunedPath.length}, smooth=${_smoothPath.length}',
      );
    } catch (e) {
      _errorMessage = e.toString();
      print('Error calculating path: $e');
    } finally {
      _isLoading = false;
      _loadingAlgorithm = null;
      notifyListeners();
    }
  }

  void clearPathAndPoints() {
    _startPoint = null;
    _endPoint = null;
    _unprunedPath = [];
    _prunedPath = [];
    _smoothPath = []; 
    _controlPath = []; 
    _drawingMode = DrawingMode.none;
    _gridCells = []; 
    _showGrid = false;
    _lastUsedAlgorithm = null;
    notifyListeners();
  }

  void clearAll() {
    _drawingMode = DrawingMode.none;
    _boundary = null;
    _obstacles = [];
    _startPoint = null;
    _endPoint = null;
    _unprunedPath = [];
    _prunedPath = [];
    _smoothPath = []; 
    _controlPath = []; 
    _tempStartPoint = null;
    _isLoading = false;
    _loadingAlgorithm = null;
    _errorMessage = '';
    _currentMapName = null;
    _gridCells = []; 
    _showGrid = false;
    _isLoadingGrid = false;
    _lastUsedAlgorithm = null;
    notifyListeners();
  }
}