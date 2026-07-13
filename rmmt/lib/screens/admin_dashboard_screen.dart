import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_planning/providers/auth_provider.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'deliveries_log_screen.dart';
import 'user_management_screen.dart';
import 'room_editor_screen.dart';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6);

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: kNavyDark,
      appBar: AppBar(
        title: const Text('Admin Operations Hub'),
        backgroundColor: kNavyMid,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, ${auth.userName ?? "Admin"} 👋',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Control system, map rooms, and monitor fleet parameters.',
                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 14),
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;

                  // Define the 5 redesigned dashboard cards
                  final liveTelemetry = AdminDashboardCard(
                    title: 'Live Telemetry',
                    description: 'Monitor robot sensors, real-time feedback loops, and network status parameters.',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Robot telemetry link active. Open Path Planner to view live paths.')),
                      );
                    },
                    painterBuilder: (color) => TelemetryPainter(color: color),
                  );

                  final floorPlanEditor = AdminDashboardCard(
                    title: '2D Floor Plan Editor',
                    description: 'Overlay room bounding boundaries on the static building floor plan blueprint.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const RoomEditorScreen()),
                      );
                    },
                    painterBuilder: (color) => FloorPlanPainter(color: color),
                  );

                  final deliveryLogs = AdminDashboardCard(
                    title: 'Delivery Logs',
                    description: 'Verify system logs of historical deliveries and request dispatch updates.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const DeliveriesLogScreen()),
                      );
                    },
                    painterBuilder: (color) => LogsPainter(color: color),
                  );

                  final userDirectory = AdminDashboardCard(
                    title: 'User Directory',
                    description: 'Manage registered student accounts and allocate operational authority credentials.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const UserManagementScreen()),
                      );
                    },
                    painterBuilder: (color) => UserDirectoryPainter(color: color),
                  );

                  final pathPlanner = AdminDashboardCard(
                    title: 'Path Planner',
                    description: 'Configure navigation routes, room connections, and path-planning parameters.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const MainScreen()),
                      );
                    },
                    painterBuilder: (color) => PathPlannerPainter(color: color),
                  );

                  if (isWide) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: liveTelemetry),
                            const SizedBox(width: 18),
                            Expanded(child: floorPlanEditor),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(child: deliveryLogs),
                            const SizedBox(width: 18),
                            Expanded(child: userDirectory),
                            const SizedBox(width: 18),
                            Expanded(child: pathPlanner),
                          ],
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        liveTelemetry,
                        const SizedBox(height: 16),
                        floorPlanEditor,
                        const SizedBox(height: 16),
                        deliveryLogs,
                        const SizedBox(height: 16),
                        userDirectory,
                        const SizedBox(height: 16),
                        pathPlanner,
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminDashboardCard extends StatefulWidget {
  final String title;
  final String description;
  final CustomPainter Function(Color) painterBuilder;
  final VoidCallback onTap;

  const AdminDashboardCard({
    super.key,
    required this.title,
    required this.description,
    required this.painterBuilder,
    required this.onTap,
  });

  @override
  State<AdminDashboardCard> createState() => _AdminDashboardCardState();
}

