import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ───────────────────────────────────────────────────────────────
/// ThemeController — butun ilova bo'ylab dark mode holatini
/// bitta joydan boshqaradi. LayoutPage, SettingsPage, PinLockPage
/// va boshqa har qanday sahifa shu controllerga obuna bo'lib,
/// dark mode o'zgarganda avtomatik qayta chiziladi (rebuild).
/// ───────────────────────────────────────────────────────────────
class ThemeController extends ChangeNotifier {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  Future<void> setDarkMode(bool value) async {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }
}