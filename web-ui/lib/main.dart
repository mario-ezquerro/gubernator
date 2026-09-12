import 'dart:async';
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
  // Register the iframe view factories for OpenSearch Dashboards
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return html.IFrameElement()
        ..src = 'http://$host:5601/app/dashboards#/view/gubernator-cluster-logs'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'fullscreen');
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-siem-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return html.IFrameElement()
        ..src = 'http://$host:5601/app/dashboards#/view/gubernator-siem-audit'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'fullscreen');
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-discover-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return html.IFrameElement()
        ..src = 'http://$host:5601/app/discover#/view/gubernator-all-logs?_g=(filters:!(),refreshInterval:(pause:!t,value:0),time:(from:now-24h,to:now))'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'fullscreen');
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-discover-errors-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return html.IFrameElement()
        ..src = 'http://$host:5601/app/discover#/view/gubernator-error-logs?_g=(filters:!(),refreshInterval:(pause:!t,value:0),time:(from:now-24h,to:now))'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'fullscreen');
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-traces-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return html.IFrameElement()
        ..src = 'http://$host:5601/app/observability-dashboards#/trace_analytics/traces'
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

  // ENS op.acc.2 Session Inactivity State
  DateTime _lastActivity = DateTime.now();
  Timer? _inactivityTimer;
  int _sessionTimeoutMinutes = 15;
  String? _sessionTimeoutNotice;
  StreamSubscription? _mouseSub;
  StreamSubscription? _keySub;

  @override
  void initState() {
    super.initState();
    _registerActivity();
    try {
      _mouseSub = html.window.onMouseMove.listen((_) => _registerActivity());
      _keySub = html.window.onKeyDown.listen((_) => _registerActivity());
    } catch (_) {}
    _checkAuth();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _mouseSub?.cancel();
    _keySub?.cancel();
    super.dispose();
  }

  void _registerActivity() {
    _lastActivity = DateTime.now();
  }

  Future<void> _fetchSecurityConfig() async {
    try {
      final cfg = await ApiService.fetchSIEMConfig();
      if (cfg != null && cfg.sessionTimeoutMinutes > 0) {
        if (mounted) {
          setState(() {
            _sessionTimeoutMinutes = cfg.sessionTimeoutMinutes;
          });
        }
      }
    } catch (_) {}
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_currentUser == null) {
        timer.cancel();
        return;
      }
      final elapsedMinutes = DateTime.now().difference(_lastActivity).inMinutes;
      if (elapsedMinutes >= _sessionTimeoutMinutes) {
        _handleInactivityTimeout();
      }
    });
  }

  void _handleInactivityTimeout() async {
    _inactivityTimer?.cancel();
    final timeout = _sessionTimeoutMinutes;
    await ApiService.logout(reason: 'INACTIVITY_TIMEOUT');
    if (mounted) {
      setState(() {
        _currentUser = null;
        _sessionTimeoutNotice =
            'Sesión cerrada por inactividad ($timeout minutos) en cumplimiento con ENS op.acc.2.';
      });
    }
  }

  Future<void> _checkAuth() async {
    try {
      final user = await ApiService.fetchMe();
      if (mounted) {
        setState(() {
          _currentUser = user;
          if (user != null) {
            _displayName = user.displayName;
            _registerActivity();
          }
          _checkingAuth = false;
        });
        if (user != null) {
          _fetchSecurityConfig();
          _startInactivityTimer();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingAuth = false);
      }
    }
  }

  void _handleLogout() async {
    _inactivityTimer?.cancel();
    await ApiService.logout();
    if (mounted) {
      setState(() {
        _currentUser = null;
        _sessionTimeoutNotice = null;
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
                  timeoutMessage: _sessionTimeoutNotice,
                  onLoginSuccess: (user) {
                    setState(() {
                      _currentUser = user;
                      _displayName = user.displayName;
                      _sessionTimeoutNotice = null;
                      _registerActivity();
                    });
                    _fetchSecurityConfig();
                    _startInactivityTimer();
                  },
                )
              : Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _registerActivity(),
                  onPointerMove: (_) => _registerActivity(),
                  onPointerHover: (_) => _registerActivity(),
                  onPointerSignal: (_) => _registerActivity(),
                  child: AppShell(
                    isDark: _isDark,
                    onThemeChanged: (dark) => setState(() => _isDark = dark),
                    displayName: _displayName,
                    onNameChanged: (name) => setState(() => _displayName = name),
                    currentUser: _currentUser,
                    onLogout: _handleLogout,
                  ),
                ),
    );
  }
}
