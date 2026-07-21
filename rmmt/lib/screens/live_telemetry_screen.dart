// lib/screens/live_telemetry_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_planning/api/api_service.dart';
import 'package:path_planning/widgets/camera_stream_stub.dart'
    if (dart.library.html) 'package:path_planning/widgets/camera_stream_web.dart';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6);

class LiveTelemetryScreen extends StatefulWidget {
  const LiveTelemetryScreen({super.key});

  @override
  State<LiveTelemetryScreen> createState() => _LiveTelemetryScreenState();
}

class _LiveTelemetryScreenState extends State<LiveTelemetryScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final GlobalKey _mapKey = GlobalKey();
  
  bool _isLoading = true;
  Timer? _telemetryTimer;
  Timer? _pathTimer;
  
  String _robotStatus = 'free';
  double _robotX = 0.0;
  double _robotY = 0.0;
  int _queueLength = 0;
  Map<String, dynamic>? _currentOrder;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Active ROS Path states & map theme controls
  List<Offset> _rosPath = [];
  bool _showRosPath = false;
  bool _isFetchingPath = false;
  String _mapTheme = 'clean'; // 'clean', 'dark_hud', 'classic'
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _initData();
    
    // Fetch telemetry every 1 second
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) => _pollTelemetry());
    
    // Poll ROS path from RViz every 1.5 seconds if active
    _pathTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_showRosPath) {
        _fetchRosPathSilently();
      }
    });
    
    // Set up pulsing animation for the robot location icon
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _pathTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _pollTelemetry() async {
    try {
      final statusResponse = await _apiService.getRobotStatus();
      if (mounted) {
        setState(() {
          _robotStatus = statusResponse['status'] ?? 'free';
          _robotX = (statusResponse['x'] as num?)?.toDouble() ?? 0.0;
          _robotY = (statusResponse['y'] as num?)?.toDouble() ?? 0.0;
          _queueLength = (statusResponse['queue_length'] as num?)?.toInt() ?? 0;
          _currentOrder = statusResponse['current_order'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      // Silent catch
    }
  }

  // Polls the ROS global planner /plan path from Turtlebot
  Future<void> _fetchRosPathSilently() async {
    try {
      final result = await _apiService.getRosPlan();
      final List<dynamic> pathPoints = result['path'] ?? [];
      
      if (mounted) {
        setState(() {
          _rosPath = pathPoints
              .where((p) => p != null && p.length >= 2 && p[0] != null && p[1] != null)
              .map<Offset>((p) {
                final double rx = (p[0] as num).toDouble();
                final double ry = (p[1] as num).toDouble();
                return _mapMetersToPixel(rx, ry);
              }).toList();
        });
      }
    } catch (e) {
      // Silent error catching for background polling
    }
  }

  void _zoomIn() {
    final double currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale < 4.5) {
      _transformationController.value = _transformationController.value.scaled(1.25, 1.25, 1.0);
    }
  }

  void _zoomOut() {
    final double currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 0.6) {
      _transformationController.value = _transformationController.value.scaled(0.8, 0.8, 1.0);
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _cycleMapTheme() {
    setState(() {
      if (_mapTheme == 'clean') {
        _mapTheme = 'dark_hud';
      } else if (_mapTheme == 'dark_hud') {
        _mapTheme = 'classic';
      } else {
        _mapTheme = 'clean';
      }
    });

    final String label = _mapTheme == 'clean'
        ? 'Clean Floorplan (Transparent)'
        : (_mapTheme == 'dark_hud' ? 'Cyberpunk Dark HUD' : 'Raw SLAM Grid');

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Map Style: $label'),
        duration: const Duration(seconds: 1),
        backgroundColor: kNavyMid,
      ),
    );
  }

  String get _currentMapAsset {
    if (_mapTheme == 'dark_hud') {
      return 'assets/images/my_sim_world_dark.png';
    } else if (_mapTheme == 'classic') {
      return 'assets/images/my_sim_world_classic.png';
    } else {
      return 'assets/images/my_sim_world.png';
    }
  }

  // Maps Gazebo/ROS world coordinates (meters) to normalized image coordinates (0.0 to 1.0)
  // Matching my_sim_world.yaml & my_sim_world.pgm (640x640 px):
  // - resolution: 0.05 m/px
  // - origin: [-16.0, -16.0, 0.0]
  // - map dimensions: 640x640 px (32.0m x 32.0m)
  // - Real-world span: X in [-16.0m, +16.0m], Y in [-16.0m, +16.0m]
  // - Standard ROS to Canvas Transformation:
  //   ix = (rx - (-16.0)) / 32.0 = (rx + 16.0) / 32.0
  //   iy = (16.0 - ry) / 32.0  (Y inverted because Canvas Y=0 is at Top)
  Offset _mapMetersToPixel(double rx, double ry) {
    const double xMin = -16.0;
    const double xMax = 16.0;
    const double yMin = -16.0;
    const double yMax = 16.0;

    double ix = (rx - xMin) / (xMax - xMin);
    double iy = (yMax - ry) / (yMax - yMin);

    return Offset(ix.clamp(0.0, 1.0), iy.clamp(0.0, 1.0));
  }

  Future<void> _togglePlannedPath() async {
    if (_showRosPath) {
      setState(() {
        _showRosPath = false;
        _rosPath = [];
      });
      return;
    }

    setState(() {
      _isFetchingPath = true;
      _showRosPath = true;
    });

    try {
      await _fetchRosPathSilently();
      setState(() {
        _isFetchingPath = false;
      });
    } catch (e) {
      setState(() {
        _isFetchingPath = false;
        _showRosPath = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading Turtlebot path: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'free':
        return 'Free / Idle';
      case 'en_route_to_pickup':
        return 'En Route to Pickup';
      case 'en_route_to_dropoff':
        return 'En Route to Dropoff';
      case 'returning':
        return 'Returning Home';
      default:
        return status.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    if (status == 'free') {
      return const Color(0xFF4ADE80);
    } else if (status == 'returning') {
      return Colors.orangeAccent;
    } else {
      return const Color(0xFFFF8A50);
    }
  }

  void _showCameraDialog() {
    final String streamUrl = '${_apiService.baseUrl}/robot/camera_stream';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: kNavyMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.videocam_rounded, color: kAccent, size: 22),
              SizedBox(width: 8),
              Text(
                'Live Robot Camera',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Container(
            width: 480,
            height: 270,
            decoration: BoxDecoration(
              color: kNavyDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: createWebCameraStream(streamUrl, 480, 270),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: kAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final robotOffset = _mapMetersToPixel(_robotX, _robotY);

    return Scaffold(
      backgroundColor: kNavyDark,
      appBar: AppBar(
        title: const Text('Live Robot Telemetry'),
        backgroundColor: kNavyMid,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  // 1. Telemetry Parameter Panel (Left)
                  Container(
                    width: 340,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: kNavyMid,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Robot Status Parameters',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        
                        // Status Card Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _getStatusColor(_robotStatus).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _getStatusColor(_robotStatus), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.circle, color: _getStatusColor(_robotStatus), size: 12),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formatStatus(_robotStatus),
                                  style: TextStyle(color: _getStatusColor(_robotStatus), fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Coordinates Display
                        const Text(
                          'Odometry Pose (Real-time)',
                          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildParameterTile('X coordinate', '${_robotX.toStringAsFixed(3)} m'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildParameterTile('Y coordinate', '${_robotY.toStringAsFixed(3)} m'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Queue parameter
                        _buildParamRow(Icons.format_list_numbered_rounded, 'Queue Length', '$_queueLength orders'),
                        const SizedBox(height: 12),
                        _buildParamRow(Icons.battery_std_rounded, 'Battery Level', '78% (Static)'),
                        
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 12),
                        
                        // Active Delivery Details Card (Pickup, Dropoff, Sender, Recipient)
                        _buildActiveDeliveryCard(),

                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 12),
                        
                        // ==========================================
                        // THE 2 MAIN OPERATIONS OPTIONS (ONLY CAMERA & PLAN)
                        // ==========================================
                        const Text(
                          'Operations Control',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        
                        // OPTION 1: Open Camera
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kNavyDark,
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.videocam_rounded, color: kAccent, size: 18),
                            label: const Text('Open Camera'),
                            onPressed: _showCameraDialog,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // OPTION 2: Planned Path Toggle (Linked to RViz /plan topic)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _showRosPath ? kAccent.withOpacity(0.15) : kNavyDark,
                              foregroundColor: Colors.white,
                              side: BorderSide(color: _showRosPath ? kAccent : Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: Icon(
                              _showRosPath ? Icons.navigation_rounded : Icons.navigation_outlined,
                              color: _showRosPath ? kAccent : Colors.white54,
                              size: 18,
                            ),
                            label: Text(_isFetchingPath ? 'Fetching...' : 'Planned Path'),
                            onPressed: _isFetchingPath ? null : _togglePlannedPath,
                          ),
                        ),

                        
                        const Spacer(),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.link, color: kAccent, size: 16),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'WSL RViz & ROS 2 Linked',
                                style: TextStyle(color: kAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  
                  // 2. Interactive Floor Plan Live View (Right)
                  Expanded(
                    child: Container(
                      key: _mapKey,
                      decoration: BoxDecoration(
                        color: kNavyMid.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            // Interactive Pan & Zoom Area
                            InteractiveViewer(
                              transformationController: _transformationController,
                              minScale: 0.5,
                              maxScale: 5.0,
                              boundaryMargin: const EdgeInsets.all(120),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final double boxWidth = constraints.maxWidth;
                                  final double boxHeight = constraints.maxHeight;

                                  // my_sim_world map aspect ratio (640x640 square = 1.0)
                                  const double imgAspect = 1.0;
                                  double imgW = boxWidth;
                                  double imgH = boxHeight;
                                  double offsetX = 0.0;
                                  double offsetY = 0.0;

                                  if (boxWidth / boxHeight > imgAspect) {
                                    imgH = boxHeight;
                                    imgW = boxHeight * imgAspect;
                                    offsetX = (boxWidth - imgW) / 2.0;
                                  } else {
                                    imgW = boxWidth;
                                    imgH = boxWidth / imgAspect;
                                    offsetY = (boxHeight - imgH) / 2.0;
                                  }

                                  final double iconLeft = offsetX + (robotOffset.dx * imgW) - 20;
                                  final double iconTop = offsetY + (robotOffset.dy * imgH) - 20;

                                  return Stack(
                                    children: [
                                      // Background floor plan map image (my_sim_world 2D SLAM grid map: origin [-16, -16], 640x640 px, 0.05m/px)
                                      Positioned.fill(
                                        child: Image.asset(
                                          _currentMapAsset,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Image.asset(
                                              'assets/images/floor_plan.png',
                                              fit: BoxFit.contain,
                                            );
                                          },
                                        ),
                                      ),

                                      // Plot Turtlebot ROS Path (Solid Neon Teal)
                                      if (_showRosPath && _rosPath.isNotEmpty)
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: PathPainter(
                                              _rosPath,
                                              kAccent,
                                              offsetX: offsetX,
                                              offsetY: offsetY,
                                              imgW: imgW,
                                              imgH: imgH,
                                            ),
                                          ),
                                        ),

                                      // Live moving Robot Icon with Pulse effect
                                      Positioned(
                                        left: iconLeft,
                                        top: iconTop,
                                        width: 40,
                                        height: 40,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Pulse ring overlay
                                            ScaleTransition(
                                              scale: _pulseAnimation,
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: kAccent.withOpacity(0.4), width: 2),
                                                  color: kAccent.withOpacity(0.08),
                                                ),
                                              ),
                                            ),
                                            
                                            // Robot avatar icon
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: kAccent,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: kAccent.withOpacity(0.5),
                                                    blurRadius: 10,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.smart_toy_rounded,
                                                color: kNavyDark,
                                                size: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),

                            // Floating Zoom & Pan Controls (In, Out, Reset)
                            _buildZoomControls(),
                          ],
                        ),
                      ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildParameterTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kNavyDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildParamRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildActiveDeliveryCard() {
    final order = _currentOrder;
    final String pickupRoom = order?['pickup_room_name'] ?? order?['pickup_room'] ?? 'Robot Room';
    final String dropoffRoom = order?['recipient_room_name'] ?? order?['dropoff_room'] ?? 'N/A';
    final String sender = order?['sender_name'] ?? order?['sender_account_name'] ?? 'System User';
    final String recipient = order?['recipient_name'] ?? 'N/A';
    final bool hasActiveOrder = order != null || (_robotStatus != 'free' && _robotStatus != 'returning');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kNavyDark.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasActiveOrder ? kAccent.withOpacity(0.4) : Colors.white10,
          width: hasActiveOrder ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_shipping_rounded,
                color: hasActiveOrder ? kAccent : Colors.white38,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Active Delivery Order',
                style: TextStyle(
                  color: hasActiveOrder ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasActiveOrder) ...[
            _buildDeliveryDetailRow(Icons.unarchive_rounded, 'Pickup', pickupRoom, Colors.green),
            const SizedBox(height: 6),
            _buildDeliveryDetailRow(Icons.archive_rounded, 'Dropoff', dropoffRoom, Colors.orangeAccent),
            const SizedBox(height: 6),
            _buildDeliveryDetailRow(Icons.person_rounded, 'Sender', sender, Colors.white70),
            const SizedBox(height: 6),
            _buildDeliveryDetailRow(Icons.person_pin_circle_rounded, 'Recipient', recipient, kAccent),
          ] else ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                'No active delivery in progress.',
                style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryDetailRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: kNavyDark.withOpacity(0.85),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              tooltip: 'Zoom In',
              onPressed: _zoomIn,
            ),
            const Divider(color: Colors.white10, height: 1),
            IconButton(
              icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 20),
              tooltip: 'Zoom Out',
              onPressed: _zoomOut,
            ),
            const Divider(color: Colors.white10, height: 1),
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded, color: kAccent, size: 20),
              tooltip: 'Reset View',
              onPressed: _resetZoom,
            ),
            const Divider(color: Colors.white10, height: 1),
            IconButton(
              icon: const Icon(Icons.palette_outlined, color: kAccent, size: 20),
              tooltip: 'Switch Map Style',
              onPressed: _cycleMapTheme,
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Painter to plot the calculated planning paths over the map image with exact letterbox offsets
class PathPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double offsetX;
  final double offsetY;
  final double imgW;
  final double imgH;

  PathPainter(
    this.points,
    this.color, {
    required this.offsetX,
    required this.offsetY,
    required this.imgW,
    required this.imgH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    double startX = offsetX + (points[0].dx * imgW);
    double startY = offsetY + (points[0].dy * imgH);
    path.moveTo(startX, startY);

    for (int i = 1; i < points.length; i++) {
      double px = offsetX + (points[i].dx * imgW);
      double py = offsetY + (points[i].dy * imgH);
      path.lineTo(px, py);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PathPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.offsetX != offsetX ||
      oldDelegate.offsetY != offsetY;
}
