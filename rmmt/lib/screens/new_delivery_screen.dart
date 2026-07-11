// lib/screens/new_delivery_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_planning/providers/auth_provider.dart';
import 'package:path_planning/api/api_service.dart';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6);

class NewDeliveryScreen extends StatefulWidget {
  const NewDeliveryScreen({super.key});

  @override
  State<NewDeliveryScreen> createState() => _NewDeliveryScreenState();
}

class _NewDeliveryScreenState extends State<NewDeliveryScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _recipientNameController = TextEditingController();

  List<dynamic> _rooms = [];
  bool _isLoadingRooms = false;
  bool _isSubmitting = false;

  String _deliveryType = 'home_to_room'; // 'home_to_room' or 'room_to_room'
  int? _selectedRecipientRoomId;
  int? _selectedPickupRoomId;
  int? _hoveredRoomId;

  bool _isScheduled = false;
  DateTime? _scheduledDateTime;

  @override
  void dispose() {
    _recipientNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _isLoadingRooms = true;
    });

    try {
      // Fetch public room geometries
      final list = await _apiService.getRooms(public: true);
      setState(() {
        _rooms = list;
      });
    } catch (e) {
      print('Failed to load rooms: $e');
    } finally {
      setState(() {
        _isLoadingRooms = false;
      });
    }
  }

  void _handleRoomTap(int roomId) {
    if (_deliveryType == 'home_to_room') {
      setState(() {
        _selectedRecipientRoomId = roomId;
      });
    } else {
      // Room-to-room selection logic
      setState(() {
        if (_selectedPickupRoomId == null) {
          _selectedPickupRoomId = roomId;
        } else if (_selectedPickupRoomId == roomId) {
          // Deselect pickup
          _selectedPickupRoomId = null;
        } else if (_selectedRecipientRoomId == null) {
          _selectedRecipientRoomId = roomId;
        } else if (_selectedRecipientRoomId == roomId) {
          // Deselect recipient
          _selectedRecipientRoomId = null;
        } else {
          // Both selected, change recipient
          _selectedRecipientRoomId = roomId;
        }
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedPickupRoomId = null;
      _selectedRecipientRoomId = null;
    });
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRecipientRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a destination room on the floor plan.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_deliveryType == 'room_to_room' && _selectedPickupRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a pickup room on the floor plan.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_isScheduled) {
      if (_scheduledDateTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a scheduled date and time.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (_scheduledDateTime!.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheduled time must be in the future.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.userId == null) return;

    final recipientName = _recipientNameController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _apiService.createDelivery(
        auth.userId!,
        _selectedRecipientRoomId!,
        _deliveryType == 'room_to_room' ? _selectedPickupRoomId : null,
        _deliveryType,
        recipientName,
        scheduledAt: _isScheduled ? _scheduledDateTime : null,
      );

      if (mounted) {
        final confirmMessage = _isScheduled
            ? 'Delivery scheduled for ${_scheduledDateTime.toString().split('.')[0]}!'
            : 'Delivery request submitted successfully!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(confirmMessage),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    // Filter rooms for interactive display (Robot Home is never selectable/glowing)
    final interactiveRooms = _rooms.where((r) => r['is_robot_home'] == false).toList();
    
    return Scaffold(
      backgroundColor: kNavyDark,
      appBar: AppBar(
        title: const Text('Request Robot Delivery'),
        backgroundColor: kNavyMid,
        elevation: 0,
      ),
      body: _isLoadingRooms
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  // 1. Interactive 2D Map (Left Side)
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kNavyMid,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Interactive Floor Plan',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_selectedPickupRoomId != null || _selectedRecipientRoomId != null)
                                TextButton.icon(
                                  onPressed: _clearSelection,
                                  icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.redAccent),
                                  label: const Text('Reset Selection', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final parentW = constraints.maxWidth;
                                final parentH = constraints.maxHeight;

                                return Stack(
                                  children: [
                                    // Floor plan image
                                    Positioned.fill(
                                      child: Image.asset(
                                        'assets/images/floor_plan.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    // Overlaid interactive room regions (excluding home)
                                    for (var room in interactiveRooms)
                                      _buildInteractiveRoomOverlay(room, parentW, parentH),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // 2. Delivery Options Form (Right Side)
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.only(left: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: kNavyMid,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Delivery Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Select rooms visually on the 2D floor plan layout.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13,
                              ),
                            ),
                            const Divider(color: Colors.white24, height: 32),

                            // Sender Name (Read-Only)
                            const Text(
                              'Sending as',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: kNavyDark.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.account_circle_rounded, color: kAccent, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    auth.userName ?? 'Anonymous User',
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Recipient Name Field
                            const Text(
                              'Recipient Name',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _recipientNameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: kNavyDark,
                                hintText: 'Enter recipient full name',
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.white10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: kAccent, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.redAccent),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Please enter recipient name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            
                            // Delivery Type Selection (Toggle)
                            const Text(
                              'Delivery Dispatch Type',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Home to Room'),
                                    selected: _deliveryType == 'home_to_room',
                                    selectedColor: kAccent,
                                    backgroundColor: kNavyDark,
                                    labelStyle: TextStyle(
                                      color: _deliveryType == 'home_to_room' ? kNavyDark : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _deliveryType = 'home_to_room';
                                          _clearSelection();
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Room to Room'),
                                    selected: _deliveryType == 'room_to_room',
                                    selectedColor: kAccent,
                                    backgroundColor: kNavyDark,
                                    labelStyle: TextStyle(
                                      color: _deliveryType == 'room_to_room' ? kNavyDark : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _deliveryType = 'room_to_room';
                                          _clearSelection();
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Dynamic Helper Instructions & Status Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kNavyDark.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Selection Status',
                                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 10),
                                  _buildSelectionStatusWidget(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Scheduling Section
                            const Text(
                              'Delivery Schedule',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Start Now'),
                                    selected: !_isScheduled,
                                    selectedColor: kAccent,
                                    backgroundColor: kNavyDark,
                                    labelStyle: TextStyle(
                                      color: !_isScheduled ? kNavyDark : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _isScheduled = false;
                                          _scheduledDateTime = null;
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Send Later'),
                                    selected: _isScheduled,
                                    selectedColor: kAccent,
                                    backgroundColor: kNavyDark,
                                    labelStyle: TextStyle(
                                      color: _isScheduled ? kNavyDark : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _isScheduled = true;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (_isScheduled) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white10),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  backgroundColor: kNavyDark,
                                ),
                                icon: const Icon(Icons.date_range_rounded, color: kAccent, size: 20),
                                label: Text(
                                  _scheduledDateTime == null
                                      ? 'Select Date & Time'
                                      : _scheduledDateTime.toString().split('.')[0],
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onPressed: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now().add(const Duration(minutes: 5)),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 30)),
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
                                  if (date == null) return;
                                  
                                  if (!mounted) return;
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))),
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
                                  if (time == null) return;
                                  
                                  setState(() {
                                    _scheduledDateTime = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      time.hour,
                                      time.minute,
                                    );
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 48),

                            // Submit Button
                            ElevatedButton.icon(
                              onPressed: _isSubmitting || !_isSelectionComplete() ? null : _submit,
                              icon: _isSubmitting 
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kNavyDark))
                                  : const Icon(Icons.local_shipping_rounded),
                              label: const Text('Request Transport'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAccent,
                                foregroundColor: kNavyDark,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
    );
  }

  Widget _buildInteractiveRoomOverlay(Map<String, dynamic> room, double parentWidth, double parentHeight) {
    final int roomId = room['id'] as int;
    
    // Check if room coordinates exist
    final double? labelX = room['label_x'] != null ? (room['label_x'] as num).toDouble() : null;
    final double? labelY = room['label_y'] != null ? (room['label_y'] as num).toDouble() : null;
    final double? regW = room['region_width'] != null ? (room['region_width'] as num).toDouble() : null;
    final double? regH = room['region_height'] != null ? (room['region_height'] as num).toDouble() : null;

    // Do not draw if not configured visually by admin
    if (labelX == null || labelY == null || regW == null || regH == null) {
      return const SizedBox.shrink();
    }

    final double left = labelX * parentWidth;
    final double top = labelY * parentHeight;
    final double width = regW * parentWidth;
    final double height = regH * parentHeight;

    final bool isPickup = _selectedPickupRoomId == roomId;
    final bool isRecipient = _selectedRecipientRoomId == roomId;
    final bool isHovered = _hoveredRoomId == roomId;

    Color highlightColor = Colors.transparent;
    Color borderColor = Colors.white12;
    double borderWidth = 1.0;

    if (isPickup) {
      highlightColor = Colors.green.withOpacity(0.24);
      borderColor = Colors.green;
      borderWidth = 2.0;
    } else if (isRecipient) {
      highlightColor = Colors.redAccent.withOpacity(0.24);
      borderColor = Colors.redAccent;
      borderWidth = 2.0;
    } else if (isHovered) {
      highlightColor = kAccent.withOpacity(0.18);
      borderColor = kAccent;
      borderWidth = 1.5;
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredRoomId = roomId),
        onExit: (_) => setState(() => _hoveredRoomId = null),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // Prevent choosing same room twice
            if (_deliveryType == 'room_to_room') {
              if (_selectedPickupRoomId == roomId && _selectedRecipientRoomId != null) {
                // Deselect pickup
                _handleRoomTap(roomId);
              } else if (_selectedPickupRoomId != null && _selectedPickupRoomId != roomId) {
                // Tapping destination
                _handleRoomTap(roomId);
              } else if (_selectedPickupRoomId == null) {
                // Tapping pickup
                _handleRoomTap(roomId);
              } else {
                // Prevent duplicate
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pickup and Destination rooms cannot be the same!')),
                );
              }
            } else {
              _handleRoomTap(roomId);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: highlightColor,
              border: Border.all(color: borderColor, width: borderWidth),
              borderRadius: BorderRadius.circular(6),
              boxShadow: (isHovered || isPickup || isRecipient) 
                  ? [
                      BoxShadow(
                        color: borderColor.withOpacity(0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    room['name'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: (isHovered || isPickup || isRecipient) ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (isPickup)
                  const Positioned(
                    bottom: 2,
                    left: 2,
                    child: Text('PICKUP', style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                if (isRecipient)
                  const Positioned(
                    bottom: 2,
                    left: 2,
                    child: Text('DEST', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionStatusWidget() {
    if (_deliveryType == 'home_to_room') {
      if (_selectedRecipientRoomId == null) {
        return const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: kAccent, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pickup from Robot Home is active. Tap a room on the floor plan to select it as the Destination.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          ],
        );
      } else {
        final destRoom = _rooms.firstWhere((r) => r['id'] == _selectedRecipientRoomId, orElse: () => null);
        final destName = destRoom != null ? destRoom['name'] : 'Room';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusLine('Pickup', 'Robot Charging Hub (Home)', Colors.purpleAccent),
            const SizedBox(height: 8),
            _buildStatusLine('Deliver to', destName, Colors.redAccent),
          ],
        );
      }
    } else {
      // Room to room status
      if (_selectedPickupRoomId == null) {
        return const Row(
          children: [
            Icon(Icons.touch_app_rounded, color: Colors.green, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tap a room on the floor plan to select it as the Pickup point.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          ],
        );
      } else if (_selectedRecipientRoomId == null) {
        final pickupRoom = _rooms.firstWhere((r) => r['id'] == _selectedPickupRoomId, orElse: () => null);
        final pickupName = pickupRoom != null ? pickupRoom['name'] : 'Room';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusLine('Pickup', pickupName, Colors.green),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.touch_app_rounded, color: Colors.redAccent, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap another room on the map to select the Destination.',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        );
      } else {
        final pickupRoom = _rooms.firstWhere((r) => r['id'] == _selectedPickupRoomId, orElse: () => null);
        final pickupName = pickupRoom != null ? pickupRoom['name'] : 'Room';
        final destRoom = _rooms.firstWhere((r) => r['id'] == _selectedRecipientRoomId, orElse: () => null);
        final destName = destRoom != null ? destRoom['name'] : 'Room';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusLine('Pickup', pickupName, Colors.green),
            const SizedBox(height: 8),
            _buildStatusLine('Deliver to', destName, Colors.redAccent),
          ],
        );
      }
    }
  }

  Widget _buildStatusLine(String label, String roomName, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        Expanded(
          child: Text(
            roomName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }

  bool _isSelectionComplete() {
    if (_deliveryType == 'home_to_room') {
      return _selectedRecipientRoomId != null;
    } else {
      return _selectedPickupRoomId != null && _selectedRecipientRoomId != null;
    }
  }
}
