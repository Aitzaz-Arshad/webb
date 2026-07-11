// lib/providers/auth_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_planning/api/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  int? _userId;
  int? get userId => _userId;

  String? _userName;
  String? get userName => _userName;

  String? _userEmail;
  String? get userEmail => _userEmail;

  String? _userRole;
  String? get userRole => _userRole;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  bool get isLoggedIn => _userId != null;
  bool get isAdmin => _userRole == 'admin';

  AuthProvider() {
    initSession();
  }

  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('userId');
    _userName = prefs.getString('userName');
    _userEmail = prefs.getString('userEmail');
    _userRole = prefs.getString('userRole');
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final response = await _apiService.login(email, password);
      final user = response['user'];

      _userId = user['id'];
      _userName = user['name'];
      _userEmail = user['email'];
      _userRole = user['role'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('userId', _userId!);
      await prefs.setString('userName', _userName!);
      await prefs.setString('userEmail', _userEmail!);
      await prefs.setString('userRole', _userRole!);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String name, String email, String password, String role) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      await _apiService.register(name, email, password, role);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _userId = null;
    _userName = null;
    _userEmail = null;
    _userRole = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('userEmail');
    await prefs.remove('userRole');

    notifyListeners();
  }
}
