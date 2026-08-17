import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'models/models.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'theme/theme.dart';

void main() {
  // Register the iframe view factory for Grafana
  ui_web.platformViewRegistry.registerViewFactory(
    'grafana-iframe',
    (int viewId) => html.IFrameElement()
      ..src = '/grafana/'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%',
  );
  // Register the iframe view factory for Grafana Network Monitor
  ui_web.platformViewRegistry.registerViewFactory(
    'grafana-network-iframe',
    (int viewId) => html.IFrameElement()
      ..src = '/grafana/d/gubernator-network/gubernator-network-monitor?orgId=1&kiosk'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%',
  );
  // Register the iframe view factory for Jaeger
  ui_web.platformViewRegistry.registerViewFactory(
    'jaeger-iframe',
    (int viewId) => html.IFrameElement()
      ..src = '/jaeger/'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%',
  );
  // Register the iframe view factory for Weave Scope Network Topology
  ui_web.platformViewRegistry.registerViewFactory(
    'scope-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return html.IFrameElement()
        ..src = 'http://$host:4040/'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'fullscreen');
    },
  );
  runApp(const GubernatorApp());
}

/// Root widget for the Gubernator Web Dashboard.
class GubernatorApp extends StatefulWidget {
  const GubernatorApp({super.key});

  @override
  State<GubernatorApp> createState() => _GubernatorAppState();
}

class _GubernatorAppState extends State<GubernatorApp> {
  bool _isDark = true;
  String _displayName = 'Admin';
  UserSession? _currentUser;
  bool _checkingAuth = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final user = await ApiService.fetchMe();
      if (mounted) {
        setState(() {
          _currentUser = user;
          if (user != null) {
            _displayName = user.displayName;
          }
          _checkingAuth = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingAuth = false);
      }
    }
  }

  void _handleLogout() async {
    await ApiService.logout();
    if (mounted) {
      setState(() {
        _currentUser = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gubernator Dashboard',
      debugShowCheckedModeBanner: false,
      theme: GubernatorTheme.light(),
      darkTheme: GubernatorTheme.dark(),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: _checkingAuth
          ? const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏛', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 16),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            )
          : _currentUser == null
              ? LoginScreen(
                  onLoginSuccess: (user) {
                    setState(() {
                      _currentUser = user;
                      _displayName = user.displayName;
                    });
                  },
                )
              : AppShell(
                  isDark: _isDark,
                  onThemeChanged: (dark) => setState(() => _isDark = dark),
                  displayName: _displayName,
                  onNameChanged: (name) => setState(() => _displayName = name),
                  currentUser: _currentUser,
                  onLogout: _handleLogout,
                ),
    );
  }
}
