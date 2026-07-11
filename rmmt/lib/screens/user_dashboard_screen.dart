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
  bool _isLoading = false;
  String? _statusFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final Set<int> _expandedIds = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMyDeliveries();
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
            onPressed: _loadMyDeliveries,
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const NewDeliveryScreen()),
                      );
                      if (result == true) {
                        _loadMyDeliveries();
                      }
                    },
                    icon: const Icon(Icons.add_shopping_cart_rounded, color: kNavyDark),
                    label: const Text(
                      'Request New Delivery',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: kNavyDark,
                      minimumSize: const Size(120, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          0.0,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    icon: const Icon(Icons.history_rounded, color: kAccent),
                    label: const Text(
                      'View Delivery History',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: kAccent, width: 1.5),
                      minimumSize: const Size(120, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 36),
            const Text(
              'My Delivery Requests',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
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
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: kAccent),
                    )
                  : _myDeliveries.isEmpty
                      ? Center(
                          child: Text(
                            'No delivery requests submitted yet.',
                            style: TextStyle(color: Colors.white.withOpacity(0.4)),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _myDeliveries.length,
                          itemBuilder: (context, index) {
                            final delivery = _myDeliveries[index];
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
                          },
                        ),
            ),
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
