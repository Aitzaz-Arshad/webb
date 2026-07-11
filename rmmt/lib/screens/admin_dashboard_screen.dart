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

  Widget _buildCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      color: kNavyMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 36, color: kAccent),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      body: Container(
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
            Expanded(
              child: GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                children: [
                  _buildCard(
                    title: 'Map & Room Editor',
                    description: 'Configure layout boundaries, map obstacle geometry, and drop room delivery markers.',
                    icon: Icons.map_outlined,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const MainScreen()),
                      );
                    },
                  ),
                  _buildCard(
                    title: '2D Floor Plan Editor',
                    description: 'Overlay and drag room bounding boxes on the static building floor plan image.',
                    icon: Icons.layers_outlined,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const RoomEditorScreen()),
                      );
                    },
                  ),
                  _buildCard(
                    title: 'Deliveries Log',
                    description: 'Verify pending delivery requests and manual override robot travel tasks status.',
                    icon: Icons.list_alt_rounded,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const DeliveriesLogScreen()),
                      );
                    },
                  ),
                  _buildCard(
                    title: 'Live Telemetry',
                    description: 'Monitor robot positioning, trajectory plotting logs, and telemetry status.',
                    icon: Icons.track_changes_rounded,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Robot telemetry link active. Open Map/Room Editor to view live paths.')),
                      );
                    },
                  ),
                  _buildCard(
                    title: 'User Directories',
                    description: 'Manage registered student accounts and allocate authorization roles.',
                    icon: Icons.people_outline_rounded,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const UserManagementScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
