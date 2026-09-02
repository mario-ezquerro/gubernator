import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/compose_editor.dart';
import '../../widgets/new_stack_dialog.dart';
import '../../widgets/stack_diagram_dialog.dart';
import '../../utils/clipboard_service.dart';

/// Legions page — full-width stacks table with all actions.
class LegionsPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;
  final ValueChanged<String>? onViewContainerLogs;
  final ValueChanged<String>? onViewStackContainers;

  const LegionsPage({
    super.key,
    required this.state,
    required this.onRefresh,
    this.onViewContainerLogs,
    this.onViewStackContainers,
  });

  @override
  State<LegionsPage> createState() => _LegionsPageState();
}

class _LegionsPageState extends State<LegionsPage> {
  String _searchQuery = '';
  int? _sortColumnIndex;
  bool _sortAscending = true;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _deleteStack(String id, String name) async {
    final isCore = id == 'core-gbnt-stack' || name.toLowerCase().contains('core-gbnt');
    final isMonitor = id == 'sre-monitor-stack' || name.toLowerCase().contains('monitor');

    final title = isCore ? 'Restart Core Stack'
        : isMonitor ? 'Stop Monitor Stack' : 'Delete Stack';
    final content = isCore
        ? 'Restart all core containers? This will not delete the stack or stop it permanently.'
        : isMonitor
            ? 'Stop and remove all monitor containers? The stack will remain in the dashboard for redeployment.'
            : 'Delete this stack and stop all its containers?';
    final actionText = isCore ? 'Restart' : isMonitor ? 'Stop' : 'Delete';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(actionText),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.deleteStack(id);
    final successMsg = isCore ? 'Core services restarted successfully!'
        : isMonitor ? 'Monitor containers stopped.' : 'Stack deleted and containers stopped.';
    final failMsg = isCore ? 'Failed to restart core services.'
        : isMonitor ? 'Failed to stop monitor.' : 'Failed to delete stack.';
    _showSnackBar(ok ? successMsg : failMsg, isError: !ok);
    widget.onRefresh();
  }

  Future<void> _redeployStack(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeploy Stack'),
        content: const Text('Stop existing containers and redeploy this stack?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Redeploy')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.redeployStack(id);
    _showSnackBar(ok ? 'Stack redeployed!' : 'Redeploy failed.', isError: !ok);
    widget.onRefresh();
  }

