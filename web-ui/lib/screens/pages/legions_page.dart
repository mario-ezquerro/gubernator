import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/compose_editor.dart';
import '../../widgets/new_stack_dialog.dart';
import '../../widgets/stack_diagram_dialog.dart';
import '../../widgets/server_stack_picker_dialog.dart';
import '../../widgets/poc_examples_dialog.dart';
import '../../widgets/port_conflict_dialog.dart';
import '../../widgets/autoscale_dialog.dart';
import '../../widgets/save_server_stack_dialog.dart';
import '../../widgets/save_pc_stack_dialog.dart';
import '../../utils/clipboard_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/shell_dialog.dart';
import '../../widgets/common_widgets.dart';

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
  String _selectedGroup = 'deployed'; // 'deployed', 'base', 'all'
  int? _sortColumnIndex;
  bool _sortAscending = true;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final Set<String> _processingStackIds = {};
  final Set<String> _expandedStackIds = {};

  bool _isBaseStack(StackModel s) {
    final id = s.id.toLowerCase();
    final name = s.name.toLowerCase();
    return id == 'core-gbnt-stack' ||
        id == 'sre-monitor-stack' ||
        id == 'super-net-topology-mgr' ||
        id.startsWith('core-') ||
        id.startsWith('sre-') ||
        id.startsWith('super-') ||
        name.contains('core-gbnt') ||
        name == 'core' ||
        name.contains('monitor') ||
        name.contains('[sre]') ||
        name == 'sre' ||
        name.contains('topology') ||
        name.contains('[super]') ||
        name.contains('[base]') ||
        name.contains('scope');
  }

  Future<void> _stopStack(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.stop_circle_outlined, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Expanded(child: Text('Stop Stack: $name')),
          ],
        ),
        content: Text(
          'Stop all running containers for stack "$name"?\n\n'
          'The stack definition and service configuration will remain saved in Gubernator and can be started again at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            child: const Text('Stop Stack'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _processingStackIds.add(id));
    _showSnackBar('Stopping stack "$name"...');
    final ok = await ApiService.stopStack(id);
    if (mounted) {
      setState(() => _processingStackIds.remove(id));
    }
    if (ok) {
      _showSnackBar('Stack "$name" stopped successfully.');
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to stop stack "$name".', isError: true);
    }
  }

  Future<void> _startStack(String id, String name) async {
    setState(() => _processingStackIds.add(id));
    _showSnackBar('Starting stack "$name"...');
    final ok = await ApiService.startStack(id);
    if (mounted) {
      setState(() => _processingStackIds.remove(id));
    }
    if (ok) {
      _showSnackBar('Stack "$name" started successfully.');
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to start stack "$name".', isError: true);
    }
  }

  Future<void> _restartStack(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.refresh, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Expanded(child: Text('Restart Stack: $name')),
          ],
        ),
        content: Text(
          'Restart all containers for stack "$name"?\n\n'
          'All running workloads will be restarted and container health will be re-verified.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
            child: const Text('Restart Stack'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _processingStackIds.add(id));
    _showSnackBar('Restarting stack "$name"...');
    final ok = await ApiService.restartStack(id);
    if (mounted) {
      setState(() => _processingStackIds.remove(id));
    }
    if (ok) {
      _showSnackBar('Stack "$name" restarted successfully.');
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to restart stack "$name".', isError: true);
    }
  }

  Future<void> _reconcileStack(String id, String name) async {
    setState(() => _processingStackIds.add(id));
    _showSnackBar('Reconciling stack "$name" and purging stale containers...');
    final res = await ApiService.reconcileStack(id);
    if (mounted) {
      setState(() => _processingStackIds.remove(id));
    }
    if (res != null) {
      final msg = res['message'] ?? 'Stack "$name" reconciled successfully.';
      _showSnackBar(msg.toString());
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to reconcile stack "$name".', isError: true);
    }
  }

  Future<void> _pruneAllTasks() async {
    _showSnackBar('Reconciling cluster stacks and pruning stale containers...');
    final res = await ApiService.pruneTasks();
    if (res != null) {
      final msg = res['message'] ?? 'Cluster reconciliation complete.';
      _showSnackBar(msg.toString());
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to reconcile cluster tasks.', isError: true);
    }
  }

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

  String _timeAgo(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 0) return 'Up ${diff.inDays} days';
      if (diff.inHours > 0) return 'Up ${diff.inHours} hours';
      if (diff.inMinutes > 0) return 'Up ${diff.inMinutes} mins';
      return 'Up ${diff.inSeconds} secs';
    } catch (_) {
      return '-';
    }
  }

  Future<void> _taskAction(String id, String action) async {
    final ok = await ApiService.taskAction(id, action);
    if (ok) {
      _showSnackBar('Container $action executed successfully.');
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to $action container.', isError: true);
    }
  }

  Future<void> _stopTask(String id) async {
    final ok = await ApiService.taskAction(id, 'stop');
    if (ok) {
      _showSnackBar('Container stopped successfully.');
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to stop container.', isError: true);
    }
  }

  Future<void> _deleteTask(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Container'),
        content: const Text('Are you sure you want to remove this container?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.deleteTask(id);
    if (ok) {
      _showSnackBar('Container removed successfully.');
      widget.onRefresh();
    } else {
      _showSnackBar('Failed to remove container.', isError: true);
    }
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

  void _showTaskAutoscaleDialog(Task t) {
    final svc = widget.state.services.where((s) => s.id == t.serviceId).firstOrNull;
    final stack = widget.state.stacks.where((st) => st.id == svc?.stackId).firstOrNull;
    showDialog(
      context: context,
      builder: (ctx) => AutoscaleControlDialog(
        stack: stack,
        service: svc,
        onSaved: widget.onRefresh,
      ),
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
            avatar: Icon(Icons.open_in_new, size: 13, color: Theme.of(context).colorScheme.primary),
            label: Text(portMapping,
                style: TextStyle(fontSize: 11, fontFamily: 'Courier New', fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
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

  Widget _buildTaskActions(Task t) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Container Actions',
      onSelected: (value) {
        switch (value) {
          case 'autoscale': _showTaskAutoscaleDialog(t); break;
          case 'shell': _viewTaskShell(t.id, t.containerName); break;
          case 'logs': _viewTaskLogs(t.id); break;
          case 'inspect': _viewTaskInspect(t.id); break;
          case 'pause': _taskAction(t.id, 'pause'); break;
          case 'unpause': _taskAction(t.id, 'unpause'); break;
          case 'restart': _taskAction(t.id, 'restart'); break;
          case 'start': _taskAction(t.id, 'start'); break;
          case 'stop': _stopTask(t.id); break;
          case 'delete': _deleteTask(t.id); break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'autoscale',
          child: ListTile(
            leading: Icon(Icons.bolt, size: 18, color: Color(0xFFA855F7)),
            title: Text('Autoscale Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        if (t.status == 'running')
          const PopupMenuItem<String>(value: 'shell', child: ListTile(leading: Icon(Icons.terminal, size: 18), title: Text('Shell'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem<String>(value: 'logs', child: ListTile(leading: Icon(Icons.notes, size: 18), title: Text('Logs'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem<String>(value: 'inspect', child: ListTile(leading: Icon(Icons.info_outline, size: 18), title: Text('View Details'), contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        if (t.status == 'running')
          const PopupMenuItem<String>(value: 'pause', child: ListTile(leading: Icon(Icons.pause, size: 18), title: Text('Pause'), contentPadding: EdgeInsets.zero))
        else if (t.status == 'paused')
          const PopupMenuItem<String>(value: 'unpause', child: ListTile(leading: Icon(Icons.play_arrow, size: 18), title: Text('Resume'), contentPadding: EdgeInsets.zero))
        else
          const PopupMenuItem<String>(value: 'start', child: ListTile(leading: Icon(Icons.play_arrow, size: 18), title: Text('Start'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem<String>(value: 'restart', child: ListTile(leading: Icon(Icons.refresh, size: 18), title: Text('Restart'), contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'stop', child: ListTile(leading: Icon(Icons.stop_circle, size: 18, color: Colors.orange), title: Text('Stop', style: TextStyle(color: Colors.orange)), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete, size: 18, color: Colors.red), title: Text('Remove', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero)),
      ],
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
            final res = await deployWithConflictResolution(
              context: ctx,
              stackName: name,
              compose: compose,
              targetNode: targetNode,
            );
            if (res.success) {
              _showSnackBar('Stack duplicated and deployed successfully!');
              widget.onRefresh();
              return null;
            }
            return res.error;
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

  Future<void> _downloadStackYaml(StackModel s) async {
    try {
      final yaml = await ApiService.getStackCompose(s.id);
      if (!mounted) return;
      await showSavePcStackDialog(
        context: context,
        initialName: s.name,
        yamlContent: yaml,
      );
    } catch (e) {
      _showSnackBar('Failed to download compose file: $e', isError: true);
    }
  }

  Future<void> _saveStackToServer(StackModel s) async {
    try {
      final yaml = await ApiService.getStackCompose(s.id);
      if (!mounted) return;
      final savedPath = await showSaveServerStackDialog(
        context: context,
        initialName: s.name,
        yamlContent: yaml,
      );
      if (savedPath != null && mounted) {
        _showSnackBar('Saved "${s.name}" to Master server: $savedPath');
      }
    } catch (e) {
      _showSnackBar('Failed to load compose file: $e', isError: true);
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

  void _showAutoscaleDialog(StackModel s) {
    final stackServices = widget.state.services.where((svc) => svc.stackId == s.id).toList();
    showDialog(
      context: context,
      builder: (ctx) => AutoscaleControlDialog(
        stack: s,
        stackServices: stackServices,
        onSaved: widget.onRefresh,
      ),
    );
  }

  void _showNewStackDialog() {
    showDialog(
      context: context,
      builder: (ctx) => NewStackDialog(
        nodes: widget.state.nodes,
        onDeploy: (name, yaml, targetNode) async {
          final res = await deployWithConflictResolution(
            context: ctx,
            stackName: name,
            compose: yaml,
            targetNode: targetNode,
          );
          if (res.success) {
            _showSnackBar('Stack deployed successfully!');
            widget.onRefresh();
            return null;
          }
          return res.error;
        },
      ),
    );
  }

  void _showServerStackPicker() {
    showDialog(
      context: context,
      builder: (ctx) => ServerStackPickerDialog(
        onSelect: (name, yaml) {
          showDialog(
            context: context,
            builder: (ctx2) => NewStackDialog(
              nodes: widget.state.nodes,
              initialName: name,
              initialYaml: yaml,
              onDeploy: (n, y, target) async {
                final res = await deployWithConflictResolution(
                  context: ctx2,
                  stackName: n,
                  compose: y,
                  targetNode: target,
                );
                if (res.success) {
                  _showSnackBar('Stack deployed successfully!');
                  widget.onRefresh();
                  return null;
                }
                return res.error;
              },
            ),
          );
        },
        onDirectDeploy: (path, name) async {
          final err = await ApiService.deployServerStack(path, name: name);
          if (err == null) {
            _showSnackBar('🚀 Stack "$name" deployed from Master server ($path)!');
            widget.onRefresh();
          } else {
            _showSnackBar('Failed: $err');
          }
        },
      ),
    );
  }

  void _showPOCExamples() {
    showDialog(
      context: context,
      builder: (ctx) => POCExamplesDialog(
        nodes: widget.state.nodes,
        onOpenInStudio: (name, yaml) {
          showDialog(
            context: context,
            builder: (ctx2) => NewStackDialog(
              nodes: widget.state.nodes,
              initialName: name,
              initialYaml: yaml,
              onDeploy: (n, y, target) async {
                final res = await deployWithConflictResolution(
                  context: ctx2,
                  stackName: n,
                  compose: y,
                  targetNode: target,
                );
                if (res.success) {
                  _showSnackBar('POC Blueprint "$n" deployed successfully!');
                  widget.onRefresh();
                  return null;
                }
                return res.error;
              },
            ),
          );
        },
        onStackDeployed: widget.onRefresh,
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
    final allMatching = widget.state.stacks.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.id.toLowerCase().contains(_searchQuery) ||
          s.name.toLowerCase().contains(_searchQuery);
    }).toList();

    final deployedCount = widget.state.stacks.where((s) => !_isBaseStack(s)).length;
    final baseCount = widget.state.stacks.where((s) => _isBaseStack(s)).length;

    List<StackModel> filteredStacks;
    if (_selectedGroup == 'deployed') {
      filteredStacks = allMatching.where((s) => !_isBaseStack(s)).toList();
    } else if (_selectedGroup == 'base') {
      filteredStacks = allMatching.where((s) => _isBaseStack(s)).toList();
    } else {
      filteredStacks = allMatching;
    }

    // Apply sorting
    if (_sortColumnIndex != null) {
      Comparable Function(StackModel s) getField;
      switch (_sortColumnIndex) {
        case 1: getField = (s) => s.id; break;
        case 2: getField = (s) => s.name; break;
        case 4: getField = (s) => s.nodeId; break;
        case 5: getField = (s) => s.createdAt; break;
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
                  Tooltip(
                    message: 'Reconcile all stacks and purge dead/stale containers across the cluster',
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cleaning_services_outlined, size: 16, color: Color(0xFF06B6D4)),
                      label: const Text('Reconcile & Prune', style: TextStyle(color: Color(0xFF06B6D4))),
                      onPressed: _pruneAllTasks,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.dns, size: 16, color: Color(0xFF58A6FF)),
                    label: const Text('Master Server File', style: TextStyle(color: Color(0xFF58A6FF))),
                    onPressed: _showServerStackPicker,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.rocket_launch, size: 16, color: Color(0xFFE3B341)),
                    label: const Text('POC Blueprints', style: TextStyle(color: Color(0xFFE3B341), fontWeight: FontWeight.bold)),
                    onPressed: _showPOCExamples,
                  ),
                  const SizedBox(width: 8),
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
              Row(
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'deployed',
                        icon: const Icon(Icons.rocket_launch, size: 15, color: Color(0xFF38BDF8)),
                        label: Text('Deployed Apps ($deployedCount)'),
                      ),
                      ButtonSegment(
                        value: 'base',
                        icon: const Icon(Icons.foundation, size: 15, color: Color(0xFF8B5CF6)),
                        label: Text('Base Stacks ($baseCount)'),
                      ),
                      ButtonSegment(
                        value: 'all',
                        icon: const Icon(Icons.layers_outlined, size: 15),
                        label: Text('All (${widget.state.stacks.length})'),
                      ),
                    ],
                    selected: {_selectedGroup},
                    onSelectionChanged: (newSelection) {
                      setState(() => _selectedGroup = newSelection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search stacks by name or ID...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                    ),
                  ),
                ],
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
                                  : 'No matching stacks found in this group',
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
                                label: Tooltip(
                                  message: _expandedStackIds.isEmpty ? 'Expand all stacks' : 'Collapse all stacks',
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (_expandedStackIds.length >= filteredStacks.length && filteredStacks.isNotEmpty) {
                                          _expandedStackIds.clear();
                                        } else {
                                          _expandedStackIds.addAll(filteredStacks.map((s) => s.id));
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                      ),
                                      child: Icon(
                                        _expandedStackIds.isEmpty ? Icons.unfold_more : Icons.unfold_less,
                                        size: 15,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                              const DataColumn(label: Text('AUTOSCALE')),
                              DataColumn(
                                label: const Text('HOST NODE'),
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
                            rows: [
                              for (final s in filteredStacks) ...[
                                _buildStackRow(s, theme),
                                if (_expandedStackIds.contains(s.id))
                                  ..._buildContainerRowsForStack(s, theme),
                              ],
                            ],
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

  DataRow _buildStackRow(StackModel s, ThemeData theme) {
    final isExpanded = _expandedStackIds.contains(s.id);
    final isBase = _isBaseStack(s);
    final stackTasks = widget.state.tasks.where((t) {
      final svc = widget.state.services.where((sv) => sv.id == t.serviceId).firstOrNull;
      return svc?.stackId == s.id;
    }).toList();
    final runningCount = stackTasks.where((t) => t.status == 'running').length;

    return DataRow(
      key: ValueKey('stack-${s.id}'),
      cells: [
        // 0. EXPAND TOGGLE (matching user screenshot)
        DataCell(
          Tooltip(
            message: isExpanded
                ? 'Collapse containers for ${s.name}'
                : 'Expand containers (${stackTasks.length}) for ${s.name}',
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedStackIds.remove(s.id);
                  } else {
                    _expandedStackIds.add(s.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isExpanded
                        ? const Color(0xFF38BDF8)
                        : theme.colorScheme.primary.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  color: isExpanded
                      ? const Color(0xFF38BDF8).withValues(alpha: 0.12)
                      : Colors.transparent,
                ),
                child: Center(
                  child: AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: isExpanded ? const Color(0xFF38BDF8) : theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 1. Stack ID
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
        // 2. NAME (with green dot + icon + badge + name)
        DataCell(
          InkWell(
            onTap: () => widget.onViewStackContainers?.call(s.name),
            borderRadius: BorderRadius.circular(4),
            child: Tooltip(
              message: isBase
                  ? 'Base Infrastructure Stack: ${s.name}'
                  : 'Deployed Application: ${s.name}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: runningCount > 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        boxShadow: [
                          BoxShadow(
                            color: (runningCount > 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isBase ? Icons.foundation : Icons.rocket_launch,
                      size: 16,
                      color: isBase ? const Color(0xFF8B5CF6) : const Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: (isBase ? const Color(0xFF8B5CF6) : const Color(0xFF38BDF8)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (isBase ? const Color(0xFF8B5CF6) : const Color(0xFF38BDF8)).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        isBase ? 'BASE' : 'APP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isBase ? const Color(0xFF8B5CF6) : const Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
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
        // 3. AUTOSCALE
        DataCell(
          Builder(builder: (context) {
            final autoSvc = s.primaryAutoscaleService(widget.state.services);
            if (autoSvc == null || !autoSvc.isAutoscalingEnabled) {
              return Tooltip(
                message: 'Autoscaling: Disabled\nClick to configure & enable horizontal autoscaling (GPU/CPU)',
                child: InkWell(
                  onTap: () => _showAutoscaleDialog(s),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 12, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          'Off',
                          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final isGPU = autoSvc.autoscaleMetric == 'gpu';
            final isCluster = autoSvc.autoscaleScope == 'cluster';
            final color = isGPU ? const Color(0xFFA855F7) : const Color(0xFF06B6D4);
            final icon = isGPU ? Icons.developer_board : Icons.speed;
            final metricLabel = isGPU ? 'GPU' : 'CPU';
            final scopeLabel = isCluster ? 'Cluster' : 'Host';

            final tooltipMsg = 'Autoscaling Enabled (Service: ${autoSvc.name})\n'
                '• Metric: $metricLabel (Target: ${autoSvc.autoscaleTarget.toStringAsFixed(0)}%)\n'
                '• Scope: ${isCluster ? "All Nodes (Cluster)" : "Single Host (Local)"}\n'
                '• Replicas: Min ${autoSvc.autoscaleMin} / Max ${autoSvc.autoscaleMax}'
                '${isGPU ? "\n• Hardware Affinity: Centurions with NVIDIA GPU" : ""}\n'
                'Click to manage & adjust autoscaling settings';

            return Tooltip(
              message: tooltipMsg,
              child: InkWell(
                onTap: () => _showAutoscaleDialog(s),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: 13, color: color),
                      const SizedBox(width: 3),
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(
                        '$metricLabel • $scopeLabel',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontFamily: 'Courier New',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        // 4. HOST NODE
        DataCell(
          Builder(builder: (context) {
            final hostNode = widget.state.nodes.where((n) => n.id == s.nodeId || (s.nodeId.isNotEmpty && n.ip == s.nodeId)).firstOrNull;
            final isMgr = hostNode != null ? hostNode.role.toLowerCase() == 'manager' : false;
            final hostLabel = hostNode != null
                ? (hostNode.labels['gbnt.node.hostname'] ?? hostNode.id)
                : (s.nodeId.isNotEmpty ? s.nodeId : 'Auto / Cluster');
            final hostIp = hostNode?.ip ?? '';
            final color = isMgr ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8);

            return Tooltip(
              message: hostNode != null
                  ? 'Running on ${hostNode.role.toUpperCase()} ($hostLabel - $hostIp)\nClick to migrate to another host'
                  : 'Click to migrate to a specific Centurion host',
              child: InkWell(
                onTap: () => _showMigrateStackDialog(s),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMgr ? Icons.shield : Icons.computer,
                        size: 13,
                        color: color,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hostLabel,
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.swap_horiz, size: 12, color: color.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        // 5. CREATED
        DataCell(Text(_formatDate(s.createdAt))),
        // 6. CONTAINERS
        DataCell(
          InkWell(
            onTap: () => widget.onViewStackContainers?.call(s.name),
            borderRadius: BorderRadius.circular(10),
            child: Tooltip(
              message: runningCount > 0
                  ? 'Running $runningCount/${stackTasks.length} containers for ${s.name}'
                  : 'Stopped (0/${stackTasks.length} containers) for ${s.name}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: runningCount > 0
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: runningCount > 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      runningCount > 0 ? Icons.play_arrow : Icons.stop,
                      size: 12,
                      color: runningCount > 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      runningCount > 0
                          ? '$runningCount/${stackTasks.length}'
                          : 'Stopped (${stackTasks.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: runningCount > 0
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.visibility_outlined,
                      size: 12,
                      color: runningCount > 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 7. ACTIONS
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dynamic Stop / Start Button
            if (_processingStackIds.contains(s.id))
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (runningCount > 0)
              _actionBtn(
                Icons.stop_circle_outlined,
                'Stop Stack (Stop all containers)',
                const Color(0xFFF59E0B),
                () => _stopStack(s.id, s.name),
              )
            else
              _actionBtn(
                Icons.play_circle_filled,
                'Start Stack (Start compose)',
                const Color(0xFF10B981),
                () => _startStack(s.id, s.name),
              ),
            _actionBtn(Icons.receipt_long, 'View Stack Logs & Placement Errors',
                const Color(0xFF8B5CF6), () => _showStackLogsDialog(s)),
            _actionBtn(Icons.schema_outlined, 'View Schema',
                const Color(0xFFFB923C), () => _showStackDiagramDialog(s)),
            _actionBtn(Icons.code, 'Edit YAML',
                const Color(0xFFF97316), () => _openComposeEditor(s)),
            _actionBtn(Icons.download, 'Download docker-compose.yml to local PC',
                const Color(0xFF388BFD), () => _downloadStackYaml(s)),
            _actionBtn(Icons.dns_outlined, 'Save to Master Server (~/.gbnt/stacks/)',
                const Color(0xFF2EA043), () => _saveStackToServer(s)),
            isBase
                ? const SizedBox(width: 36)
                : _actionBtn(Icons.copy, 'Duplicate',
                    const Color(0xFF10B981), () => _duplicateStack(s)),
            _actionBtn(Icons.refresh, 'Restart Stack (Restart all containers)',
                const Color(0xFF3B82F6), () => _restartStack(s.id, s.name)),
            _actionBtn(Icons.rocket_launch, 'Redeploy Stack (Recreate containers)',
                const Color(0xFFD29922), () => _redeployStack(s.id)),
            _actionBtn(Icons.auto_fix_high, 'Reconcile Stack (Purge dead containers & align replicas)',
                const Color(0xFF06B6D4), () => _reconcileStack(s.id, s.name)),
            _actionBtn(Icons.bolt, 'Autoscale Settings (GPU / CPU)',
                const Color(0xFFA855F7), () => _showAutoscaleDialog(s)),
            if (!isBase)
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
      ],
    );
  }

  List<DataRow> _buildContainerRowsForStack(StackModel s, ThemeData theme) {
    final stackTasks = widget.state.tasks.where((t) {
      final svc = widget.state.services.where((sv) => sv.id == t.serviceId).firstOrNull;
      return svc?.stackId == s.id;
    }).toList();

    if (stackTasks.isEmpty) {
      return [
        DataRow(
          key: ValueKey('stack-${s.id}-empty'),
          color: WidgetStateProperty.all(theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1)),
          cells: [
            const DataCell(SizedBox.shrink()),
            const DataCell(Text('-')),
            DataCell(
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'No active containers running for this stack',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
          ],
        )
      ];
    }

    return stackTasks.map((t) {
      final svc = widget.state.services.where((sv) => sv.id == t.serviceId).firstOrNull;
      final node = widget.state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
      final isRunning = t.status == 'running';
      final isPaused = t.status == 'paused';
      final isDead = t.status == 'dead' || t.status == 'exited';

      final statusDotColor = isRunning
          ? const Color(0xFF10B981)
          : (isPaused ? const Color(0xFFF59E0B) : (isDead ? const Color(0xFFEF4444) : Colors.grey));

      final containerDisplayName = t.containerName.isNotEmpty ? t.containerName : (svc?.name ?? 'container');

      return DataRow(
        key: ValueKey('container-${t.id}'),
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) {
            return theme.colorScheme.primary.withValues(alpha: 0.08);
          }
          return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.14);
        }),
        cells: [
          // 0. Blank space under parent toggle column (matching screenshot)
          const DataCell(SizedBox.shrink()),
          // 1. ID
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.view_in_ar, size: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                SelectableText(
                  t.id.length > 8 ? t.id.substring(0, 8) : t.id,
                  style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
                ),
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.copy, size: 12),
                  tooltip: 'Copy Container ID',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ClipboardService.copy(t.id);
                    _showSnackBar('Copied Container ID!');
                  },
                ),
              ],
            ),
          ),
          // 2. NAME (Indented with green dot + container/service name, exactly like screenshot)
          DataCell(
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusDotColor,
                      boxShadow: [
                        BoxShadow(
                          color: statusDotColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        containerDisplayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (svc?.image != null && svc!.image.isNotEmpty)
                        Text(
                          svc.image,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Courier New',
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 3. AUTOSCALE
          DataCell(
            Builder(builder: (context) {
              if (svc == null || !svc.isAutoscalingEnabled) {
                return Tooltip(
                  message: 'Autoscaling: Disabled\nClick to configure autoscaling',
                  child: InkWell(
                    onTap: () => _showTaskAutoscaleDialog(t),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, size: 10, color: Colors.grey),
                          SizedBox(width: 2),
                          Text('Off', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final isGPU = svc.autoscaleMetric == 'gpu';
              final isCluster = svc.autoscaleScope == 'cluster';
              final color = isGPU ? const Color(0xFFA855F7) : const Color(0xFF06B6D4);
              return Tooltip(
                message: 'Autoscaling (${svc.name}): ${isGPU ? "GPU" : "CPU"} • ${isCluster ? "Cluster" : "Host"}\nClick to manage',
                child: InkWell(
                  onTap: () => _showTaskAutoscaleDialog(t),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 10, color: color),
                        const SizedBox(width: 2),
                        Text(
                          '${isGPU ? "GPU" : "CPU"} • ${isCluster ? "Cluster" : "Host"}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, fontFamily: 'Courier New'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          // 4. HOST NODE
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  node?.role.toLowerCase() == 'manager' ? Icons.shield : Icons.computer,
                  size: 13,
                  color: node?.role.toLowerCase() == 'manager' ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 4),
                Text(
                  node != null ? (node.labels['gbnt.node.hostname'] ?? node.id) : t.nodeId,
                  style: const TextStyle(fontFamily: 'Courier New', fontSize: 11),
                ),
                if (node != null && node.ip.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${node.ip})',
                    style: TextStyle(fontSize: 10, fontFamily: 'Courier New', color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ],
            ),
          ),
          // 5. CREATED / UPTIME
          DataCell(
            Text(
              _timeAgo(t.createdAt),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
            ),
          ),
          // 6. CONTAINERS / PORTS & STATUS
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(label: t.status),
                if (svc != null && svc.ports.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _buildPortsCell(svc, node),
                ],
              ],
            ),
          ),
          // 7. ACTIONS
          DataCell(_buildTaskActions(t)),
        ],
      );
    }).toList();
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
            icon: const Icon(Icons.bolt, size: 20, color: Color(0xFFA855F7)),
            tooltip: 'Horizontal Autoscaling Settings (GPU / CPU)',
            onPressed: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (ctx) => AutoscaleControlDialog(
                  stack: widget.stack,
                  stackServices: widget.state.services.where((s) => s.stackId == widget.stack.id).toList(),
                  onSaved: widget.onRefreshState,
                ),
              );
            },
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
                                if (service != null) ...[
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AutoscaleControlDialog(
                                          stack: widget.stack,
                                          service: service,
                                          stackServices: widget.state.services.where((s) => s.stackId == widget.stack.id).toList(),
                                          onSaved: widget.onRefreshState,
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFA855F7)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.bolt, size: 12, color: Color(0xFFA855F7)),
                                          const SizedBox(width: 4),
                                          Text(
                                            service.isAutoscalingEnabled
                                                ? 'Autoscale (${service.autoscaleMetric.toUpperCase()} • ${service.autoscaleScope})'
                                                : 'Autoscale Settings',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFA855F7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          if (task.error.isNotEmpty) ...[
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