class _AdminDashboardCardState extends State<AdminDashboardCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _isHovered ? 1.025 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 250,
          decoration: BoxDecoration(
            color: kNavyMid,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? kAccent.withOpacity(0.8) : Colors.white10,
              width: _isHovered ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? kAccent.withOpacity(0.25) : Colors.black.withOpacity(0.2),
                blurRadius: _isHovered ? 16 : 8,
                spreadRadius: _isHovered ? 2 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Illustration visual focus
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: CustomPaint(
                          painter: widget.painterBuilder(
                            _isHovered ? kAccent : kAccent.withOpacity(0.65),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Module Title
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    // Short Description (1-2 lines)
                    Text(
                      widget.description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 12),
                    // Open Module Action with hover sliding effect
                    AnimatedPadding(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.only(left: _isHovered ? 12.0 : 0.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Open Module',
                            style: TextStyle(
                              color: _isHovered ? kAccent : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13.5,
                            color: _isHovered ? kAccent : Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 1. Live Telemetry Illustration Painter (Radar, Waves, Sensors)
class TelemetryPainter extends CustomPainter {
  final Color color;
  TelemetryPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    // Center transceiver unit
    canvas.drawCircle(center, 10, paint);

    // Radar crosshairs (background lines)
    final gridPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - 60, center.dy), Offset(center.dx + 60, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 40), Offset(center.dx, center.dy + 40), gridPaint);

    // Concentric sweep rings
    paint.strokeWidth = 1.0;
    canvas.drawCircle(center, 22, paint);

    // Arcs representing wireless telemetry transmission pulses
    paint.strokeWidth = 1.8;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 34),
      -0.65 * 3.14,
      1.3 * 3.14,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 46),
      -0.45 * 3.14,
      0.9 * 3.14,
      false,
      paint,
    );

    // Sensor point indicators
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx + 24, center.dy - 24), 2.5, fillPaint);
    canvas.drawCircle(Offset(center.dx - 32, center.dy + 12), 2.0, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 2. 2D Floor Plan Editor Illustration Painter (Blueprint walls, intersections)
class FloorPlanPainter extends CustomPainter {
  final Color color;
  FloorPlanPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.12)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Technical drafting grid lines
    final step = 15.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Outer layout boundaries
    paint.color = color;
    paint.strokeWidth = 1.8;
    final wMargin = size.width * 0.15;
    final hMargin = size.height * 0.1;
    final rect = Rect.fromLTRB(wMargin, hMargin, size.width - wMargin, size.height - hMargin);
    canvas.drawRect(rect, paint);

    // Interior walls layout
    canvas.drawLine(Offset(size.width * 0.5, hMargin), Offset(size.width * 0.5, size.height - hMargin), paint);
    canvas.drawLine(Offset(wMargin, size.height * 0.5), Offset(size.width * 0.5, size.height * 0.5), paint);
    canvas.drawLine(Offset(size.width * 0.5, size.height * 0.4), Offset(size.width - wMargin, size.height * 0.4), paint);

    // Dash room boundaries representation
    paint.color = color.withOpacity(0.5);
    paint.strokeWidth = 1.2;
    double startY = size.height * 0.4 + 10;
    double endY = size.height - hMargin - 10;
    double targetX = size.width * 0.72;
    while (startY < endY) {
      canvas.drawLine(Offset(targetX, startY), Offset(targetX, startY + 4), paint);
      startY += 8;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 3. Delivery Logs Illustration Painter (3D package box)
class LogsPainter extends CustomPainter {
  final Color color;
  LogsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8;

    final cx = size.width / 2;
    final cy = size.height / 2 + 5;

    // Isometric coordinates
    final topPoint = Offset(cx, cy - 24);
    final leftPoint = Offset(cx - 26, cy - 11);
    final rightPoint = Offset(cx + 26, cy - 11);
    final bottomPoint = Offset(cx, cy + 2);

    final botLeft = Offset(cx - 26, cy + 14);
    final botRight = Offset(cx + 26, cy + 14);
    final botCenter = Offset(cx, cy + 27);

    // Top face
    paint.style = PaintingStyle.stroke;
    final pathTop = Path()
      ..moveTo(topPoint.dx, topPoint.dy)
      ..lineTo(rightPoint.dx, rightPoint.dy)
      ..lineTo(bottomPoint.dx, bottomPoint.dy)
      ..lineTo(leftPoint.dx, leftPoint.dy)
      ..close();
    canvas.drawPath(pathTop, paint);

    // Bottom structural vertical lines
    canvas.drawLine(leftPoint, botLeft, paint);
    canvas.drawLine(rightPoint, botRight, paint);
    canvas.drawLine(bottomPoint, botCenter, paint);

    // Bottom base walls
    canvas.drawLine(botLeft, botCenter, paint);
    canvas.drawLine(botRight, botCenter, paint);

    // Decorative packaging tape details
    paint.color = color.withOpacity(0.55);
    paint.strokeWidth = 1.2;
    canvas.drawLine(
      Offset((topPoint.dx + leftPoint.dx) / 2, (topPoint.dy + leftPoint.dy) / 2),
      Offset((bottomPoint.dx + rightPoint.dx) / 2, (bottomPoint.dy + rightPoint.dy) / 2),
      paint,
    );
    canvas.drawLine(
      Offset((leftPoint.dx + bottomPoint.dx) / 2, (leftPoint.dy + bottomPoint.dy) / 2),
      Offset((leftPoint.dx + bottomPoint.dx) / 2, (leftPoint.dy + bottomPoint.dy) / 2 + 25),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 4. User Directory Illustration Painter (Hierarchical user profiles structure)
class UserDirectoryPainter extends CustomPainter {
  final Color color;
  UserDirectoryPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2 + 5;

    // Draw central main admin user silhouette
    _drawProfile(canvas, Offset(cx, cy - 8), 10, 24, paint);

    // Draw left secondary user silhouette
    paint.color = color.withOpacity(0.5);
    _drawProfile(canvas, Offset(cx - 28, cy + 2), 8, 18, paint);

    // Draw right tertiary user silhouette
    _drawProfile(canvas, Offset(cx + 28, cy + 2), 8, 18, paint);

    // Draw hierarchical connecting arcs to indicate structural directory
    paint.color = color.withOpacity(0.25);
    paint.strokeWidth = 1.0;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy + 2), radius: 40),
      3.14,
      3.14,
      false,
      paint,
    );
  }

  void _drawProfile(Canvas canvas, Offset center, double headRad, double bodyWidth, Paint paint) {
    // Head circle
    canvas.drawCircle(Offset(center.dx, center.dy - headRad - 2), headRad, paint);

    // Shoulders base
    final rect = Rect.fromLTRB(
      center.dx - bodyWidth / 2,
      center.dy - 1,
      center.dx + bodyWidth / 2,
      center.dy + 12,
    );
    canvas.drawArc(rect, 3.14, 3.14, false, paint);
    canvas.drawLine(
      Offset(center.dx - bodyWidth / 2, center.dy + 5),
      Offset(center.dx + bodyWidth / 2, center.dy + 5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 5. Path Planner Illustration Painter (Nodes networks, connected active path)
class PathPlannerPainter extends CustomPainter {
  final Color color;
  PathPlannerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Define topology node points
    final n1 = Offset(cx - 38, cy + 12);
    final n2 = Offset(cx - 16, cy - 18);
    final n3 = Offset(cx + 16, cy + 10);
    final n4 = Offset(cx + 38, cy - 14);

    // Draw background routes lines
    canvas.drawLine(n1, n3, paint);
    canvas.drawLine(n2, n4, paint);

    // Highlight planned navigation route
    paint.color = color;
    paint.strokeWidth = 2.2;
    final activePath = Path()
      ..moveTo(n1.dx, n1.dy)
      ..lineTo(n2.dx, n2.dy)
      ..lineTo(n3.dx, n3.dy)
      ..lineTo(n4.dx, n4.dy);
    canvas.drawPath(activePath, paint);

    // Draw node vertices
    final bgPaint = Paint()
      ..color = kNavyMid
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final nodes = [n1, n2, n3, n4];
    for (final node in nodes) {
      canvas.drawCircle(node, 4.5, bgPaint);
      canvas.drawCircle(node, 4.5, borderPaint);
      canvas.drawCircle(node, 1.8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
