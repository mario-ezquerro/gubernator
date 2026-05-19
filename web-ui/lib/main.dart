import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'theme/theme.dart';

void main() {
  runApp(const GubernatorApp());
}

/// Root widget for the Gubernator Web Dashboard.
class GubernatorApp extends StatefulWidget {
  const GubernatorApp({super.key});

  @override
  State<GubernatorApp> createState() => _GubernatorAppState();
}

class _GubernatorAppState extends State<GubernatorApp> {
  bool _isDark = true; // Default to dark mode
  String _displayName = 'Admin';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gubernator Dashboard',
      debugShowCheckedModeBanner: false,
      theme: GubernatorTheme.light(),
      darkTheme: GubernatorTheme.dark(),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: DashboardScreen(
        isDark: _isDark,
        onThemeChanged: (dark) => setState(() => _isDark = dark),
        displayName: _displayName,
        onNameChanged: (name) => setState(() => _displayName = name),
      ),
    );
  }
}
