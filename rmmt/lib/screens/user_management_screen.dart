// lib/screens/user_management_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_planning/api/api_service.dart';
import 'package:path_planning/providers/auth_provider.dart';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6);

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _users = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.userId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final list = await _apiService.getUsers(auth.userId!, auth.userRole!);
      setState(() {
        _users = list;
      });
    } catch (e) {
      print('Error fetching users: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateUserRole(int targetUserId, String role) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await _apiService.updateUser(
        auth.userId!,
        auth.userRole!,
        targetUserId,
        role: role,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User role updated successfully.')),
      );
      _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update role: $e')),
      );
    }
  }

  Future<void> _toggleUserActiveStatus(int targetUserId, bool isActive) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await _apiService.updateUser(
        auth.userId!,
        auth.userRole!,
        targetUserId,
        isActive: isActive,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive ? 'User reactivated successfully.' : 'User deactivated successfully.',
          ),
        ),
      );
      _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  void _confirmDeactivate(int targetUserId, String userName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: kNavyMid,
          title: const Text(
            'Confirm Deactivation',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Are you sure you want to deactivate user "$userName"? This user will no longer be able to log in, but their historical delivery logs will be preserved.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.of(context).pop();
                _toggleUserActiveStatus(targetUserId, false);
              },
              child: const Text('Deactivate', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: kNavyDark,
      appBar: AppBar(
        title: const Text('Registered Portal Users'),
        backgroundColor: kNavyMid,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: _users.isEmpty
                  ? Center(
                      child: Text(
                        'No registered users found.',
                        style: TextStyle(color: Colors.white.withOpacity(0.4)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final userId = user['id'] as int;
                        final role = user['role'] as String;
                        final isActive = user['is_active'] as bool;
                        final isSelf = userId == auth.userId;

                        return Card(
                          color: kNavyMid,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: role == 'admin' ? kAccent : Colors.white24,
                                  foregroundColor: role == 'admin' ? kNavyDark : Colors.white,
                                  child: const Icon(Icons.person),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            user['name'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          if (isSelf) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'YOU',
                                                style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        user['email'],
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      // Active/Inactive status indicator
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? Colors.green.withOpacity(0.12)
                                              : Colors.red.withOpacity(0.12),
                                          border: Border.all(
                                            color: isActive ? Colors.green : Colors.red,
                                            width: 1,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          isActive ? 'ACTIVE' : 'DEACTIVATED',
                                          style: TextStyle(
                                            color: isActive ? Colors.green : Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Dropdown to change role
                                DropdownButton<String>(
                                  value: role,
                                  dropdownColor: kNavyMid,
                                  underline: Container(),
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                                  style: const TextStyle(color: Colors.white),
                                  items: isSelf
                                      ? [
                                          DropdownMenuItem(
                                            value: role,
                                            child: Text(role.toUpperCase()),
                                          )
                                        ]
                                      : const [
                                          DropdownMenuItem(value: 'user', child: Text('USER')),
                                          DropdownMenuItem(value: 'admin', child: Text('ADMIN')),
                                        ],
                                  onChanged: isSelf
                                      ? null
                                      : (newRole) {
                                          if (newRole != null && newRole != role) {
                                            _updateUserRole(userId, newRole);
                                          }
                                        },
                                ),
                                const SizedBox(width: 12),
                                // Deactivate/Reactivate button
                                isSelf
                                    ? const SizedBox(width: 40) // Placeholder to align
                                    : IconButton(
                                        icon: Icon(
                                          isActive ? Icons.block_flipped : Icons.check_circle_outline_rounded,
                                          color: isActive ? Colors.redAccent : Colors.greenAccent,
                                        ),
                                        tooltip: isActive ? 'Deactivate User' : 'Reactivate User',
                                        onPressed: () {
                                          if (isActive) {
                                            _confirmDeactivate(userId, user['name']);
                                          } else {
                                            _toggleUserActiveStatus(userId, true);
                                          }
                                        },
                                      ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
