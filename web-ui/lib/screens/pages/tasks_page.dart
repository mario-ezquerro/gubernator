import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/shell_dialog.dart';
import '../../utils/clipboard_service.dart';

/// Tasks page — PlutoGrid with bulk actions, search, and full container management.
class TasksPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;

  const TasksPage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  PlutoGridStateManager? _gridStateManager;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyColumnFilter(String columnField, String value) {
    if (_gridStateManager == null) return;
    final filterRow = FilterHelper.createFilterRow(
      columnField: columnField,
      filterType: const PlutoFilterTypeContains(),
      filterValue: value,
    );
    _gridStateManager!.setFilterWithFilterRows([filterRow]);
  }

  void _clearFilters() {
    if (_gridStateManager == null) return;
    _gridStateManager!.setFilterWithFilterRows([]);
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

  Future<void> _stopTask(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Container'),
        content: const Text('Stop this container?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.deleteTask(id);
    _showSnackBar(ok ? 'Container stopped.' : 'Failed to stop container.', isError: !ok);
    widget.onRefresh();
  }

  Future<void> _taskAction(String id, String action) async {
    final ok = await ApiService.taskAction(id, action);
    _showSnackBar(
      ok ? 'Action "$action" executed successfully.' : 'Failed to execute "$action".',
      isError: !ok,
    );
    widget.onRefresh();
  }

  Future<void> _viewTaskLogs(String id) async {
    try {
      final logs = await ApiService.taskLogs(id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Container Logs'),
          content: Container(
            width: double.maxFinite,
            height: 400,
            color: Colors.black,
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              child: Text(
                logs.isEmpty ? 'No logs available.' : logs,
                style: const TextStyle(fontFamily: 'Courier New', color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      _showSnackBar(e.toString(), isError: true);
    }
  }

  Future<void> _viewTaskInspect(String id) async {
    try {
      final inspectData = await ApiService.taskInspect(id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Container Details (Inspect)'),
          content: Container(
            width: double.maxFinite,
            height: 400,
            color: Colors.grey[900],
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              child: SelectableText(
                inspectData,
                style: const TextStyle(fontFamily: 'Courier New', color: Colors.greenAccent, fontSize: 12),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      _showSnackBar(e.toString(), isError: true);
    }
  }

  void _viewTaskShell(String id, String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ShellDialog(taskId: id, containerName: name),
    );
  }

  Future<void> _bulkAction(String action) async {
    final checkedRows = _gridStateManager?.checkedRows ?? [];
    if (checkedRows.isEmpty) return;
    final tasks = checkedRows
        .map((r) => r.cells['task_raw']?.value as Task?)
        .whereType<Task>()
        .toList();
    if (tasks.isEmpty) return;

    final actionLabel = action == 'delete' ? 'remove' : action;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bulk ${actionLabel.toUpperCase()} Containers'),
        content: Text('Are you sure you want to $actionLabel ${tasks.length} selected container(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: action == 'delete'
                ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                : null,
            child: Text(actionLabel.toUpperCase()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    int successCount = 0;
    for (final task in tasks) {
      bool ok = action == 'delete'
          ? await ApiService.deleteTask(task.id)
          : await ApiService.taskAction(task.id, action);
      if (ok) successCount++;
    }
    _showSnackBar('Bulk $actionLabel completed: $successCount / ${tasks.length} succeeded.');
    widget.onRefresh();
  }

  Widget _buildTaskActions(Task t) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'Actions',
      onSelected: (value) {
        switch (value) {
          case 'shell': _viewTaskShell(t.id, t.containerName); break;
          case 'logs': _viewTaskLogs(t.id); break;
          case 'inspect': _viewTaskInspect(t.id); break;
          case 'pause': _taskAction(t.id, 'pause'); break;
          case 'unpause': _taskAction(t.id, 'unpause'); break;
          case 'restart': _taskAction(t.id, 'restart'); break;
          case 'start': _taskAction(t.id, 'start'); break;
          case 'stop': _stopTask(t.id); break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (t.status == 'running')
          const PopupMenuItem<String>(value: 'shell', child: ListTile(leading: Icon(Icons.terminal, size: 20), title: Text('Shell'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem<String>(value: 'logs', child: ListTile(leading: Icon(Icons.notes, size: 20), title: Text('Logs'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem<String>(value: 'inspect', child: ListTile(leading: Icon(Icons.info_outline, size: 20), title: Text('View Details'), contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        if (t.status == 'running')
          const PopupMenuItem<String>(value: 'pause', child: ListTile(leading: Icon(Icons.pause, size: 20), title: Text('Pause'), contentPadding: EdgeInsets.zero))
        else if (t.status == 'paused')
          const PopupMenuItem<String>(value: 'unpause', child: ListTile(leading: Icon(Icons.play_arrow, size: 20), title: Text('Resume'), contentPadding: EdgeInsets.zero))
        else
          const PopupMenuItem<String>(value: 'start', child: ListTile(leading: Icon(Icons.play_arrow, size: 20), title: Text('Start'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem<String>(value: 'restart', child: ListTile(leading: Icon(Icons.refresh, size: 20), title: Text('Restart'), contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'stop', child: ListTile(leading: Icon(Icons.stop_circle, size: 20, color: Colors.red), title: Text('Stop', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero)),
      ],
    );
  }

  Widget _buildPortsCell(Service? svc, Node? node) {
    if (svc == null || svc.ports.isEmpty) {
      return const Text('-', style: TextStyle(color: Colors.grey));
    }
    final nodeIp = (node != null && node.ip.isNotEmpty) ? node.ip : 'localhost';
    final host = (nodeIp == '127.0.0.1') ? 'localhost' : nodeIp;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: svc.ports.map((portMapping) {
        final hostPort = portMapping.split(':').first;
        final url = 'http://$host:$hostPort';
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(
            avatar: Icon(Icons.open_in_new, size: 14, color: Theme.of(context).colorScheme.primary),
            label: Text(portMapping,
                style: TextStyle(fontSize: 12, fontFamily: 'Courier New', fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
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
          ),
        );
      }).toList(),
    );
  }

  String _timeAgo(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 0) return 'Up ${diff.inDays} days';
      if (diff.inHours > 0) return 'Up ${diff.inHours} hours';
      if (diff.inMinutes > 0) return 'Up ${diff.inMinutes} minutes';
      return 'Up ${diff.inSeconds} seconds';
    } catch (_) {
      return '-';
    }
  }

  String _formatCpu(Task t, Service? svc) {
    final limit = t.cpuLimit.isNotEmpty ? t.cpuLimit : (svc?.cpuLimit ?? '');
    final res = t.cpuReservation.isNotEmpty ? t.cpuReservation : (svc?.cpuReservation ?? '');
    if (limit.isNotEmpty && res.isNotEmpty) {
      return '$limit Core (min $res)';
    } else if (limit.isNotEmpty) {
      return '$limit Core';
    } else if (res.isNotEmpty) {
      return 'min $res Core';
    }
    return 'Unlimited';
  }

  String _formatMem(Task t, Service? svc) {
    final limit = t.memoryLimit.isNotEmpty ? t.memoryLimit : (svc?.memoryLimit ?? '');
    final res = t.memoryReservation.isNotEmpty ? t.memoryReservation : (svc?.memoryReservation ?? '');
    if (limit.isNotEmpty && res.isNotEmpty) {
      return '$limit (min $res)';
    } else if (limit.isNotEmpty) {
      return limit;
    } else if (res.isNotEmpty) {
      return 'min $res';
    }
    return 'Unlimited';
  }

  List<PlutoRow> _getPlutoRows(ThemeData theme) {
    final filteredTasks = widget.state.tasks.where((t) {
      if (_searchQuery.isEmpty) return true;
      final svc = widget.state.services.where((s) => s.id == t.serviceId).firstOrNull;
      final node = widget.state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
      return t.id.toLowerCase().contains(_searchQuery) ||
          t.containerName.toLowerCase().contains(_searchQuery) ||
          t.containerIp.toLowerCase().contains(_searchQuery) ||
          t.status.toLowerCase().contains(_searchQuery) ||
          (svc != null && svc.name.toLowerCase().contains(_searchQuery)) ||
          (svc != null && svc.image.toLowerCase().contains(_searchQuery)) ||
          (node != null && (node.id.toLowerCase().contains(_searchQuery) || node.ip.toLowerCase().contains(_searchQuery)));
    }).toList();

    return filteredTasks.map((t) {
      final svc = widget.state.services.where((s) => s.id == t.serviceId).firstOrNull;
      final stack = widget.state.stacks.where((s) => s.id == svc?.stackId).firstOrNull;
      final stackName = stack?.name ?? svc?.stackId ?? '-';
      final node = widget.state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
      final nodeVal = node != null ? '${node.id} (${node.ip})' : t.nodeId;

      return PlutoRow(cells: {
        'checkbox': PlutoCell(value: ''),
        'task_id': PlutoCell(value: t.id),
        'service': PlutoCell(value: svc?.name ?? 'unknown'),
        'stack': PlutoCell(value: stackName),
        'container': PlutoCell(value: t.containerName.isEmpty ? '-' : t.containerName),
        'node': PlutoCell(value: nodeVal),
        'status': PlutoCell(value: t.status),
        'cpu': PlutoCell(value: _formatCpu(t, svc)),
        'memory': PlutoCell(value: _formatMem(t, svc)),
        'ip': PlutoCell(value: t.containerIp.isEmpty ? '-' : t.containerIp),
        'created': PlutoCell(value: t.createdAt),
        'ports': PlutoCell(value: ''),
        'actions': PlutoCell(value: ''),
        'task_raw': PlutoCell(value: t),
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.state.tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text('No containers running', style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  )),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final checkedCount = _gridStateManager?.checkedRows.length ?? 0;
    final hasActiveFilters = _gridStateManager != null && _gridStateManager!.filterRows.isNotEmpty;

    final List<PlutoColumn> columns = [
      PlutoColumn(title: '', field: 'checkbox', type: PlutoColumnType.text(), width: 50, enableRowChecked: true, enableSorting: false, enableFilterMenuItem: false, enableContextMenu: false, enableDropToResize: false),
      PlutoColumn(title: 'CONTAINER ID', field: 'task_id', type: PlutoColumnType.text(), width: 120,
        renderer: (ctx) {
          final t = ctx.row.cells['task_raw']!.value as Task;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SelectableText(t.id.length > 8 ? t.id.substring(0, 8) : t.id, style: const TextStyle(fontFamily: 'Courier New', fontSize: 13)),
            const SizedBox(width: 4),
            IconButton(icon: const Icon(Icons.copy, size: 14), tooltip: 'Copy Container ID', padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              onPressed: () { ClipboardService.copy(t.id); _showSnackBar('Copied Container ID!'); }),
          ]);
        }),
      PlutoColumn(title: 'SERVICE', field: 'service', type: PlutoColumnType.text(), width: 200,
        renderer: (ctx) {
          final t = ctx.row.cells['task_raw']!.value as Task;
          final svc = widget.state.services.where((s) => s.id == t.serviceId).firstOrNull;
          final serviceName = svc?.name ?? 'unknown';
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              InkWell(
                onTap: () => _applyColumnFilter('service', serviceName),
                child: Tooltip(
                  message: 'Click to filter by service: $serviceName',
                  child: Text(
                    serviceName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              if (svc?.image != null) Text(svc!.image, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
            ]),
            if (svc != null) ...[
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.copy, size: 14), tooltip: 'Copy Service ID', padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onPressed: () { ClipboardService.copy(svc.id); _showSnackBar('Copied Service ID!'); }),
            ],
          ]);
        }),
      PlutoColumn(title: 'STACK', field: 'stack', type: PlutoColumnType.text(), width: 120,
        renderer: (ctx) {
          final stackName = ctx.cell.value as String;
          return Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => _applyColumnFilter('stack', stackName),
              child: Tooltip(
                message: 'Click to filter by stack: $stackName',
                child: Text(
                  stackName,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          );
        }),
      PlutoColumn(title: 'CONTAINER', field: 'container', type: PlutoColumnType.text(), width: 160),
      PlutoColumn(title: 'NODE', field: 'node', type: PlutoColumnType.text(), width: 180,
        renderer: (ctx) {
          final t = ctx.row.cells['task_raw']!.value as Task;
          final node = widget.state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
          final nodeId = node?.id ?? 'unknown';
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              InkWell(
                onTap: () => _applyColumnFilter('node', nodeId),
                child: Tooltip(
                  message: 'Click to filter by node: $nodeId',
                  child: Text(
                    nodeId,
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              if (node != null && node.ip.isNotEmpty) Text(node.ip, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontFamily: 'Courier New')),
            ]),
            if (node != null) ...[
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.copy, size: 14), tooltip: 'Copy Node ID', padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onPressed: () { ClipboardService.copy(node.id); _showSnackBar('Copied Node ID!'); }),
            ],
          ]);
        }),
      PlutoColumn(title: 'STATUS', field: 'status', type: PlutoColumnType.text(), width: 100,
        renderer: (ctx) => StatusBadge(label: ctx.cell.value as String)),
      PlutoColumn(title: 'CPU', field: 'cpu', type: PlutoColumnType.text(), width: 145,
        renderer: (ctx) {
          final val = ctx.cell.value as String;
          final isUnlimited = val == 'Unlimited';
          return Container(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isUnlimited
                    ? Colors.grey.withValues(alpha: 0.08)
                    : Colors.blueAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isUnlimited
                      ? Colors.grey.withValues(alpha: 0.2)
                      : Colors.blueAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.speed, size: 13, color: isUnlimited ? Colors.grey : Colors.blueAccent),
                  const SizedBox(width: 4),
                  Text(
                    val,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Courier New',
                      fontWeight: FontWeight.w600,
                      color: isUnlimited ? Colors.grey : Colors.blueAccent,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      PlutoColumn(title: 'MEMORY', field: 'memory', type: PlutoColumnType.text(), width: 145,
        renderer: (ctx) {
          final val = ctx.cell.value as String;
          final isUnlimited = val == 'Unlimited';
          return Container(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isUnlimited
                    ? Colors.grey.withValues(alpha: 0.08)
                    : Colors.teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isUnlimited
                      ? Colors.grey.withValues(alpha: 0.2)
                      : Colors.teal.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.memory, size: 13, color: isUnlimited ? Colors.grey : Colors.teal),
                  const SizedBox(width: 4),
                  Text(
                    val,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Courier New',
                      fontWeight: FontWeight.w600,
                      color: isUnlimited ? Colors.grey : Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      PlutoColumn(title: 'IP', field: 'ip', type: PlutoColumnType.text(), width: 120),
      PlutoColumn(title: 'CREATED', field: 'created', type: PlutoColumnType.text(), width: 120,
        renderer: (ctx) {
          final t = ctx.row.cells['task_raw']!.value as Task;
          return Text(_timeAgo(t.createdAt), style: const TextStyle(fontSize: 13, color: Colors.grey));
        }),
      PlutoColumn(title: 'PORTS', field: 'ports', type: PlutoColumnType.text(), width: 200,
        renderer: (ctx) {
          final t = ctx.row.cells['task_raw']!.value as Task;
          final svc = widget.state.services.where((s) => s.id == t.serviceId).firstOrNull;
          final node = widget.state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
          return _buildPortsCell(svc, node);
        }),
      PlutoColumn(title: 'ACTIONS', field: 'actions', type: PlutoColumnType.text(), width: 80, enableSorting: false,
        renderer: (ctx) {
          final t = ctx.row.cells['task_raw']!.value as Task;
          return _buildTaskActions(t);
        }),
    ];

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
                  Icon(Icons.view_in_ar, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text('Containers (Cohorts & Workloads)',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (hasActiveFilters) ...[
                    OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off, size: 16),
                      label: const Text('Clear Filters'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(color: theme.colorScheme.error),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (checkedCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_box, size: 16, color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 6),
                        Text('$checkedCount selected',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _bulkAction('start'),
                      icon: const Icon(Icons.play_arrow, size: 16, color: Colors.green),
                      label: const Text('Start'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: () => _bulkAction('stop'),
                      icon: const Icon(Icons.stop, size: 16, color: Colors.amber),
                      label: const Text('Stop'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: () => _bulkAction('restart'),
                      icon: const Icon(Icons.refresh, size: 16, color: Colors.blue),
                      label: const Text('Restart'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: () => _bulkAction('delete'),
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text('Remove'),
                      style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), visualDensity: VisualDensity.compact),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search containers, services, nodes, stacks...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PlutoGrid(
                      columns: columns,
                      rows: _getPlutoRows(theme),
                      createFooter: (stateManager) {
                        stateManager.setPageSize(25, notify: false);
                        return PlutoPagination(stateManager);
                      },
                      onRowChecked: (PlutoGridOnRowCheckedEvent event) => setState(() {}),
                      rowColorCallback: (rowColorContext) {
                        if (rowColorContext.rowIdx % 2 != 0) {
                          return theme.colorScheme.onSurface.withValues(alpha: 0.04);
                        }
                        return theme.brightness == Brightness.dark ? const Color(0xFF111111) : Colors.white;
                      },
                      onLoaded: (PlutoGridOnLoadedEvent event) {
                        _gridStateManager = event.stateManager;
                        _gridStateManager!.setShowColumnFilter(true);
                        _gridStateManager!.addListener(() {
                          if (mounted) setState(() {});
                        });
                      },
                      configuration: PlutoGridConfiguration(
                        style: theme.brightness == Brightness.dark
                            ? const PlutoGridStyleConfig.dark()
                            : const PlutoGridStyleConfig(),
                        columnSize: const PlutoGridColumnSizeConfig(autoSizeMode: PlutoAutoSizeMode.scale),
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
