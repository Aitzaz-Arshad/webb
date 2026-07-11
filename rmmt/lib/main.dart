import 'package:flutter/material.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:path_planning/providers/auth_provider.dart';
import 'package:path_planning/screens/starting_screen.dart';
import 'package:path_planning/screens/login_screen.dart';
import 'package:path_planning/screens/admin_dashboard_screen.dart';
import 'package:path_planning/screens/user_dashboard_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => MapProvider()),
      ],
      child: MaterialApp(
        title: 'ParcelPath Navigation',
        theme: ThemeData(
          primaryColor: const Color(0xFF122140),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF122140),
            elevation: 1,
            iconTheme: IconThemeData(color: Colors.white),
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,  
            ),
          ),
        ),
        debugShowCheckedModeBanner: false,
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    
    if (auth.isLoggedIn) {
      if (auth.isAdmin) {
        return const AdminDashboardScreen();
      } else {
        return const UserDashboardScreen();
      }
    } else {
      return const StartingScreen();
    }
  }
}