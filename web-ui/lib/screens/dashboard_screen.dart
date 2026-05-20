import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/compose_editor.dart';
import '../widgets/settings_dialog.dart';

/// Main dashboard screen.
class DashboardScreen extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final String displayName;
  final ValueChanged<String> onNameChanged;

  const DashboardScreen({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
    required this.displayName,
    required this.onNameChanged,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardState _state = DashboardState();
  bool _loading = true;
  String? _error;
  DateTime? _lastRefresh;
  Timer? _timer;
  String _stackSearchQuery = '';
  String _nodeSearchQuery = '';
  String _taskSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
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

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Stack Actions ──────────────────────────────────────────────────
  Future<void> _deleteStack(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Stack'),
        content:
            const Text('Delete this stack and stop all its containers?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.deleteStack(id);
    _showSnackBar(
      ok ? 'Stack deleted and containers stopped.' : 'Failed to delete stack.',
      isError: !ok,
    );
    _fetchData();
  }

  Future<void> _redeployStack(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeploy Stack'),
        content: const Text(
            'Stop existing containers and redeploy this stack?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Redeploy')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.redeployStack(id);
    _showSnackBar(
      ok ? 'Stack redeployed!' : 'Redeploy failed.',
      isError: !ok,
    );
    _fetchData();
  }

  Future<void> _openComposeEditor(StackModel stack) async {
    try {
      final yaml = await ApiService.getStackCompose(stack.id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => ComposeEditorDialog(
          stackName: stack.name,
          composeYaml: yaml,
          onSave: (y) => ApiService.updateStackCompose(stack.id, y),
          onRedeploy: (_) async {
            final ok = await ApiService.redeployStack(stack.id);
            _fetchData();
            return ok;
          },
        ),
      );
    } catch (e) {
      _showSnackBar('Failed to load compose file', isError: true);
    }
  }

  Future<void> _stopTask(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Task'),
        content: const Text('Stop this container/task?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Stop')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.deleteTask(id);
    _showSnackBar(
      ok ? 'Task stopped.' : 'Failed to stop task.',
      isError: !ok,
    );
    _fetchData();
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        isDark: widget.isDark,
        onThemeChanged: widget.onThemeChanged,
        displayName: widget.displayName,
        onNameChanged: widget.onNameChanged,
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = _state.tasks;
    final running = tasks.where((t) => t.status == 'running').length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.network('/gubernator-icon.png',
                height: 28, width: 28,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.hub, color: theme.colorScheme.primary)),
            const SizedBox(width: 12),
            const Text('Gubernator'),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Manager',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ],
        ),
        actions: [
          // Last refresh
          if (_lastRefresh != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Refreshed: ${_formatTime(_lastRefresh!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          // Settings gear icon
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && _state.nodes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _state.nodes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off,
                          size: 64,
                          color:
                              theme.colorScheme.error.withValues(alpha: 0.6)),
                      const SizedBox(height: 16),
                      Text('Connection error',
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: theme.textTheme.bodySmall?.copyWith(
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
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsRow(theme, running),
                        const SizedBox(height: 24),
                        _buildTwoColumnRow(theme),
                        const SizedBox(height: 24),
                        _buildTasksSection(theme),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ─── Stats Row ──────────────────────────────────────────────────────
  Widget _buildStatsRow(ThemeData theme, int running) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final cards = [
          StatCard(
              label: 'Nodes',
              value: '${_state.nodes.length}',
              icon: Icons.dns),
          StatCard(
              label: 'Stacks',
              value: '${_state.stacks.length}',
              icon: Icons.layers),
          StatCard(
              label: 'Services',
              value: '${_state.services.length}',
              icon: Icons.miscellaneous_services),
          StatCard(
              label: 'Tasks',
              value: '${_state.tasks.length}',
              icon: Icons.task),
          StatCard(
              label: 'Running',
              value: '$running',
              icon: Icons.play_circle,
              valueColor: const Color(0xFF10B981)),
        ];

        if (isWide) {
          return Row(
            children:
                cards.map((c) => Expanded(child: c)).toList(),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cards
              .map((c) => SizedBox(width: constraints.maxWidth / 2 - 8, child: c))
              .toList(),
        );
      },
    );
  }

  // ─── Two Column: Stacks + Nodes ─────────────────────────────────────
  Widget _buildTwoColumnRow(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final stacksCard = _buildStacksCard(theme);
        final nodesCard = _buildNodesCard(theme);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: stacksCard),
              const SizedBox(width: 24),
              Expanded(child: nodesCard),
            ],
          );
        }
        return Column(children: [stacksCard, const SizedBox(height: 24), nodesCard]);
      },
    );
  }

  Widget _buildStacksCard(ThemeData theme) {
    final filteredStacks = _state.stacks.where((s) {
      if (_stackSearchQuery.isEmpty) return true;
      return s.id.toLowerCase().contains(_stackSearchQuery) ||
          s.name.toLowerCase().contains(_stackSearchQuery);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Legions (Stacks)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search stacks...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (val) {
                setState(() {
                  _stackSearchQuery = val.toLowerCase();
                });
              },
            ),
            const SizedBox(height: 16),
            if (filteredStacks.isEmpty)
              _emptyState(_state.stacks.isEmpty ? 'No stacks deployed yet' : 'No matching stacks found', Icons.layers_clear)
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('ID')),
                    DataColumn(label: Text('NAME')),
                    DataColumn(label: Text('CREATED')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: filteredStacks.map((s) {
                    return DataRow(cells: [
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(s.id.length > 8 ? s.id.substring(0, 8) : s.id,
                              style: const TextStyle(fontFamily: 'Courier New', fontSize: 13)),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 14),
                            tooltip: 'Copy full ID',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: s.id));
                              _showSnackBar('Copied Stack ID to clipboard!');
                            },
                          ),
                        ],
                      )),
                      DataCell(Text(s.name,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(_formatDate(s.createdAt))),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _actionBtn(Icons.code, 'Edit YAML',
                              const Color(0xFF3B82F6), () => _openComposeEditor(s)),
                          _actionBtn(Icons.rocket_launch, 'Redeploy',
                              const Color(0xFFD29922), () => _redeployStack(s.id)),
                          _actionBtn(Icons.delete, 'Delete',
                              const Color(0xFFEF4444), () => _deleteStack(s.id)),
                        ],
                      )),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodesCard(ThemeData theme) {
    final filteredNodes = _state.nodes.where((n) {
      if (_nodeSearchQuery.isEmpty) return true;
      return n.id.toLowerCase().contains(_nodeSearchQuery) ||
          n.ip.toLowerCase().contains(_nodeSearchQuery) ||
          n.role.toLowerCase().contains(_nodeSearchQuery) ||
          n.status.toLowerCase().contains(_nodeSearchQuery);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Centurions (Nodes)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search nodes...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (val) {
                setState(() {
                  _nodeSearchQuery = val.toLowerCase();
                });
              },
            ),
            const SizedBox(height: 16),
            if (filteredNodes.isEmpty)
              _emptyState(_state.nodes.isEmpty ? 'No nodes registered' : 'No matching nodes found', Icons.dns)
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('ID')),
                    DataColumn(label: Text('IP')),
                    DataColumn(label: Text('ROLE')),
                    DataColumn(label: Text('STATUS')),
                  ],
                  rows: filteredNodes.map((n) {
                    return DataRow(cells: [
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(n.id.length > 8 ? n.id.substring(0, 8) : n.id,
                              style: const TextStyle(fontFamily: 'Courier New', fontSize: 13)),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 14),
                            tooltip: 'Copy full ID',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: n.id));
                              _showSnackBar('Copied Node ID to clipboard!');
                            },
                          ),
                        ],
                      )),
                      DataCell(Text(n.ip)),
                      DataCell(StatusBadge(label: n.role)),
                      DataCell(StatusBadge(label: n.status)),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Tasks Section ──────────────────────────────────────────────────
  Widget _buildTasksSection(ThemeData theme) {
    final filteredTasks = _state.tasks.where((t) {
      if (_taskSearchQuery.isEmpty) return true;
      final svc = _state.services.where((s) => s.id == t.serviceId).firstOrNull;
      final node = _state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
      return t.id.toLowerCase().contains(_taskSearchQuery) ||
          t.containerName.toLowerCase().contains(_taskSearchQuery) ||
          t.containerIp.toLowerCase().contains(_taskSearchQuery) ||
          t.status.toLowerCase().contains(_taskSearchQuery) ||
          (svc != null && svc.name.toLowerCase().contains(_taskSearchQuery)) ||
          (svc != null && svc.image.toLowerCase().contains(_taskSearchQuery)) ||
          (node != null && node.id.toLowerCase().contains(_taskSearchQuery));
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.view_in_ar,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Cohorts & Tasks (Containers)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search tasks...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (val) {
                setState(() {
                  _taskSearchQuery = val.toLowerCase();
                });
              },
            ),
            const SizedBox(height: 16),
            if (filteredTasks.isEmpty)
              _emptyState(_state.tasks.isEmpty ? 'No tasks running' : 'No matching tasks found', Icons.inbox)
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('TASK ID')),
                    DataColumn(label: Text('SERVICE')),
                    DataColumn(label: Text('CONTAINER')),
                    DataColumn(label: Text('NODE')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('IP')),
                    DataColumn(label: Text('PORTS')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: filteredTasks.map((t) {
                    final svc = _state.services
                        .where((s) => s.id == t.serviceId)
                        .firstOrNull;
                    final node = _state.nodes
                        .where((n) => n.id == t.nodeId)
                        .firstOrNull;
                    return DataRow(cells: [
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                              t.id.length > 8 ? t.id.substring(0, 8) : t.id,
                              style: const TextStyle(
                                  fontFamily: 'Courier New', fontSize: 13)),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 14),
                            tooltip: 'Copy full ID',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: t.id));
                              _showSnackBar('Copied Task ID to clipboard!');
                            },
                          ),
                        ],
                      )),
                      DataCell(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(svc?.name ?? 'unknown',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          if (svc?.image != null)
                            Text(svc!.image,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5))),
                        ],
                      )),
                      DataCell(Text(t.containerName.isEmpty ? '-' : t.containerName,
                          style: const TextStyle(
                              fontFamily: 'Courier New', fontSize: 13))),
                      DataCell(Text(
                          node != null && node.id.length > 8
                              ? node.id.substring(0, 8)
                              : node?.id ?? 'unknown',
                          style: const TextStyle(
                              fontFamily: 'Courier New', fontSize: 13))),
                      DataCell(StatusBadge(label: t.status)),
                      DataCell(Text(t.containerIp.isEmpty ? '-' : t.containerIp)),
                      DataCell(_buildPortsCell(svc, node)),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.stop_circle, size: 20),
                          color: const Color(0xFFEF4444),
                          tooltip: 'Stop task',
                          onPressed: () => _stopTask(t.id),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────
  Widget _emptyState(String text, IconData icon) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 40,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                )),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: color,
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }

  /// Builds clickable port chips for a task's service.
  /// Parses port mappings like "8080:80" → host port 8080.
  /// Each chip opens http://<nodeIP>:<hostPort> in the browser.
  Widget _buildPortsCell(Service? svc, Node? node) {
    if (svc == null || svc.ports.isEmpty) {
      return const Text('-', style: TextStyle(color: Colors.grey));
    }

    final nodeIp = (node != null && node.ip.isNotEmpty) ? node.ip : 'localhost';
    // For containers running on the manager (127.0.0.1), use localhost
    final host = (nodeIp == '127.0.0.1') ? 'localhost' : nodeIp;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: svc.ports.map((portMapping) {
        // Parse "hostPort:containerPort" or "hostPort:containerPort/protocol"
        final hostPort = portMapping.split(':').first;
        final url = 'http://$host:$hostPort';

        return ActionChip(
          avatar: Icon(Icons.open_in_new, size: 14,
              color: Theme.of(context).colorScheme.primary),
          label: Text(portMapping,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Courier New',
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              )),
          tooltip: url,
          onPressed: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              _showSnackBar('Could not open $url', isError: true);
            }
          },
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