  Future<void> _duplicateStack(StackModel stack) async {
    try {
      final yaml = await ApiService.getStackCompose(stack.id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => NewStackDialog(
          initialName: '${stack.name}-copy',
          initialYaml: yaml,
          nodes: widget.state.nodes,
          onDeploy: (name, compose, targetNode) async {
            final errorMsg = await ApiService.deployStack(name, compose, targetNode: targetNode);
            if (errorMsg == null) {
              _showSnackBar('Stack duplicated and deployed successfully!');
              widget.onRefresh();
            }
            return errorMsg;
          },
        ),
      );
    } catch (e) {
      _showSnackBar('Failed to load original stack compose file', isError: true);
    }
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
          nodes: widget.state.nodes,
          onSave: (y) => ApiService.updateStackCompose(stack.id, y),
          onRedeploy: (_) async {
            final ok = await ApiService.redeployStack(stack.id);
            widget.onRefresh();
            return ok;
          },
        ),
      );
    } catch (e) {
      _showSnackBar('Failed to load compose file', isError: true);
    }
  }

  Future<void> _showStackLogsDialog(StackModel s) async {
    showDialog(
      context: context,
      builder: (ctx) => _StackDiagnosticsDialog(
        stack: s,
        state: widget.state,
        onRefreshState: widget.onRefresh,
        onViewContainerLogs: widget.onViewContainerLogs,
      ),
    );
  }

  void _showMigrateStackDialog(StackModel s) {
    final activeNodes = widget.state.nodes
        .where((n) => n.status == 'active' || n.status == 'ready')
        .toList();
    if (activeNodes.isEmpty) {
      _showSnackBar('No active nodes available to migrate stack', isError: true);
      return;
    }
    String selectedNodeId = activeNodes.first.id;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.swap_horiz, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text('Migrate Stack: ${s.name}'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select the target host to move this stack to. All containers for "${s.name}" '
                'will be removed from their current host and redeployed on the selected target node.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('Target Node:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedNodeId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: activeNodes.map((n) {
                  final label = '${n.id} (${n.ip}) [${n.role.toUpperCase()}]';
                  return DropdownMenuItem<String>(
                    value: n.id,
                    child: Text(label, style: const TextStyle(fontSize: 13, fontFamily: 'Courier New')),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedNodeId = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Migrate Stack'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final ok = await ApiService.migrateStack(s.id, selectedNodeId);
                if (ok) {
                  _showSnackBar('Stack "${s.name}" successfully migrated to $selectedNodeId');
                  widget.onRefresh();
                } else {
                  _showSnackBar('Failed to migrate stack "${s.name}"', isError: true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNewStackDialog() {
    showDialog(
      context: context,
      builder: (ctx) => NewStackDialog(
        nodes: widget.state.nodes,
        onDeploy: (name, yaml, targetNode) async {
          final errorMsg = await ApiService.deployStack(name, yaml, targetNode: targetNode);
          if (errorMsg == null) {
            _showSnackBar('Stack deployed successfully!');
            widget.onRefresh();
          }
          return errorMsg;
        },
      ),
    );
  }

  void _showStackDiagramDialog(StackModel s) {
    showDialog(
      context: context,
      builder: (ctx) => StackDiagramDialog(
        stack: s,
        services: widget.state.services,
        tasks: widget.state.tasks,
        nodes: widget.state.nodes,
      ),
    );
  }

  Widget _actionBtn(IconData icon, String tooltip, Color color, VoidCallback onPressed) {
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

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<StackModel> filteredStacks = widget.state.stacks.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.id.toLowerCase().contains(_searchQuery) ||
          s.name.toLowerCase().contains(_searchQuery);
    }).toList();

    // Apply sorting
    if (_sortColumnIndex != null) {
      Comparable Function(StackModel s) getField;
      switch (_sortColumnIndex) {
        case 0: getField = (s) => s.id; break;
        case 1: getField = (s) => s.name; break;
        case 2: getField = (s) => s.createdAt; break;
        default: getField = (s) => s.id;
      }
      filteredStacks.sort((a, b) {
        final aVal = getField(_sortAscending ? a : b);
        final bVal = getField(_sortAscending ? b : a);
        return Comparable.compare(aVal, bVal);
      });
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.layers, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text('Legions (Stacks)',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Deploy Stack'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _showNewStackDialog,
                  ),
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
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filteredStacks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.layers_clear, size: 48,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text(
                              widget.state.stacks.isEmpty
                                  ? 'No stacks deployed yet'
                                  : 'No matching stacks found',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Scrollbar(
                        controller: _verticalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalScrollController,
                          scrollDirection: Axis.vertical,
                          child: Scrollbar(
                            controller: _horizontalScrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _horizontalScrollController,
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _sortAscending,
                            columns: [
                              DataColumn(
                                label: const Text('ID'),
                                onSort: (col, asc) => setState(() {
                                  _sortColumnIndex = col;
                                  _sortAscending = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('NAME'),
                                onSort: (col, asc) => setState(() {
                                  _sortColumnIndex = col;
                                  _sortAscending = asc;
                                }),
                              ),
                              DataColumn(
                                label: const Text('CREATED'),
                                onSort: (col, asc) => setState(() {
                                  _sortColumnIndex = col;
                                  _sortAscending = asc;
                                }),
                              ),
                              const DataColumn(label: Text('CONTAINERS')),
                              const DataColumn(label: Text('ACTIONS')),
                            ],
                            rows: filteredStacks.map((s) {
                              final stackTasks = widget.state.tasks.where((t) {
                                final svc = widget.state.services.where((sv) => sv.id == t.serviceId).firstOrNull;
                                return svc?.stackId == s.id;
                              }).toList();
                              final runningCount = stackTasks.where((t) => t.status == 'running').length;

                              return DataRow(cells: [
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SelectableText(
                                      s.id.length > 8 ? s.id.substring(0, 8) : s.id,
                                      style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 14),
                                      tooltip: 'Copy full ID',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        ClipboardService.copy(s.id);
                                        _showSnackBar('Copied Stack ID to clipboard!');
                                      },
                                    ),
                                  ],
                                )),
                                DataCell(
                                   InkWell(
                                     onTap: () => widget.onViewStackContainers?.call(s.name),
                                     borderRadius: BorderRadius.circular(4),
                                     child: Tooltip(
                                       message: 'Click to view containers for ${s.name}',
                                       child: Padding(
                                         padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                         child: Row(
                                           mainAxisSize: MainAxisSize.min,
                                           children: [
                                             Text(
                                               s.name,
                                               style: TextStyle(
                                                 fontWeight: FontWeight.w600,
                                                 color: Theme.of(context).colorScheme.primary,
                                                 decoration: TextDecoration.underline,
                                                 decorationStyle: TextDecorationStyle.dotted,
                                               ),
                                             ),
                                             const SizedBox(width: 4),
                                             Icon(
                                               Icons.arrow_forward_rounded,
                                               size: 13,
                                               color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                             ),
                                           ],
                                         ),
                                       ),
                                     ),
                                   ),
                                 ),
                                 DataCell(Text(_formatDate(s.createdAt))),
                                 DataCell(
                                   InkWell(
                                     onTap: () => widget.onViewStackContainers?.call(s.name),
                                     borderRadius: BorderRadius.circular(10),
                                     child: Tooltip(
                                       message: 'View $runningCount/${stackTasks.length} containers for ${s.name}',
                                       child: Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                         decoration: BoxDecoration(
                                           color: runningCount == stackTasks.length && stackTasks.isNotEmpty
                                               ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                               : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                                           borderRadius: BorderRadius.circular(10),
                                           border: Border.all(
                                             color: runningCount == stackTasks.length && stackTasks.isNotEmpty
                                                 ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                                 : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                           ),
                                         ),
                                         child: Row(
                                           mainAxisSize: MainAxisSize.min,
                                           children: [
                                             Text(
                                               '$runningCount/${stackTasks.length}',
                                               style: TextStyle(
                                                 fontSize: 12,
                                                 fontWeight: FontWeight.w600,
                                                 color: runningCount == stackTasks.length && stackTasks.isNotEmpty
                                                     ? const Color(0xFF10B981)
                                                     : const Color(0xFFF59E0B),
                                               ),
                                             ),
                                             const SizedBox(width: 4),
                                             Icon(
                                               Icons.visibility_outlined,
                                               size: 12,
                                               color: runningCount == stackTasks.length && stackTasks.isNotEmpty
                                                   ? const Color(0xFF10B981)
                                                   : const Color(0xFFF59E0B),
                                             ),
                                           ],
                                         ),
                                       ),
                                     ),
                                   ),
                                 ),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _actionBtn(Icons.receipt_long, 'View Stack Logs & Placement Errors',
                                        const Color(0xFF8B5CF6), () => _showStackLogsDialog(s)),
                                    _actionBtn(Icons.schema_outlined, 'View Schema',
                                        const Color(0xFFFB923C), () => _showStackDiagramDialog(s)),
                                    _actionBtn(Icons.code, 'Edit YAML',
                                        const Color(0xFFF97316), () => _openComposeEditor(s)),
                                    (s.id == 'core-gbnt-stack' || s.id == 'sre-monitor-stack' ||
                                            s.name.toLowerCase().contains('core-gbnt') ||
                                            s.name.toLowerCase().contains('monitor'))
                                        ? const SizedBox(width: 36)
                                        : _actionBtn(Icons.copy, 'Duplicate',
                                            const Color(0xFF10B981), () => _duplicateStack(s)),
                                    _actionBtn(Icons.rocket_launch, 'Redeploy',
                                        const Color(0xFFD29922), () => _redeployStack(s.id)),
                                    if (s.id != 'core-gbnt-stack' && s.id != 'sre-monitor-stack' &&
                                        !s.name.toLowerCase().contains('core-gbnt') &&
                                        !s.name.toLowerCase().contains('monitor'))
                                      _actionBtn(Icons.swap_horiz, 'Change Target Host',
                                          const Color(0xFF3B82F6), () => _showMigrateStackDialog(s)),
                                    _actionBtn(
                                      Icons.delete,
                                      (s.id == 'core-gbnt-stack' || s.name.toLowerCase().contains('core-gbnt'))
                                          ? 'Restart Core (Does not delete)'
                                          : (s.id == 'sre-monitor-stack' || s.name.toLowerCase().contains('monitor'))
                                              ? 'Stop Monitor (Keeps stack)'
                                              : 'Delete',
                                      const Color(0xFFEF4444),
                                      () => _deleteStack(s.id, s.name),
                                    ),
                                  ],
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StackDiagnosticsDialog extends StatefulWidget {
  final StackModel stack;
  final DashboardState state;
  final VoidCallback onRefreshState;
  final ValueChanged<String>? onViewContainerLogs;

  const _StackDiagnosticsDialog({
    required this.stack,
    required this.state,
    required this.onRefreshState,
    this.onViewContainerLogs,
  });

  @override
  State<_StackDiagnosticsDialog> createState() => _StackDiagnosticsDialogState();
}

class _StackDiagnosticsDialogState extends State<_StackDiagnosticsDialog> {
  final Map<String, String> _taskLogs = {};
  final Map<String, bool> _loadingLogs = {};
  final Set<String> _expandedLogs = {};
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadAllLogs();
  }

  Future<void> _loadAllLogs() async {
    final tasks = _getStackTasks();
    for (final t in tasks) {
      _fetchLogsForTask(t.id);
    }
  }

  List<Task> _getStackTasks() {
    return widget.state.tasks.where((t) {
      final svc = widget.state.services.where((sv) => sv.id == t.serviceId).firstOrNull;
      return svc?.stackId == widget.stack.id;
    }).toList();
  }

  Future<void> _fetchLogsForTask(String taskId) async {
    setState(() {
      _loadingLogs[taskId] = true;
    });
    try {
      final logs = await ApiService.getTaskLogs(taskId);
      if (mounted) {
        setState(() {
          _taskLogs[taskId] = logs;
          _loadingLogs[taskId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _taskLogs[taskId] = 'Failed to load logs: $e';
          _loadingLogs[taskId] = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    widget.onRefreshState();
    await Future.delayed(const Duration(milliseconds: 600));
    await _loadAllLogs();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stackTasks = _getStackTasks();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long, color: Color(0xFF8B5CF6)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stack Logs & Diagnostics: ${widget.stack.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Real-time container output logs, image download progress, and placement diagnostics',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Diagnostics & Logs',
            onPressed: _isRefreshing ? null : _refresh,
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 540,
        child: stackTasks.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox, size: 48, color: Colors.grey.shade600),
                    const SizedBox(height: 12),
                    Text(
                      'No container tasks currently registered for stack "${widget.stack.name}".',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: stackTasks.length,
                itemBuilder: (context, index) {
                  final task = stackTasks[index];
                  final service = widget.state.services.where((sv) => sv.id == task.serviceId).firstOrNull;
                  final statusLower = task.status.toLowerCase();
                  final isRunning = statusLower == 'running';
                  final isPulling = statusLower == 'pulling';
                  final isStarting = statusLower == 'starting';
                  final isDead = statusLower == 'dead' || statusLower == 'failed';
                  final isExpanded = _expandedLogs.contains(task.id);
                  final logs = _taskLogs[task.id];
                  final isLoading = _loadingLogs[task.id] == true;

                  Color statusColor = Colors.orangeAccent;
                  IconData statusIcon = Icons.sync;
                  if (isRunning) {
                    statusColor = const Color(0xFF10B981);
                    statusIcon = Icons.check_circle;
                  } else if (isPulling) {
                    statusColor = const Color(0xFF3B82F6);
                    statusIcon = Icons.cloud_download;
                  } else if (isStarting) {
                    statusColor = const Color(0xFFF59E0B);
                    statusIcon = Icons.play_circle_outline;
                  } else if (isDead) {
                    statusColor = Colors.redAccent;
                    statusIcon = Icons.error_outline;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isDead ? Colors.red.withValues(alpha: 0.06) : const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isDead
                            ? Colors.red.withValues(alpha: 0.3)
                            : (isRunning ? const Color(0xFF10B981).withValues(alpha: 0.25) : Colors.white10),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(statusIcon, color: statusColor, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Service: ${service?.name ?? task.serviceId}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isPulling || isStarting) ...[
                                      SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      task.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Host: ${task.nodeId}',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'Courier New', color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                          if (task.containerName.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'Container: ${task.containerName}',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'Courier New', color: Colors.white70),
                                ),
                                const Spacer(),
                                if (widget.onViewContainerLogs != null)
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      widget.onViewContainerLogs!(task.containerName);
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF8B5CF6)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.receipt_long, size: 12, color: Color(0xFF8B5CF6)),
                                          SizedBox(width: 4),
                                          Text(
                                            'Loki Stream Explorer',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF8B5CF6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (task.error != null && task.error!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: isDead
                                    ? Colors.red.withValues(alpha: 0.12)
                                    : const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isDead
                                      ? Colors.red.withValues(alpha: 0.3)
                                      : const Color(0xFF3B82F6).withValues(alpha: 0.3),
                                ),
                              ),
                              child: SelectableText(
                                isDead ? '⚠️ Error: ${task.error}' : '⏳ ${task.error}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Courier New',
                                  color: isDead ? Colors.redAccent : const Color(0xFF60A5FA),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Collapsible Terminal Logs Section
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedLogs.remove(task.id);
                                    } else {
                                      _expandedLogs.add(task.id);
                                      if (_taskLogs[task.id] == null) {
                                        _fetchLogsForTask(task.id);
                                      }
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                        size: 16,
                                        color: const Color(0xFF8B5CF6),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isExpanded ? 'Hide Output Logs' : 'View Container Logs (stdout/stderr)',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF8B5CF6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (isExpanded) ...[
                                IconButton(
                                  icon: const Icon(Icons.refresh, size: 14),
                                  tooltip: 'Reload Container Logs',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  onPressed: () => _fetchLogsForTask(task.id),
                                ),
                                if (logs != null && logs.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 14),
                                    tooltip: 'Copy Output Logs',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () async {
                                      await ClipboardService.copy(logs);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Container logs copied to clipboard'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ],
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 180),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: isLoading
                                  ? const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      child: SelectableText(
                                        (logs != null && logs.trim().isNotEmpty)
                                            ? logs
                                            : '(No stdout/stderr logs produced yet)',
                                        style: const TextStyle(
                                          fontFamily: 'Courier New',
                                          fontSize: 11,
                                          color: Color(0xFFE2E8F0),
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
