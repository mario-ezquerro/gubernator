import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/sidebar.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/update_dialog.dart';
import 'pages/overview_page.dart';
import 'pages/legions_page.dart';
import 'pages/centurions_page.dart';
import 'pages/tasks_page.dart';
import 'pages/caddy_page.dart';
import 'pages/coredns_page.dart';
import 'pages/grafana_page.dart';
import 'pages/loki_logs_page.dart';
import 'pages/jaeger_page.dart';
import 'pages/network_page.dart';
import 'pages/scope_page.dart';
import 'pages/slo_page.dart';
import 'pages/security_page.dart';

/// Main application shell with sidebar navigation + content area.
class AppShell extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final String displayName;
  final ValueChanged<String> onNameChanged;
  final UserSession? currentUser;
  final VoidCallback? onLogout;

  const AppShell({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
    required this.displayName,
    required this.onNameChanged,
    this.currentUser,
    this.onLogout,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DashboardState _state = DashboardState();
  bool _loading = true;
  String? _error;
  DateTime? _lastRefresh;
  Timer? _timer;
  int _selectedIndex = 0;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
    // Auto-collapse on narrow screens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.of(context).size.width < 1200) {
        setState(() => _sidebarCollapsed = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final data = await ApiService.fetchState();
      if (mounted) {
        setState(() {
          _state = data;
          _loading = false;
          _error = null;
          _lastRefresh = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        isDark: widget.isDark,
        onThemeChanged: widget.onThemeChanged,
        displayName: widget.displayName,
        onNameChanged: widget.onNameChanged,
        version: _state.version,
        nodes: _state.nodes,
      ),
    );
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) => UpdateDialog(
        currentVersion: _state.version,
        latestVersion: _state.latestVersion,
        releaseNotes: _state.releaseNotes,
        releaseUrl: _state.releaseUrl,
        onUpdateTriggered: _fetchData,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$hour:$min:$sec';
  }

  List<SidebarItem> _buildSidebarItems() {
    final running = _state.tasks.where((t) => t.status == 'running').length;
    final items = [
      const SidebarItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        label: 'Overview',
      ),
      SidebarItem(
        icon: Icons.dns_outlined,
        activeIcon: Icons.dns,
        label: 'Centurions [Host]',
        badgeCount: _state.nodes.length,
        showBadge: true,
      ),
      SidebarItem(
        icon: Icons.layers_outlined,
        activeIcon: Icons.layers,
        label: 'Legions [Stacks]',
        badgeCount: _state.stacks.length,
        showBadge: true,
      ),
      SidebarItem(
        icon: Icons.view_in_ar_outlined,
        activeIcon: Icons.view_in_ar,
        label: 'Tasks',
        badgeCount: running,
        showBadge: true,
      ),
      const SidebarItem(
        icon: Icons.speed_outlined,
        activeIcon: Icons.speed,
        label: 'SLO & Error Budgets',
      ),
      const SidebarItem(
        icon: Icons.alt_route_outlined,
        activeIcon: Icons.alt_route,
        label: 'Caddy Ingress',
      ),
      const SidebarItem(
        icon: Icons.manage_search_outlined,
        activeIcon: Icons.manage_search,
        label: 'CoreDNS',
      ),
      // Monitoring (Grafana), Loki Logs, Network & Jaeger
      const SidebarItem(
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics,
        label: 'Monitoring',
      ),
      const SidebarItem(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        label: 'Loki Logs',
      ),
      const SidebarItem(
        icon: Icons.network_check_outlined,
        activeIcon: Icons.network_check,
        label: 'Network Monitor',
      ),
      const SidebarItem(
        icon: Icons.timeline_outlined,
        activeIcon: Icons.timeline,
        label: 'Jaeger',
      ),
      const SidebarItem(
        icon: Icons.hub_outlined,
        activeIcon: Icons.hub,
        label: 'Network Topology',
      ),
      const SidebarItem(
        icon: Icons.shield_outlined,
        activeIcon: Icons.shield,
        label: 'Security & Directory',
      ),
    ];
    return items;
  }

  // Navigation labels for the header breadcrumb
  static const _pageLabels = [
    'Overview',
    'Centurions [Host]',
    'Legions [Stacks]',
    'Tasks',
    'SLO & Error Budgets',
    'Caddy Ingress',
    'CoreDNS',
    'Monitoring',
    'Loki Logs',
    'Network Monitor',
    'Jaeger',
    'Network Topology',
    'Security & Directory',
  ];

  Widget _buildCurrentPage() {
    switch (_selectedIndex) {
      case 0:
        return OverviewPage(
          state: _state,
          onRefresh: _fetchData,
          onViewLegions: () => setState(() => _selectedIndex = 2),
          onViewCenturions: () => setState(() => _selectedIndex = 1),
          onViewTasks: () => setState(() => _selectedIndex = 3),
        );
      case 1:
        return CenturionsPage(state: _state, onRefresh: _fetchData);
      case 2:
        return LegionsPage(state: _state, onRefresh: _fetchData);
      case 3:
        return TasksPage(state: _state, onRefresh: _fetchData);
      case 4:
        return SloPage(state: _state, onRefresh: _fetchData);
      case 5:
        return CaddyPage(state: _state, onRefresh: _fetchData);
      case 6:
        return CoreDnsPage(state: _state, onRefresh: _fetchData);
      case 7:
        return const GrafanaPage();
      case 8:
        return const LokiLogsPage();
      case 9:
        return const NetworkPage();
      case 10:
        return const JaegerPage();
      case 11:
        return const ScopePage();
      case 12:
        return SecurityPage(state: _state, onRefresh: _fetchData);
      default:
        return OverviewPage(
          state: _state,
          onRefresh: _fetchData,
          onViewLegions: () => setState(() => _selectedIndex = 2),
          onViewCenturions: () => setState(() => _selectedIndex = 1),
          onViewTasks: () => setState(() => _selectedIndex = 3),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = widget.currentUser ?? _state.currentUser;

    return Scaffold(
      body: Row(
        children: [
          // ─── Sidebar ─────────────────────────────────────
          GubernatorSidebar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              // Guard Grafana/Jaeger if monitor not running
              if (index >= 7 && index <= 9 && !_state.monitorRunning) return;
              setState(() => _selectedIndex = index);
            },
            isDark: widget.isDark,
            onThemeChanged: widget.onThemeChanged,
            version: _state.version,
            updateAvailable: _state.updateAvailable,
            latestVersion: _state.latestVersion,
            onUpdatePressed: _showUpdateDialog,
            onSettingsPressed: _openSettings,
            items: _buildSidebarItems(),
            isCollapsed: _sidebarCollapsed,
            onToggleCollapse: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            monitorRunning: _state.monitorRunning,
          ),

          // ─── Main Content Area ───────────────────────────
          Expanded(
            child: Column(
              children: [
                // ─── Top Header Bar ─────────────────────────
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Breadcrumb
                      Text(
                        _selectedIndex < _pageLabels.length ? _pageLabels[_selectedIndex] : 'Overview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const Spacer(),

                      // User Profile Badge & Role Chip
                      if (user != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: user.isAdmin
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : user.isOperator
                                        ? Colors.blue.withValues(alpha: 0.2)
                                        : Colors.green.withValues(alpha: 0.2),
                                child: Text(
                                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: user.isAdmin ? Colors.amber : user.isOperator ? Colors.blue : Colors.green,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                user.displayName,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: user.isAdmin
                                      ? Colors.amber.withValues(alpha: 0.15)
                                      : user.isOperator
                                          ? Colors.blue.withValues(alpha: 0.15)
                                          : Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  user.isAdmin ? '👑 ADMIN' : user.isOperator ? '⚡ OPERATOR' : '👁️ READ-ONLY',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: user.isAdmin ? Colors.amber : user.isOperator ? Colors.blue : Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // Last refresh
                      if (_lastRefresh != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Row(
                            children: [
                              Icon(Icons.access_time,
                                  size: 14,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4)),
                              const SizedBox(width: 4),
                              Text(
                                _formatTime(_lastRefresh!),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                                  fontFamily: 'Courier New',
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Observability quick links
                      if (_state.monitorRunning) ...[
                        IconButton(
                          icon: const Icon(Icons.analytics_outlined, size: 20),
                          tooltip: 'Open Grafana (new tab)',
                          onPressed: () =>
                              html.window.open('/grafana/', '_blank'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.timeline, size: 20),
                          tooltip: 'Open Jaeger (new tab)',
                          onPressed: () =>
                              html.window.open('/jaeger/', '_blank'),
                        ),
                        const SizedBox(width: 4),
                      ],

                      // Refresh button
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh now',
                        onPressed: _fetchData,
                      ),

                      // Logout button
                      if (widget.onLogout != null)
                        IconButton(
                          icon: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
                          tooltip: 'Sign Out',
                          onPressed: widget.onLogout,
                        ),
                    ],
                  ),
                ),

                // ─── Page Content ───────────────────────────
                Expanded(
                  child: _loading && _state.nodes.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null && _state.nodes.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_off,
                                      size: 64,
                                      color: theme.colorScheme.error
                                          .withValues(alpha: 0.6)),
                                  const SizedBox(height: 16),
                                  Text('Connection error',
                                      style: theme.textTheme.titleLarge),
                                  const SizedBox(height: 8),
                                  Text(_error!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      )),
                                  const SizedBox(height: 24),
                                  FilledButton.icon(
                                    onPressed: _fetchData,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.topLeft,
                                  children: [
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey<int>(_selectedIndex),
                                child: _buildCurrentPage(),
                              ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
