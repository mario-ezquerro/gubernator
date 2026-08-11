import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'screens/app_shell.dart';
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
      final host = html.window.location.hostname;
      return html.IFrameElement()
        ..src = 'http://$host:4040/'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
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
      home: AppShell(
        isDark: _isDark,
        onThemeChanged: (dark) => setState(() => _isDark = dark),
        displayName: _displayName,
        onNameChanged: (name) => setState(() => _displayName = name),
      ),
    );
  }
}
