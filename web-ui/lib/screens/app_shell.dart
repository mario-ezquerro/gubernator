import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/sidebar.dart';
import '../widgets/settings_dialog.dart';
import 'pages/overview_page.dart';
import 'pages/legions_page.dart';
import 'pages/centurions_page.dart';
import 'pages/tasks_page.dart';
import 'pages/caddy_page.dart';
import 'pages/coredns_page.dart';
import 'pages/grafana_page.dart';
import 'pages/jaeger_page.dart';

/// Main application shell with sidebar navigation + content area.
class AppShell extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final String displayName;
  final ValueChanged<String> onNameChanged;

  const AppShell({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
    required this.displayName,
    required this.onNameChanged,
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

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  List<SidebarItem> _buildSidebarItems() {
    final running = _state.tasks.where((t) => t.status == 'running').length;
    return [
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
        icon: Icons.alt_route_outlined,
        activeIcon: Icons.alt_route,
        label: 'Caddy Ingress',
      ),
      const SidebarItem(
        icon: Icons.manage_search_outlined,
        activeIcon: Icons.manage_search,
        label: 'CoreDNS',
      ),
      // Grafana & Jaeger (conditional in sidebar, always defined)
      const SidebarItem(
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics,
        label: 'Grafana',
      ),
      const SidebarItem(
        icon: Icons.timeline_outlined,
        activeIcon: Icons.timeline,
        label: 'Jaeger',
      ),
    ];
  }

  // Navigation labels for the header breadcrumb
  static const _pageLabels = [
    'Overview',
    'Centurions [Host]',
    'Legions [Stacks]',
    'Tasks',
    'Caddy Ingress',
    'CoreDNS',
    'Grafana',
    'Jaeger',
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
        return CaddyPage(state: _state, onRefresh: _fetchData);
      case 5:
        return CoreDnsPage(state: _state, onRefresh: _fetchData);
      case 6:
        return const GrafanaPage();
      case 7:
        return const JaegerPage();
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

    return Scaffold(
      body: Row(
        children: [
          // ─── Sidebar ─────────────────────────────────────
          GubernatorSidebar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              // Guard Grafana/Jaeger if monitor not running
              if (index >= 6 && !_state.monitorRunning) return;
              setState(() => _selectedIndex = index);
            },
            isDark: widget.isDark,
            onThemeChanged: widget.onThemeChanged,
            version: _state.version,
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
                        _pageLabels[_selectedIndex],
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const Spacer(),

                      // Last refresh
                      if (_lastRefresh != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
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
                        const SizedBox(width: 8),
                      ],

                      // Refresh button
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh now',
                        onPressed: _fetchData,
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
                              child: _buildCurrentPage(),
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
