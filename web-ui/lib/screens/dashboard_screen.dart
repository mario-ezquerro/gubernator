import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/compose_editor.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/new_stack_dialog.dart';

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
  int? _stackSortColumnIndex;
  bool _stackSortAscending = true;
  int? _nodeSortColumnIndex;
  bool _nodeSortAscending = true;
  int? _taskSortColumnIndex;
  bool _taskSortAscending = true;
  List<String> _sectionOrder = ['stats', 'stacks_nodes', 'tasks'];

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

  void _applySorting() {
    // Apply Stacks sort
    if (_stackSortColumnIndex != null) {
      Comparable Function(StackModel s) getField;
      switch (_stackSortColumnIndex) {
        case 0:
          getField = (s) => s.id;
          break;
        case 1:
          getField = (s) => s.name;
          break;
        case 2:
          getField = (s) => s.createdAt;
          break;
        default:
          getField = (s) => s.id;
      }
      _state.stacks.sort((a, b) {
        final aVal = getField(_stackSortAscending ? a : b);
        final bVal = getField(_stackSortAscending ? b : a);
        return Comparable.compare(aVal, bVal);
      });
    }

    // Apply Nodes sort
    if (_nodeSortColumnIndex != null) {
      Comparable Function(Node n) getField;
      switch (_nodeSortColumnIndex) {
        case 0:
          getField = (n) => n.id;
          break;
        case 1:
          getField = (n) => n.ip;
          break;
        case 2:
          getField = (n) => n.role;
          break;
        case 3:
          getField = (n) => n.status;
          break;
        default:
          getField = (n) => n.id;
      }
      _state.nodes.sort((a, b) {
        final aVal = getField(_nodeSortAscending ? a : b);
        final bVal = getField(_nodeSortAscending ? b : a);
        return Comparable.compare(aVal, bVal);
      });
    }

    // Apply Tasks sort
    if (_taskSortColumnIndex != null) {
      Comparable Function(Task t) getField;
      switch (_taskSortColumnIndex) {
        case 0:
          getField = (t) => t.id;
          break;
        case 1:
          getField = (t) {
            final svc = _state.services.where((s) => s.id == t.serviceId).firstOrNull;
            return svc?.name ?? '';
          };
          break;
        case 2:
          getField = (t) => t.containerName;
          break;
        case 3:
          getField = (t) => t.nodeId;
          break;
        case 4:
          getField = (t) => t.status;
          break;
        case 5:
          getField = (t) => t.containerIp;
          break;
        default:
          getField = (t) => t.id;
      }
      _state.tasks.sort((a, b) {
        final aVal = getField(_taskSortAscending ? a : b);
        final bVal = getField(_taskSortAscending ? b : a);
        return Comparable.compare(aVal, bVal);
      });
    }
  }

  Future<void> _fetchData() async {
    try {
      final data = await ApiService.fetchState();
      if (mounted) {
        setState(() {
          _state = data;
          _applySorting();
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

  void _showNewStackDialog() {
    showDialog(
      context: context,
      builder: (ctx) => NewStackDialog(
        onDeploy: (name, yaml) async {
          final ok = await ApiService.deployStack(name, yaml);
          if (ok) {
            _showSnackBar('Stack deployed successfully!');
            _fetchData();
          } else {
            _showSnackBar('Failed to deploy stack.', isError: true);
          }
          return ok;
        },
      ),
    );
  }

  void _showNodeInspectDialog(Node n) {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        
        final encoder = const JsonEncoder.withIndent('  ');
        final labelsJson = encoder.convert(n.labels);

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 8, 16),
                  child: Row(
                    children: [
                      Icon(Icons.dns, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Node Details',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow('Node ID', n.id, theme),
                        const SizedBox(height: 16),
                        _detailRow('IP Address', n.ip, theme),
                        const SizedBox(height: 16),
                        _detailRow('Role', n.role.toUpperCase(), theme, isBadge: true),
                        const SizedBox(height: 16),
                        _detailRow('Status', n.status.toUpperCase(), theme, isBadge: true),
                        const SizedBox(height: 24),
                        Text(
                          'Labels',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: SelectableText(
                            labelsJson,
                            style: const TextStyle(
                              fontFamily: 'Courier New',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (n.createdAt.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _detailRow('Created At', n.createdAt, theme),
                        ],
                        if (n.updatedAt.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _detailRow('Last Heartbeat', n.updatedAt, theme),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, ThemeData theme, {bool isBadge = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        isBadge
            ? StatusBadge(label: value)
            : SelectableText(
                value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
      ],
    );
  }

  Future<void> _updateNodeRole(String id, String role) async {
    final ok = await ApiService.updateNodeRole(id, role);
    if (ok) {
      _showSnackBar('Node role updated successfully!');
      _fetchData();
    } else {
      _showSnackBar('Failed to update node role.', isError: true);
    }
  }

  Future<void> _updateNodeAvailability(String id, String availability) async {
    final ok = await ApiService.updateNodeAvailability(id, availability);
    if (ok) {
      _showSnackBar('Node availability updated successfully!');
      _fetchData();
    } else {
      _showSnackBar('Failed to update node availability.', isError: true);
    }
  }

  Future<void> _leaveNode(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force Node Leave'),
        content: const Text('Are you sure you want to force this node to leave the legion?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Force Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await ApiService.leaveNode(id);
      if (ok) {
        _showSnackBar('Node left the cluster successfully.');
        _fetchData();
      } else {
        _showSnackBar('Failed to remove node from cluster.', isError: true);
      }
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
                    child: ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final item = _sectionOrder.removeAt(oldIndex);
                          _sectionOrder.insert(newIndex, item);
                        });
                      },
                      children: _sectionOrder.map((section) {
                        Widget child;
                        switch (section) {
                          case 'stats':
                            child = _buildStatsRow(theme, running);
                            break;
                          case 'stacks_nodes':
                            child = _buildStacksAndNodesRow(theme);
                            break;
                          case 'tasks':
                            child = _buildTasksSection(theme);
                            break;
                          default:
                            child = const SizedBox.shrink();
                        }
                        return Padding(
                          key: ValueKey(section),
                          padding: const EdgeInsets.only(bottom: 24),
                          child: child,
                        );
                      }).toList(),
                    ),
                  ),
                ),
    );
  }

  // ─── Stats Row ──────────────────────────────────────────────────────
  Widget _buildStatsRow(ThemeData theme, int running) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Metrics Overview',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Icon(Icons.drag_indicator, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
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
            ),
          ],
        ),
      ),
    );
  }


  // ─── Legions + Centurions side by side ────────────────────────────
  Widget _buildStacksAndNodesRow(ThemeData theme) {
    // MediaQuery gives the true window/screen width.
    // We then subtract the outer SingleChildScrollView padding (24×2=48).
    final screenWidth = MediaQuery.of(context).size.width;
    const outerPadding = 48.0;
    const gap = 24.0;
    final availableWidth = screenWidth - outerPadding;

    // Narrow screen → stack vertically
    if (availableWidth <= 700) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStacksCard(theme),
          const SizedBox(height: gap),
          _buildNodesCard(theme),
        ],
      );
    }

    // Wide screen → side by side.
    // IMPORTANT: we wrap the Row in SizedBox(width: availableWidth) so that
    // the Row gets a **bounded** width parent. Without this explicit bound the
    // ReorderableListView passes maxWidth=∞ and the Row cannot lay out its
    // children correctly even when the children have explicit SizedBox widths.
    final cardWidth = (availableWidth - gap) / 2;
    return SizedBox(
      width: availableWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: cardWidth, child: _buildStacksCard(theme)),
          const SizedBox(width: gap),
          SizedBox(width: cardWidth, child: _buildNodesCard(theme)),
        ],
      ),
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
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Options',
                  onSelected: (val) {
                    if (val == 'deploy') {
                      _showNewStackDialog();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'deploy',
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 20),
                          SizedBox(width: 8),
                          Text('Deploy New Stack'),
                        ],
                      ),
                    ),
                  ],
                ),
                Icon(Icons.drag_indicator, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
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
                  sortColumnIndex: _stackSortColumnIndex,
                  sortAscending: _stackSortAscending,
                  columns: [
                    DataColumn(
                      label: const Text('ID'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _stackSortColumnIndex = columnIndex;
                          _stackSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('NAME'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _stackSortColumnIndex = columnIndex;
                          _stackSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('CREATED'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _stackSortColumnIndex = columnIndex;
                          _stackSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    const DataColumn(label: Text('ACTIONS')),
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
                const Spacer(),
                Icon(Icons.drag_indicator, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
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
                  sortColumnIndex: _nodeSortColumnIndex,
                  sortAscending: _nodeSortAscending,
                  columns: [
                    DataColumn(
                      label: const Text('ID'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _nodeSortColumnIndex = columnIndex;
                          _nodeSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('IP'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _nodeSortColumnIndex = columnIndex;
                          _nodeSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('ROLE'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _nodeSortColumnIndex = columnIndex;
                          _nodeSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('STATUS'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _nodeSortColumnIndex = columnIndex;
                          _nodeSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    const DataColumn(label: Text('ACTIONS')),
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
                      DataCell(
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          tooltip: 'Node Actions',
                          onSelected: (action) {
                            if (action == 'inspect') {
                              _showNodeInspectDialog(n);
                            } else if (action == 'promote') {
                              _updateNodeRole(n.id, 'manager');
                            } else if (action == 'demote') {
                              _updateNodeRole(n.id, 'worker');
                            } else if (action == 'active') {
                              _updateNodeAvailability(n.id, 'active');
                            } else if (action == 'pause') {
                              _updateNodeAvailability(n.id, 'pause');
                            } else if (action == 'drain') {
                              _updateNodeAvailability(n.id, 'drain');
                            } else if (action == 'leave') {
                              _leaveNode(n.id);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'inspect',
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Inspect'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            if (n.role == 'worker')
                              const PopupMenuItem(
                                value: 'promote',
                                child: Row(
                                  children: [
                                    Icon(Icons.trending_up, size: 18, color: Colors.green),
                                    SizedBox(width: 8),
                                    Text('Promote to Manager'),
                                  ],
                                ),
                              ),
                            if (n.role == 'manager')
                              const PopupMenuItem(
                                value: 'demote',
                                child: Row(
                                  children: [
                                    Icon(Icons.trending_down, size: 18, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Demote to Worker'),
                                  ],
                                ),
                              ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'active',
                              enabled: n.status != 'active',
                              child: const Row(
                                children: [
                                  Icon(Icons.play_arrow, size: 18, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text('Set Active'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'pause',
                              enabled: n.status != 'pause',
                              child: const Row(
                                children: [
                                  Icon(Icons.pause, size: 18, color: Colors.amber),
                                  SizedBox(width: 8),
                                  Text('Set Pause'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'drain',
                              enabled: n.status != 'drain',
                              child: const Row(
                                children: [
                                  Icon(Icons.delete_sweep, size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Set Drain'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'leave',
                              enabled: n.status != 'left',
                              child: const Row(
                                children: [
                                  Icon(Icons.exit_to_app, size: 18, color: Colors.redAccent),
                                  SizedBox(width: 8),
                                  Text('Force Leave'),
                                ],
                              ),
                            ),
                          ],
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
                const Spacer(),
                Icon(Icons.drag_indicator, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
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
                  sortColumnIndex: _taskSortColumnIndex,
                  sortAscending: _taskSortAscending,
                  columns: [
                    DataColumn(
                      label: const Text('TASK ID'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _taskSortColumnIndex = columnIndex;
                          _taskSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('SERVICE'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _taskSortColumnIndex = columnIndex;
                          _taskSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('CONTAINER'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _taskSortColumnIndex = columnIndex;
                          _taskSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('NODE'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _taskSortColumnIndex = columnIndex;
                          _taskSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('STATUS'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _taskSortColumnIndex = columnIndex;
                          _taskSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('IP'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _taskSortColumnIndex = columnIndex;
                          _taskSortAscending = ascending;
                          _applySorting();
                        });
                      },
                    ),
                    const DataColumn(label: Text('PORTS')),
                    const DataColumn(label: Text('ACTIONS')),
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
                            tooltip: 'Copy Task ID',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: t.id));
                              _showSnackBar('Copied Task ID to clipboard!');
                            },
                          ),
                        ],
                      )),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
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
                          ),
                          if (svc != null) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              tooltip: 'Copy Service ID',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: svc.id));
                                _showSnackBar('Copied Service ID to clipboard!');
                              },
                            ),
                          ],
                        ],
                      )),
                      DataCell(Text(t.containerName.isEmpty ? '-' : t.containerName,
                          style: const TextStyle(
                              fontFamily: 'Courier New', fontSize: 13))),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                              node != null && node.id.length > 8
                                  ? node.id.substring(0, 8)
                                  : node?.id ?? 'unknown',
                              style: const TextStyle(
                                  fontFamily: 'Courier New', fontSize: 13)),
                          if (node != null) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              tooltip: 'Copy Node ID',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: node.id));
                                _showSnackBar('Copied Node ID to clipboard!');
                              },
                            ),
                          ],
                        ],
                      )),
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
