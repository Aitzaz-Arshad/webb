// lib/main.dart

import 'package:flutter/material.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:path_planning/screens/starting_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MapProvider(),
      child: MaterialApp(
        title: 'Hamara Bhenchod Robot',
        theme: ThemeData(
          primaryColor: const Color.fromARGB(255, 113, 148, 177),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            elevation: 1,
            iconTheme: IconThemeData(color: Colors.black87),
            titleTextStyle: TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.w500,  
            ),
          ),
        ),
        debugShowCheckedModeBanner: false,
        home: const StartingScreen(),
      ),
    );
  }
}