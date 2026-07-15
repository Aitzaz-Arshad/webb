// lib/screens/user_dashboard_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_planning/providers/auth_provider.dart';
import 'package:path_planning/api/api_service.dart';
import 'login_screen.dart';
import 'new_delivery_screen.dart';
import 'deliveries_log_screen.dart';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6);

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _activeDeliveries = [];
  bool _isLoadingRobotStatus = false;
  bool _isHoveringRobot = false;
  
  String _robotStatus = 'free';
  Map<String, dynamic>? _currentRobotOrder;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadRobotStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadRobotStatusSilent());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRobotStatus() async {
    setState(() {
      _isLoadingRobotStatus = true;
    });

    try {
      final inTransit = await _apiService.getDeliveries(status: 'in_transit');
      final pickedUp = await _apiService.getDeliveries(status: 'picked_up');
      final seen = <int>{};
      final active = <dynamic>[];
      for (final delivery in [...inTransit, ...pickedUp]) {
        final id = delivery['id'] as int;
        if (seen.add(id)) active.add(delivery);
      }

      final statusResponse = await _apiService.getRobotStatus();
      final status = statusResponse['status'] ?? 'free';
      final currentOrder = statusResponse['current_order'] as Map<String, dynamic>?;

      setState(() {
        _activeDeliveries = active;
        _robotStatus = status;
        _currentRobotOrder = currentOrder;
      });
    } catch (e) {
      print('Error loading robot status: $e');
    } finally {
      setState(() {
        _isLoadingRobotStatus = false;
      });
    }
  }

  Future<void> _loadRobotStatusSilent() async {
    try {
      final inTransit = await _apiService.getDeliveries(status: 'in_transit');
      final pickedUp = await _apiService.getDeliveries(status: 'picked_up');
      final seen = <int>{};
      final active = <dynamic>[];
      for (final delivery in [...inTransit, ...pickedUp]) {
        final id = delivery['id'] as int;
        if (seen.add(id)) active.add(delivery);
      }

      final statusResponse = await _apiService.getRobotStatus();
      final status = statusResponse['status'] ?? 'free';
      final currentOrder = statusResponse['current_order'] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _activeDeliveries = active;
          _robotStatus = status;
          _currentRobotOrder = currentOrder;
        });
      }
    } catch (e) {
      // Silent catch for periodic updates
    }
  }

  Future<void> _refreshAll() async {
    await _loadRobotStatus();
  }

  Map<String, dynamic>? get _currentActiveDelivery {
    if (_activeDeliveries.isEmpty) return null;
    return _activeDeliveries.first as Map<String, dynamic>;
  }

  bool get _isRobotBusy => _robotStatus != 'free' && _robotStatus != 'returning';

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: kNavyDark,
      appBar: AppBar(
        title: const Text('ParcelPath User Portal'),
        backgroundColor: kNavyMid,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _refreshAll,
          ),
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
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${auth.userName ?? "Student"} 👋',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Request automated delivery tasks and track execution status.',
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 14),
            ),
            const SizedBox(height: 28),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildActionButtons(context),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: _buildRobotStatusCard(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const NewDeliveryScreen()),
            );
            if (result == true) {
              _refreshAll();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccent,
            foregroundColor: kNavyDark,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            elevation: 6,
            shadowColor: kAccent.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.smart_toy_rounded, color: kNavyDark, size: 32),
              SizedBox(width: 16),
              Text(
                'Request New Delivery',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const DeliveriesLogScreen()),
            );
          },
          icon: Icon(Icons.history_rounded, color: Colors.white.withOpacity(0.85), size: 20),
          label: const Text(
            'Delivery History Log',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.35), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: kNavyMid.withOpacity(0.2),
          ),
        ),
      ],
    );
  }

  Widget _buildRobotStatusCard() {
    final active = _currentActiveDelivery;
    final isBusy = _isRobotBusy;
    final statusColor = isBusy ? const Color(0xFFFF8A50) : const Color(0xFF4ADE80);
    final statusLabel = isBusy ? 'Busy' : 'Free';
    final destinationRoom = _currentRobotOrder != null
        ? _currentRobotOrder!['dropoff_room']
        : (active != null
            ? (active['recipient_room_name'] ?? 'Room ${active['recipient_room_id']}')
            : null);

    return Card(
      color: kNavyMid,
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: statusColor.withOpacity(0.35),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _isLoadingRobotStatus
            ? const Center(
                child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.5),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringRobot = true),
                    onExit: (_) => setState(() => _isHoveringRobot = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _isHoveringRobot
                                ? kAccent.withOpacity(0.45)
                                : Colors.transparent,
                            blurRadius: _isHoveringRobot ? 24.0 : 0.0,
                            spreadRadius: _isHoveringRobot ? 3.0 : 0.0,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/images/delivery_robot.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Robot Status',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: statusColor, width: 1.5),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.battery_charging_full_rounded,
                        size: 15,
                        color: Colors.white.withOpacity(0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '78%',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (isBusy && destinationRoom != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.room_rounded,
                          size: 16,
                          color: Colors.white.withOpacity(0.45),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Delivering to $destinationRoom',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
