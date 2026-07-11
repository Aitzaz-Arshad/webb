import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'login_screen.dart';

// ---- Brand tokens -----------------------------------------------------
// Swap kAppName for your project's real name/title.
const String kAppName = 'ParcelPath';
const String kAppTagline = 'Autonomous indoor delivery, planned in real time';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6); // signal / tracking cyan
const Color kAccentDim = Color(0xFF1A8F7D);
// ------------------------------------------------------------------------

class StartingScreen extends StatefulWidget {
  const StartingScreen({super.key});

  @override
  State<StartingScreen> createState() => _StartingScreenState();
}

class _StartingScreenState extends State<StartingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Animation<double> _stagger(double start, double end) {
    return CurvedAnimation(
      parent: _entry,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Widget _fadeSlide(Animation<double> anim, Widget child) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * 18),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final badgeAnim = _stagger(0.0, 0.45);
    final iconAnim = _stagger(0.10, 0.55);
    final titleAnim = _stagger(0.20, 0.65);
    final taglineAnim = _stagger(0.30, 0.75);
    final chipsAnim = _stagger(0.40, 0.85);
    final buttonAnim = _stagger(0.55, 1.0);

    return Scaffold(
      backgroundColor: kNavyDark,
      body: Stack(
        children: [
          // Background gradient + floor-plan grid motif
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kNavyMid, kNavyDark],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _FloorGridPainter()),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _fadeSlide(badgeAnim, const _EyebrowBadge()),
                    const SizedBox(height: 36),
                    _fadeSlide(
                      iconAnim,
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => CustomPaint(
                          painter: _PulseRingPainter(_pulse.value),
                          child: const SizedBox(
                            width: 152,
                            height: 152,
                            child: _RobotBadge(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),
                    _fadeSlide(
                      titleAnim,
                      Text(
                        kAppName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _fadeSlide(
                      taglineAnim,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          kAppTagline,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.5,
                            color: Colors.white.withOpacity(0.65),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    _fadeSlide(
                      chipsAnim,
                      const Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatusChip(
                            icon: Icons.sensors_rounded,
                            label: 'LoRa Linked',
                          ),
                          _StatusChip(
                            icon: Icons.my_location_rounded,
                            label: 'Live Tracking',
                          ),
                          _StatusChip(
                            icon: Icons.route_rounded,
                            label: 'Auto-Routing',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    _fadeSlide(
                      buttonAnim,
                      _StartButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 28),
                    _fadeSlide(
                      buttonAnim,
                      Text(
                        'FINAL YEAR PROJECT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                          color: Colors.white.withOpacity(0.28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Pieces -------------------------------------------------------------

class _EyebrowBadge extends StatelessWidget {
  const _EyebrowBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: kAccent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(20),
        color: kAccent.withOpacity(0.08),
      ),
      child: const Text(
        'INDOOR DELIVERY ROBOT',
        style: TextStyle(
          color: kAccent,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _RobotBadge extends StatelessWidget {
  const _RobotBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kAccent, kAccentDim],
          ),
          boxShadow: [
            BoxShadow(
              color: kAccent.withOpacity(0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.smart_toy_rounded,
          size: 58,
          color: kNavyDark,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kAccent),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.85),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _StartButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent,
          foregroundColor: kNavyDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Start Delivering',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---- Painters -------------------------------------------------------------

/// Faint dot-grid suggesting an indoor floor plan / occupancy grid.
class _FloorGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Expanding pulse ring behind the robot badge, like a signal ping.
class _PulseRingPainter extends CustomPainter {
  final double t; // 0..1

  _PulseRingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (final phase in [0.0, 0.5]) {
      final localT = (t + phase) % 1.0;
      final radius = 46 + localT * (maxRadius - 46);
      final opacity = (1 - localT) * 0.35;
      final paint = Paint()
        ..color = kAccent.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) =>
      oldDelegate.t != t;
}