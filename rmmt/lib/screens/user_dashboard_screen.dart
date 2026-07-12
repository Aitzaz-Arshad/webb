// lib/screens/user_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_planning/providers/auth_provider.dart';
import 'package:path_planning/api/api_service.dart';
import 'login_screen.dart';
import 'new_delivery_screen.dart';

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
  List<dynamic> _myDeliveries = [];
  List<dynamic> _activeDeliveries = [];
  bool _isLoading = false;
  bool _isLoadingRobotStatus = false;
  String? _statusFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final Set<int> _expandedIds = {};
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _historySectionKey = GlobalKey();
  bool _showHistory = false;
  bool _isHoveringRobot = false;

  @override
  void initState() {
    super.initState();
    _loadMyDeliveries();
    _loadRobotStatus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  Future<void> _loadMyDeliveries() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.userId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final list = await _apiService.getDeliveries(
        requesterId: auth.userId,
        requesterRole: auth.userRole,
        senderId: auth.userId,
        status: _statusFilter,
        dateFrom: _dateFrom != null ? _formatDate(_dateFrom!) : null,
        dateTo: _dateTo != null ? _formatDate(_dateTo!) : null,
      );
      setState(() {
        _myDeliveries = list;
      });
    } catch (e) {
      print('Error loading deliveries: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
      setState(() {
        _activeDeliveries = active;
      });
    } catch (e) {
      print('Error loading robot status: $e');
    } finally {
      setState(() {
        _isLoadingRobotStatus = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadMyDeliveries(), _loadRobotStatus()]);
  }

  void _scrollToHistory() {
    final context = _historySectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleHistory() {
    setState(() {
      _showHistory = !_showHistory;
    });
    if (_showHistory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHistory();
      });
    }
  }

  Map<String, dynamic>? get _currentActiveDelivery {
    if (_activeDeliveries.isEmpty) return null;
    return _activeDeliveries.first as Map<String, dynamic>;
  }

  bool get _isRobotBusy => _activeDeliveries.isNotEmpty;

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orangeAccent;
      case 'picked_up':
        return Colors.blueAccent;
      case 'in_transit':
        return Colors.purpleAccent;
      case 'delivered':
        return Colors.greenAccent;
      case 'failed':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

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
            if (_showHistory) ...[
              const SizedBox(height: 36),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KeyedSubtree(
                        key: _historySectionKey,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'My Delivery Requests',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white70),
                              tooltip: 'Close History',
                              onPressed: () {
                                setState(() {
                                  _showHistory = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _statusFilter,
                    dropdownColor: kNavyMid,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Filter Status',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                      fillColor: kNavyMid,
                      filled: true,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: kAccent),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Deliveries')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'picked_up', child: Text('Picked Up')),
                      DropdownMenuItem(value: 'in_transit', child: Text('In Transit')),
                      DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                      DropdownMenuItem(value: 'failed', child: Text('Failed')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _statusFilter = val;
                      });
                      _loadMyDeliveries();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: kNavyMid,
                    ),
                    icon: const Icon(Icons.date_range_rounded, color: kAccent, size: 18),
                    label: Text(
                      _dateFrom == null
                          ? 'Start Date'
                          : _formatDate(_dateFrom!),
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateFrom ?? DateTime.now(),
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: kAccent,
                                onPrimary: kNavyDark,
                                surface: kNavyMid,
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _dateFrom = picked;
                        });
                        _loadMyDeliveries();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: kNavyMid,
                    ),
                    icon: const Icon(Icons.date_range_rounded, color: kAccent, size: 18),
                    label: Text(
                      _dateTo == null
                          ? 'End Date'
                          : _formatDate(_dateTo!),
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateTo ?? DateTime.now(),
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: kAccent,
                                onPrimary: kNavyDark,
                                surface: kNavyMid,
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _dateTo = picked;
                        });
                        _loadMyDeliveries();
                      }
                    },
                  ),
                ),
                if (_dateFrom != null || _dateTo != null || _statusFilter != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _dateFrom = null;
                        _dateTo = null;
                        _statusFilter = null;
                      });
                      _loadMyDeliveries();
                    },
                  )
                ]
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: CircularProgressIndicator(color: kAccent),
                ),
              )
            else if (_myDeliveries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'No delivery requests submitted yet.',
                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                  ),
                ),
              )
            else
              ..._myDeliveries.map((delivery) {
                final status = delivery['status'] as String;
                final deliveryId = delivery['id'] as int;
                final bool isExpanded = _expandedIds.contains(deliveryId);

                return Card(
                  color: kNavyMid,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    title: Text(
                      'Delivery #${delivery['id']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          'To: ${delivery['recipient_name']} — ${delivery['recipient_room_name'] ?? 'Room ${delivery['recipient_room_id']}'}',
                          style: const TextStyle(
                            color: kAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              delivery['pickup_room_id'] == null
                                  ? Icons.home_rounded
                                  : Icons.room_rounded,
                              size: 14,
                              color: Colors.white30,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${delivery['pickup_room_name'] ?? "Robot Home"} ➔ ${delivery['recipient_room_name'] ?? "Room " + delivery['recipient_room_id'].toString()}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.55),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isExpanded) ...[
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 8),
                          _buildDetailRow('Recipient name', '${delivery['recipient_name']}'),
                          _buildDetailRow('Delivery Type', '${delivery['delivery_type'].toString().replaceAll('_', ' ').toUpperCase()}'),
                          _buildDetailRow('Pickup Location', '${delivery['pickup_room_name'] ?? 'Robot Charging Hub (Home)'}'),
                          _buildDetailRow('Destination Room', '${delivery['recipient_room_name'] ?? 'Room ' + delivery['recipient_room_id'].toString()}'),
                          _buildDetailRow('Created At', '${delivery['created_at'].toString().replaceAll('T', ' ').split('.')[0]}'),
                          _buildDetailRow('Delivered At', delivery['delivered_at'] != null ? '${delivery['delivered_at'].toString().replaceAll('T', ' ').split('.')[0]}' : 'In Progress'),
                        ]
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.15),
                        border: Border.all(
                          color: _getStatusColor(status),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: _getStatusColor(status),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedIds.remove(deliveryId);
                        } else {
                          _expandedIds.add(deliveryId);
                        }
                      });
                    },
                  ),
                );
              }),
                    ],
                  ),
                ),
              ),
            ],
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
              Icon(Icons.local_shipping_rounded, color: kNavyDark, size: 32),
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
          onPressed: _toggleHistory,
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
    final statusLabel = isBusy ? 'Busy — In Delivery' : 'Free';
    final destinationRoom = active != null
        ? (active['recipient_room_name'] ?? 'Room ${active['recipient_room_id']}')
        : null;

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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
