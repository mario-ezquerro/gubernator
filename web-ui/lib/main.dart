import 'dart:async';
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'models/models.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'theme/theme.dart';

/// Global registry of persistent iframe DOM elements to avoid tearing down and reloading
/// iframes during Flutter Web widget tree updates or post-sleep wakeups.
final Map<String, html.IFrameElement> registeredIframes = {};

html.IFrameElement getOrCreateIframe(String viewType, String Function() srcBuilder) {
  return registeredIframes.putIfAbsent(viewType, () {
    return html.IFrameElement()
      ..src = srcBuilder()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..setAttribute('allow', 'fullscreen');
  });
}

/// Cleans up any stale Grafana session expiry cookies that cause infinite token-refresh reload loops.
void clearGrafanaStaleCookies() {
  try {
    for (final path in ['/grafana', '/grafana/', '/']) {
      html.document.cookie = 'grafana_session_expiry=; Path=$path; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax';
      html.document.cookie = 'grafana_session=; Path=$path; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax';
    }
  } catch (_) {}
}

/// Force reload an embedded iframe if needed by re-triggering its src.
void reloadIframe(String viewType) {
  clearGrafanaStaleCookies();
  final iframe = registeredIframes[viewType];
  if (iframe != null) {
    final currentSrc = iframe.src;
    iframe.src = '';
    Future.microtask(() {
      iframe.src = currentSrc;
    });
  }
}

void main() {
  clearGrafanaStaleCookies();
  // Register the iframe view factory for Grafana (Cluster Overview)
  ui_web.platformViewRegistry.registerViewFactory(
    'grafana-iframe',
    (int viewId) => getOrCreateIframe(
      'grafana-iframe',
      () => '/grafana/d/gubernator-overview/gubernator-e28094-cluster-overview?orgId=1&kiosk',
    ),
  );
  // Register the iframe view factory for Grafana Network Monitor
  ui_web.platformViewRegistry.registerViewFactory(
    'grafana-network-iframe',
    (int viewId) => getOrCreateIframe(
      'grafana-network-iframe',
      () => '/grafana/d/gubernator-network/gubernator-e28094-network-monitor?orgId=1&kiosk',
    ),
  );
  // Register the iframe view factory for Jaeger
  ui_web.platformViewRegistry.registerViewFactory(
    'jaeger-iframe',
    (int viewId) => getOrCreateIframe(
      'jaeger-iframe',
      () => '/jaeger/',
    ),
  );
  // Register the iframe view factory for Weave Scope Network Topology
  ui_web.platformViewRegistry.registerViewFactory(
    'scope-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return getOrCreateIframe('scope-iframe', () => 'http://$host:4040/');
    },
  );
  // Register the iframe view factories for OpenSearch Dashboards
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return getOrCreateIframe(
        'opensearch-iframe',
        () => 'http://$host:5601/app/dashboards#/view/gubernator-cluster-logs',
      );
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-siem-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return getOrCreateIframe(
        'opensearch-siem-iframe',
        () => 'http://$host:5601/app/dashboards#/view/gubernator-siem-audit',
      );
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-discover-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return getOrCreateIframe(
        'opensearch-discover-iframe',
        () => 'http://$host:5601/app/discover#/view/gubernator-all-logs?_g=(filters:!(),refreshInterval:(pause:!t,value:0),time:(from:now-24h,to:now))',
      );
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-discover-errors-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return getOrCreateIframe(
        'opensearch-discover-errors-iframe',
        () => 'http://$host:5601/app/discover#/view/gubernator-error-logs?_g=(filters:!(),refreshInterval:(pause:!t,value:0),time:(from:now-24h,to:now))',
      );
    },
  );
  ui_web.platformViewRegistry.registerViewFactory(
    'opensearch-traces-iframe',
    (int viewId) {
      final host = html.window.location.hostname ?? 'localhost';
      return getOrCreateIframe(
        'opensearch-traces-iframe',
        () => 'http://$host:5601/app/observability-dashboards#/trace_analytics/traces',
      );
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
  String _currentThemeId = 'dark';
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
    try {
      final savedTheme = html.window.localStorage['gbnt_theme'];
      if (savedTheme != null && savedTheme.isNotEmpty) {
        _currentThemeId = savedTheme;
      }
    } catch (_) {}
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
    final themeDef = GubernatorTheme.getThemeDef(_currentThemeId);
    final activeThemeData = GubernatorTheme.getThemeData(_currentThemeId);

    return MaterialApp(
      title: 'Gubernator Dashboard',
      debugShowCheckedModeBanner: false,
      theme: activeThemeData,
      themeMode: themeDef.isDark ? ThemeMode.dark : ThemeMode.light,
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
                    currentThemeId: _currentThemeId,
                    onThemeChanged: (themeId) {
                      setState(() => _currentThemeId = themeId);
                      try {
                        html.window.localStorage['gbnt_theme'] = themeId;
                      } catch (_) {}
                    },
                    displayName: _displayName,
                    onNameChanged: (name) => setState(() => _displayName = name),
                    currentUser: _currentUser,
                    onLogout: _handleLogout,
                  ),
                ),
    );
  }
}
