import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/compose_editor.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/new_stack_dialog.dart';
import '../widgets/shell_dialog.dart';
import '../widgets/stack_diagram_dialog.dart';
import '../widgets/node_labels_dialog.dart';
import '../utils/clipboard_service.dart';

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
  String _dnsSearchQuery = '';
  int? _stackSortColumnIndex;
  bool _stackSortAscending = true;
  int? _nodeSortColumnIndex;
  bool _nodeSortAscending = true;
  int? _taskSortColumnIndex;
  bool _taskSortAscending = true;
  PlutoGridStateManager? _taskGridStateManager;
  List<String> _layoutOrder = ['stacks', 'nodes'];
  double _stacksRatio = 0.5;
  String _selectedCaddyNode = 'node-local-manager';

  final ScrollController _stackScrollController = ScrollController();
  final ScrollController _nodeScrollController = ScrollController();
  final ScrollController _taskScrollController = ScrollController();
  final ScrollController _dnsScrollController = ScrollController();
  final ScrollController _ingressScrollController = ScrollController();

  int _coreDnsTabIndex = 0; // 0 = Records, 1 = Config
  final TextEditingController _coreDnsConfigController = TextEditingController();
  final TextEditingController _dnsForwardersController = TextEditingController();
  bool _isLoadingCoreDnsConfig = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());

    _coreDnsConfigController.addListener(() {
      final lines = _coreDnsConfigController.text.split('\n');
      for (var line in lines) {
        if (line.trim().startsWith('forward . ')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          final ips = parts.length > 2 ? parts.sublist(2).join(' ') : '';
          if (_dnsForwardersController.text != ips) {
            _dnsForwardersController.text = ips;
          }
          break;
        }
      }
    });
  }

  void _syncTextFromForwarders() {
    final ipsStr = _dnsForwardersController.text.trim();
    var newForward = '    forward .';
    if (ipsStr.isNotEmpty) {
      // Split by any whitespace and join by single space to clean it up
      final ips = ipsStr.split(RegExp(r'\s+'));
      newForward += ' ${ips.join(' ')}';
    }

    final lines = _coreDnsConfigController.text.split('\n');
    bool found = false;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('forward .')) {
        lines[i] = newForward;
        found = true;
        break;
      }
    }
    
    if (found) {
      final newText = lines.join('\n');
      if (_coreDnsConfigController.text != newText) {
        _coreDnsConfigController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stackScrollController.dispose();
    _nodeScrollController.dispose();
    _taskScrollController.dispose();
    _dnsScrollController.dispose();
    _ingressScrollController.dispose();
    _coreDnsConfigController.dispose();
    _dnsForwardersController.dispose();
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
          getField = (t) {
            final svc = _state.services.where((s) => s.id == t.serviceId).firstOrNull;
            final stack = _state.stacks.where((s) => s.id == svc?.stackId).firstOrNull;
            return stack?.name ?? svc?.stackId ?? '';
          };
          break;
        case 3:
          getField = (t) => t.containerName;
          break;
        case 4:
          getField = (t) => t.nodeId;
          break;
        case 5:
          getField = (t) => t.status;
          break;
        case 6:
          getField = (t) => t.containerIp;
          break;
        case 7:
          getField = (t) => t.createdAt;
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
          _updateTaskGrid();
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
  Future<void> _deleteStack(String id, String name) async {
    final isCore = id == 'core-gbnt-stack' || name.toLowerCase().contains('core-gbnt');
    final isMonitor = id == 'sre-monitor-stack' || name.toLowerCase().contains('monitor');

    final title = isCore
        ? 'Restart Core Stack'
        : isMonitor
            ? 'Stop Monitor Stack'
            : 'Delete Stack';

    final content = isCore
        ? 'Restart all core containers? This will not delete the stack or stop it permanently.'
        : isMonitor
            ? 'Stop and remove all monitor containers? The stack will remain in the dashboard for redeployment.'
            : 'Delete this stack and stop all its containers?';

    final actionText = isCore
        ? 'Restart'
        : isMonitor
            ? 'Stop'
            : 'Delete';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              child: Text(actionText)),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.deleteStack(id);

    final successMsg = isCore
        ? 'Core services restarted successfully!'
        : isMonitor
            ? 'Monitor containers stopped.'
            : 'Stack deleted and containers stopped.';

    final failMsg = isCore
        ? 'Failed to restart core services.'
        : isMonitor
            ? 'Failed to stop monitor.'
            : 'Failed to delete stack.';

    _showSnackBar(
      ok ? successMsg : failMsg,
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

  Future<void> _duplicateStack(StackModel stack) async {
    try {
      final yaml = await ApiService.getStackCompose(stack.id);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => NewStackDialog(
          initialName: '${stack.name}-copy',
          initialYaml: yaml,
          nodes: _state.nodes,
          onDeploy: (name, compose, targetNode) async {
            final errorMsg = await ApiService.deployStack(name, compose, targetNode: targetNode);
            if (errorMsg == null) {
              _showSnackBar('Stack duplicated and deployed successfully!');
              _fetchData();
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
        nodes: _state.nodes,
        onDeploy: (name, yaml, targetNode) async {
          final errorMsg = await ApiService.deployStack(name, yaml, targetNode: targetNode);
          if (errorMsg == null) {
            _showSnackBar('Stack deployed successfully!');
            _fetchData();
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
        services: _state.services,
        tasks: _state.tasks,
        nodes: _state.nodes,
      ),
    );
  }

  void _showNodeLabelsDialog(Node n) {
    showDialog(
      context: context,
      builder: (ctx) => NodeLabelsDialog(
        node: n,
        onLabelsSaved: () {
          _showSnackBar('Node labels updated successfully!');
          _fetchData();
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

  Future<void> _rebootNode(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reboot Node'),
        content: const Text('Are you sure you want to reboot this node? Running containers will be evacuated first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reboot Host'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await ApiService.rebootNode(id);
      if (ok) {
        _showSnackBar('Node reboot initiated successfully!');
        _fetchData();
      } else {
        _showSnackBar('Failed to initiate node reboot.', isError: true);
      }
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
    if (ok) {
      _showSnackBar('Task stopped.');
      _fetchData();
    } else {
      _showSnackBar('Failed to stop task.', isError: true);
    }
  }

  Future<void> _taskAction(String id, String action) async {
    final ok = await ApiService.taskAction(id, action);
    if (ok) {
      _showSnackBar('Action "$action" executed successfully.');
      _fetchData();
    } else {
      _showSnackBar('Failed to execute "$action".', isError: true);
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
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
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
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  color: Colors.greenAccent,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
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
      builder: (ctx) => ShellDialog(
        taskId: id,
        containerName: name,
      ),
    );
  }

  void _viewNodeShell(String id, String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ShellDialog(
        taskId: id,
        containerName: name,
        isNode: true,
      ),
    );
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


  // ─── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = _state.tasks;
    final running = tasks.where((t) => t.status == 'running').length;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
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
            // Observability gear icon
            if (_state.monitorRunning)
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.analytics_outlined),
                  tooltip: 'Observability (Grafana)',
                  onPressed: () => html.window.open('/grafana/', '_blank'),
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
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatsRow(theme, running),
                        const SizedBox(height: 16),
                        TabBar(
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                          tabs: const [
                            Tab(
                              icon: Icon(Icons.hub_outlined),
                              text: 'Legions & Tasks',
                            ),
                            Tab(
                              icon: Icon(Icons.alt_route_outlined),
                              text: 'Caddy Ingress',
                            ),
                            Tab(
                              icon: Icon(Icons.dns_outlined),
                              text: 'CoreDNS Records',
                            ),
                            Tab(
                              icon: Icon(Icons.analytics_outlined),
                              text: 'Grafana Metrics',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // Tab 1: Legions & Tasks
                              RefreshIndicator(
                                onRefresh: _fetchData,
                                child: SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _buildStacksAndNodesRow(theme),
                                      const SizedBox(height: 24),
                                      _buildTasksSection(theme),
                                    ],
                                  ),
                                ),
                              ),
                              // Tab 2: Caddy Ingress
                              RefreshIndicator(
                                onRefresh: _fetchData,
                                child: SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: _buildCaddySection(theme),
                                ),
                              ),
                              // Tab 3: CoreDNS Records
                              RefreshIndicator(
                                onRefresh: _fetchData,
                                child: SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: _buildDnsSection(theme),
                                ),
                              ),
                              // Tab 4: Grafana Metrics (Iframe)
                              Card(
                                clipBehavior: Clip.antiAlias,
                                child: const HtmlElementView(viewType: 'grafana-iframe'),
                              ),
                            ],
                          ),
                        ),
                      ],
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
      final children = _layoutOrder.map((type) {
        final card = type == 'stacks' ? _buildStacksCard(theme) : _buildNodesCard(theme);
        return _buildDraggableCard(type, card, availableWidth);
      }).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          children[0],
          const SizedBox(height: gap),
          children[1],
        ],
      );
    }

    // Wide screen → side by side with resizable split view
    final double leftWidth = _layoutOrder[0] == 'stacks'
        ? availableWidth * _stacksRatio - (gap / 2)
        : availableWidth * (1.0 - _stacksRatio) - (gap / 2);

    final double rightWidth = _layoutOrder[0] == 'stacks'
        ? availableWidth * (1.0 - _stacksRatio) - (gap / 2)
        : availableWidth * _stacksRatio - (gap / 2);

    final children = _layoutOrder.asMap().entries.map((entry) {
      final idx = entry.key;
      final type = entry.value;
      final card = type == 'stacks' ? _buildStacksCard(theme) : _buildNodesCard(theme);
      final width = idx == 0 ? leftWidth : rightWidth;
      return SizedBox(
        width: width,
        child: _buildDraggableCard(type, card, width),
      );
    }).toList();

    return SizedBox(
      width: availableWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          children[0],
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              setState(() {
                double deltaRatio = details.delta.dx / availableWidth;
                if (_layoutOrder[0] != 'stacks') {
                  deltaRatio = -deltaRatio;
                }
                _stacksRatio = (_stacksRatio + deltaRatio).clamp(0.2, 0.8);
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: SizedBox(
                width: gap,
                height: 350,
                child: Center(
                  child: Container(
                    width: 4,
                    height: 50,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          children[1],
        ],
      ),
    );
  }

  Widget _buildDraggableCard(String type, Widget child, double? width) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != type,
      onAcceptWithDetails: (details) {
        setState(() {
          final index1 = _layoutOrder.indexOf(details.data);
          final index2 = _layoutOrder.indexOf(type);
          final temp = _layoutOrder[index1];
          _layoutOrder[index1] = _layoutOrder[index2];
          _layoutOrder[index2] = temp;
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isOver
                ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                : null,
          ),
          child: Draggable<String>(
            data: type,
            feedback: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: width ?? 350,
                child: Opacity(
                  opacity: 0.85,
                  child: child,
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: child,
            ),
            child: child,
          ),
        );
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
              Scrollbar(
                controller: _stackScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _stackScrollController,
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
                              ClipboardService.copy(s.id);
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
                          _actionBtn(Icons.schema_outlined, 'View Schema',
                              const Color(0xFFFB923C), () => _showStackDiagramDialog(s)),
                          _actionBtn(Icons.code, 'Edit YAML',
                              const Color(0xFFF97316), () => _openComposeEditor(s)),
                          (s.id == 'core-gbnt-stack' ||
                                  s.id == 'sre-monitor-stack' ||
                                  s.name.toLowerCase().contains('core-gbnt') ||
                                  s.name.toLowerCase().contains('monitor'))
                              ? const SizedBox(width: 36)
                              : _actionBtn(Icons.copy, 'Duplicate',
                                  const Color(0xFF10B981), () => _duplicateStack(s)),
                          _actionBtn(Icons.rocket_launch, 'Redeploy',
                              const Color(0xFFD29922), () => _redeployStack(s.id)),
                          _actionBtn(
                              Icons.delete,
                              (s.id == 'core-gbnt-stack' || s.name.toLowerCase().contains('core-gbnt'))
                                  ? 'Restart Core (Does not delete)'
                                  : (s.id == 'sre-monitor-stack' || s.name.toLowerCase().contains('monitor'))
                                      ? 'Stop Monitor (Keeps stack)'
                                      : 'Delete',
                              const Color(0xFFEF4444),
                              () => _deleteStack(s.id, s.name)),
                        ],
                      )),
                    ]);
                  }).toList(),
                ),
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
              Scrollbar(
                controller: _nodeScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _nodeScrollController,
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
                    const DataColumn(label: Text('LABELS')),
                    const DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: filteredNodes.map((n) {
                    return DataRow(cells: [
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(n.id,
                              style: const TextStyle(fontFamily: 'Courier New', fontSize: 13)),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 14),
                            tooltip: 'Copy full ID',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              ClipboardService.copy(n.id);
                              _showSnackBar('Copied Node ID to clipboard!');
                            },
                          ),
                        ],
                      )),
                      DataCell(Text(n.ip)),
                      DataCell(StatusBadge(label: n.role)),
                      DataCell(StatusBadge(label: n.status)),
                      DataCell(
                        n.labels.isEmpty
                            ? const Text('-')
                            : Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: n.labels.entries.map((entry) {
                                  final isFixed = entry.key == 'gbnt.node.role' || entry.key == 'gbnt.node.arch';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isFixed
                                          ? theme.colorScheme.primary.withValues(alpha: 0.1)
                                          : theme.colorScheme.secondary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isFixed
                                            ? theme.colorScheme.primary.withValues(alpha: 0.3)
                                            : theme.colorScheme.secondary.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      '${entry.key}=${entry.value}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isFixed
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.secondary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      DataCell(
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          tooltip: 'Node Actions',
                          onSelected: (action) {
                            if (action == 'shell') {
                              _viewNodeShell(n.id, n.ip);
                            } else if (action == 'inspect') {
                              _showNodeInspectDialog(n);
                            } else if (action == 'labels') {
                              _showNodeLabelsDialog(n);
                            } else if (action == 'promote') {
                              _updateNodeRole(n.id, 'manager');
                            } else if (action == 'demote') {
                              _updateNodeRole(n.id, 'worker');
                            } else if (action == 'reboot') {
                              _rebootNode(n.id);
                            } else if (action == 'active') {
                              _updateNodeAvailability(n.id, 'active');
                            } else if (action == 'maintenance') {
                              _updateNodeAvailability(n.id, 'maintenance');
                            } else if (action == 'exit_maintenance') {
                              _updateNodeAvailability(n.id, 'active');
                            } else if (action == 'pause') {
                              _updateNodeAvailability(n.id, 'pause');
                            } else if (action == 'leave') {
                              _leaveNode(n.id);
                            } else if (action == 'drain') {
                              _updateNodeAvailability(n.id, 'drain');
                            }
                          },
                          itemBuilder: (context) => [
                            if (n.status == 'ready' || n.status == 'active')
                              const PopupMenuItem(
                                value: 'shell',
                                child: Row(
                                  children: [
                                    Icon(Icons.terminal, size: 18),
                                    SizedBox(width: 8),
                                    Text('Shell'),
                                  ],
                                ),
                              ),
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
                            const PopupMenuItem(
                              value: 'labels',
                              child: Row(
                                children: [
                                  Icon(Icons.label_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit Labels'),
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
                            if (n.status == 'pause')
                              const PopupMenuItem(
                                value: 'active',
                                child: Row(
                                  children: [
                                    Icon(Icons.play_arrow, size: 18, color: Colors.green),
                                    SizedBox(width: 8),
                                    Text('Reanudar Nodo (Activar)'),
                                  ],
                                ),
                              )
                            else
                              PopupMenuItem(
                                value: 'pause',
                                enabled: n.status == 'active',
                                child: const Row(
                                  children: [
                                    Icon(Icons.pause, size: 18, color: Colors.amber),
                                    SizedBox(width: 8),
                                    Text('Pausar Nodo'),
                                  ],
                                ),
                              ),
                            if (n.status == 'maintenance' || n.status == 'drain')
                              const PopupMenuItem(
                                value: 'exit_maintenance',
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                                    SizedBox(width: 8),
                                    Text('Sacar de Mantenimiento'),
                                  ],
                                ),
                              )
                            else
                              const PopupMenuItem(
                                value: 'maintenance',
                                child: Row(
                                  children: [
                                    Icon(Icons.build_circle_outlined, size: 18, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Poner en Mantenimiento'),
                                  ],
                                ),
                              ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'reboot',
                              child: Row(
                                children: [
                                  Icon(Icons.restart_alt, size: 18, color: Colors.orangeAccent),
                                  SizedBox(width: 8),
                                  Text('Reiniciar Nodo (Reboot)'),
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
            ),
          ],
        ),
      ),
    );
  }

  void _updateTaskGrid() {
    if (_taskGridStateManager == null) return;
    final theme = Theme.of(context);
    final List<PlutoRow> newRows = _getPlutoRows(theme);

    final currentRows = _taskGridStateManager!.refRows.originalList;
    final Map<String, PlutoRow> currentRowsMap = {
      for (var row in currentRows) row.cells['task_id']!.value.toString(): row
    };

    final List<PlutoRow> rowsToAdd = [];
    final Set<String> newRowIds = {};

    bool hasChanges = false;

    for (var newRow in newRows) {
      final id = newRow.cells['task_id']!.value.toString();
      newRowIds.add(id);

      final existingRow = currentRowsMap[id];
      if (existingRow != null) {
        // Update values of existing row cells if they have changed
        for (var key in newRow.cells.keys) {
          if (existingRow.cells[key]!.value != newRow.cells[key]!.value) {
            existingRow.cells[key]!.value = newRow.cells[key]!.value;
            hasChanges = true;
          }
        }
      } else {
        // Mark for addition
        rowsToAdd.add(newRow);
        hasChanges = true;
      }
    }

    // Identify rows to remove
    final List<PlutoRow> rowsToRemove = [];
    for (var row in currentRows) {
      final id = row.cells['task_id']!.value.toString();
      if (!newRowIds.contains(id)) {
        rowsToRemove.add(row);
        hasChanges = true;
      }
    }

    if (rowsToRemove.isNotEmpty) {
      _taskGridStateManager!.removeRows(rowsToRemove);
    }
    if (rowsToAdd.isNotEmpty) {
      _taskGridStateManager!.appendRows(rowsToAdd);
    }

    if (hasChanges) {
      _taskGridStateManager!.notifyListeners();
    }
  }

  List<PlutoRow> _getPlutoRows(ThemeData theme) {
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
          (node != null && (node.id.toLowerCase().contains(_taskSearchQuery) || node.ip.toLowerCase().contains(_taskSearchQuery)));
    }).toList();

    return filteredTasks.map((t) {
      final svc = _state.services.where((s) => s.id == t.serviceId).firstOrNull;
      final stack = _state.stacks.where((s) => s.id == svc?.stackId).firstOrNull;
      final stackName = stack?.name ?? svc?.stackId ?? '-';
      final node = _state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
      final nodeVal = node != null ? '${node.id} (${node.ip})' : t.nodeId;
      
      return PlutoRow(
        cells: {
          'task_id': PlutoCell(value: t.id),
          'service': PlutoCell(value: svc?.name ?? 'unknown'),
          'stack': PlutoCell(value: stackName),
          'container': PlutoCell(value: t.containerName.isEmpty ? '-' : t.containerName),
          'node': PlutoCell(value: nodeVal),
          'status': PlutoCell(value: t.status),
          'ip': PlutoCell(value: t.containerIp.isEmpty ? '-' : t.containerIp),
          'created': PlutoCell(value: t.createdAt),
          'ports': PlutoCell(value: ''),
          'actions': PlutoCell(value: ''),
          'task_raw': PlutoCell(value: t),
        },
      );
    }).toList();
  }

  // ─── Tasks Section ──────────────────────────────────────────────────
  Widget _buildTasksSection(ThemeData theme) {
    if (_state.tasks.isEmpty) {
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
              _emptyState('No tasks running', Icons.inbox),
            ],
          ),
        ),
      );
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final gridHeight = (screenHeight - 620).clamp(300.0, double.infinity);

    final List<PlutoColumn> columns = [
      PlutoColumn(
        title: 'TASK ID',
        field: 'task_id',
        type: PlutoColumnType.text(),
        width: 110,
        renderer: (rendererContext) {
          final t = rendererContext.row.cells['task_raw']!.value as Task;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                  t.id.length > 8 ? t.id.substring(0, 8) : t.id,
                  style: const TextStyle(fontFamily: 'Courier New', fontSize: 13)),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.copy, size: 14),
                tooltip: 'Copy Task ID',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  ClipboardService.copy(t.id);
                  _showSnackBar('Copied Task ID to clipboard!');
                },
              ),
            ],
          );
        },
      ),
      PlutoColumn(
        title: 'SERVICE',
        field: 'service',
        type: PlutoColumnType.text(),
        width: 220,
        renderer: (rendererContext) {
          final t = rendererContext.row.cells['task_raw']!.value as Task;
          final svc = _state.services.where((s) => s.id == t.serviceId).firstOrNull;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(svc?.name ?? 'unknown',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (svc?.image != null)
                    Text(svc!.image,
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
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
                    ClipboardService.copy(svc.id);
                    _showSnackBar('Copied Service ID to clipboard!');
                  },
                ),
              ],
            ],
          );
        },
      ),
      PlutoColumn(
        title: 'STACK',
        field: 'stack',
        type: PlutoColumnType.text(),
        width: 120,
      ),
      PlutoColumn(
        title: 'CONTAINER',
        field: 'container',
        type: PlutoColumnType.text(),
        width: 160,
      ),
      PlutoColumn(
        title: 'NODE',
        field: 'node',
        type: PlutoColumnType.text(),
        width: 180,
        renderer: (rendererContext) {
          final t = rendererContext.row.cells['task_raw']!.value as Task;
          final node = _state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SelectableText(
                      node?.id ?? 'unknown',
                      style: const TextStyle(
                          fontFamily: 'Courier New',
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  if (node != null && node.ip.isNotEmpty)
                    Text(
                      node.ip,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontFamily: 'Courier New',
                      ),
                    ),
                ],
              ),
              if (node != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: 'Copy Node ID',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ClipboardService.copy(node.id);
                    _showSnackBar('Copied Node ID to clipboard!');
                  },
                ),
              ],
            ],
          );
        },
      ),
      PlutoColumn(
        title: 'STATUS',
        field: 'status',
        type: PlutoColumnType.text(),
        width: 100,
        renderer: (rendererContext) {
          final status = rendererContext.cell.value as String;
          return StatusBadge(label: status);
        },
      ),
      PlutoColumn(
        title: 'IP',
        field: 'ip',
        type: PlutoColumnType.text(),
        width: 120,
      ),
      PlutoColumn(
        title: 'CREATED',
        field: 'created',
        type: PlutoColumnType.text(),
        width: 120,
        renderer: (rendererContext) {
          final t = rendererContext.row.cells['task_raw']!.value as Task;
          return Text(_timeAgo(t.createdAt),
              style: const TextStyle(fontSize: 13, color: Colors.grey));
        },
      ),
      PlutoColumn(
        title: 'PORTS',
        field: 'ports',
        type: PlutoColumnType.text(),
        width: 200,
        renderer: (rendererContext) {
          final t = rendererContext.row.cells['task_raw']!.value as Task;
          final svc = _state.services.where((s) => s.id == t.serviceId).firstOrNull;
          final node = _state.nodes.where((n) => n.id == t.nodeId).firstOrNull;
          return _buildPortsCell(svc, node);
        },
      ),
      PlutoColumn(
        title: 'ACTIONS',
        field: 'actions',
        type: PlutoColumnType.text(),
        width: 80,
        enableSorting: false,
        renderer: (rendererContext) {
          final t = rendererContext.row.cells['task_raw']!.value as Task;
          return _buildTaskActions(t);
        },
      ),
    ];

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
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (val) {
                setState(() {
                  _taskSearchQuery = val.toLowerCase();
                  _updateTaskGrid();
                });
              },
            ),
            const SizedBox(height: 16),
            Container(
              height: gridHeight,
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PlutoGrid(
                  columns: columns,
                  rows: _getPlutoRows(theme),
                  rowColorCallback: (rowColorContext) {
                    if (rowColorContext.rowIdx % 2 != 0) {
                      return theme.colorScheme.onSurface.withValues(alpha: 0.04);
                    }
                    return theme.brightness == Brightness.dark
                        ? const Color(0xFF111111)
                        : Colors.white;
                  },
                  onLoaded: (PlutoGridOnLoadedEvent event) {
                    _taskGridStateManager = event.stateManager;
                    _taskGridStateManager!.setShowColumnFilter(true);
                  },
                  configuration: PlutoGridConfiguration(
                    style: theme.brightness == Brightness.dark
                        ? const PlutoGridStyleConfig.dark()
                        : const PlutoGridStyleConfig(),
                    columnSize: const PlutoGridColumnSizeConfig(
                      autoSizeMode: PlutoAutoSizeMode.scale,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskActions(Task t) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'Actions',
      onSelected: (value) {
        switch (value) {
          case 'shell':
            _viewTaskShell(t.id, t.containerName);
            break;
          case 'logs':
            _viewTaskLogs(t.id);
            break;
          case 'inspect':
            _viewTaskInspect(t.id);
            break;
          case 'pause':
            _taskAction(t.id, 'pause');
            break;
          case 'unpause':
            _taskAction(t.id, 'unpause');
            break;
          case 'restart':
            _taskAction(t.id, 'restart');
            break;
          case 'start':
            _taskAction(t.id, 'start');
            break;
          case 'stop':
            _stopTask(t.id);
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (t.status == 'running')
          const PopupMenuItem<String>(
            value: 'shell',
            child: ListTile(
              leading: Icon(Icons.terminal, size: 20),
              title: Text('Shell'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem<String>(
          value: 'logs',
          child: ListTile(
            leading: Icon(Icons.notes, size: 20),
            title: Text('Logs'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'inspect',
          child: ListTile(
            leading: Icon(Icons.info_outline, size: 20),
            title: Text('View Details'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        if (t.status == 'running')
          const PopupMenuItem<String>(
            value: 'pause',
            child: ListTile(
              leading: Icon(Icons.pause, size: 20),
              title: Text('Pause'),
              contentPadding: EdgeInsets.zero,
            ),
          )
        else if (t.status == 'paused')
          const PopupMenuItem<String>(
            value: 'unpause',
            child: ListTile(
              leading: Icon(Icons.play_arrow, size: 20),
              title: Text('Resume'),
              contentPadding: EdgeInsets.zero,
            ),
          )
        else
          const PopupMenuItem<String>(
            value: 'start',
            child: ListTile(
              leading: Icon(Icons.play_arrow, size: 20),
              title: Text('Start'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem<String>(
          value: 'restart',
          child: ListTile(
            leading: Icon(Icons.refresh, size: 20),
            title: Text('Restart'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'stop',
          child: ListTile(
            leading: Icon(Icons.stop_circle, size: 20, color: Colors.red),
            title: Text('Stop', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: svc.ports.map((portMapping) {
        // Parse "hostPort:containerPort" or "hostPort:containerPort/protocol"
        final hostPort = portMapping.split(':').first;
        final url = 'http://$host:$hostPort';

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(
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
          ),
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
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _timeAgo(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);

      if (diff.inDays > 0) {
        return 'Up ${diff.inDays} days';
      } else if (diff.inHours > 0) {
        return 'Up ${diff.inHours} hours';
      } else if (diff.inMinutes > 0) {
        return 'Up ${diff.inMinutes} minutes';
      } else {
        return 'Up ${diff.inSeconds} seconds';
      }
    } catch (_) {
      return '-';
    }
  }

  Future<void> _loadCoreDnsConfig() async {
    setState(() => _isLoadingCoreDnsConfig = true);
    try {
      final config = await ApiService.getCoreDNSConfig();
      if (mounted) {
        setState(() {
          _coreDnsConfigController.text = config;
          _isLoadingCoreDnsConfig = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCoreDnsConfig = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load CoreDNS config: $e')),
        );
      }
    }
  }

  Future<void> _saveCoreDnsConfig() async {
    setState(() => _isLoadingCoreDnsConfig = true);
    try {
      await ApiService.updateCoreDNSConfig(_coreDnsConfigController.text);
      if (mounted) {
        setState(() => _isLoadingCoreDnsConfig = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CoreDNS configuration saved and container restarted')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCoreDnsConfig = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save CoreDNS config: $e')),
        );
      }
    }
  }

  Widget _buildDnsSection(ThemeData theme) {
    final filteredDns = _state.dnsRecords.where((d) {
      if (_dnsSearchQuery.isEmpty) return true;
      return d.ip.toLowerCase().contains(_dnsSearchQuery) ||
          d.hostname.toLowerCase().contains(_dnsSearchQuery);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('CoreDNS',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Records')),
                    ButtonSegment(value: 1, label: Text('Configuration')),
                  ],
                  selected: {_coreDnsTabIndex},
                  onSelectionChanged: (Set<int> newSelection) {
                    setState(() {
                      _coreDnsTabIndex = newSelection.first;
                    });
                    if (_coreDnsTabIndex == 1 && _coreDnsConfigController.text.isEmpty) {
                      _loadCoreDnsConfig();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_coreDnsTabIndex == 0) ...[
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search DNS records...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) {
                  setState(() {
                    _dnsSearchQuery = val.toLowerCase();
                  });
                },
              ),
              const SizedBox(height: 16),
              if (filteredDns.isEmpty)
                _emptyState(_state.dnsRecords.isEmpty ? 'No DNS records found' : 'No matching records found', Icons.dns)
              else
                Scrollbar(
                  controller: _dnsScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _dnsScrollController,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                    columns: const [
                      DataColumn(label: Text('IP ADDRESS')),
                      DataColumn(label: Text('HOSTNAME (DOMAIN)')),
                      DataColumn(label: Text('TEST RESOLUTION (CURL)')),
                    ],
                    rows: filteredDns.map((d) {
                      return DataRow(cells: [
                        DataCell(SelectableText(d.ip,
                            style: const TextStyle(fontFamily: 'Courier New', fontSize: 13))),
                        DataCell(SelectableText(d.hostname,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Courier New', fontSize: 13))),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText('curl http://${d.hostname}',
                                style: TextStyle(fontFamily: 'Courier New', fontSize: 12, color: theme.colorScheme.primary)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              tooltip: 'Copy curl command',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                ClipboardService.copy('curl http://${d.hostname}');
                                _showSnackBar('Copied curl command to clipboard!');
                              },
                            ),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ] else ...[
              if (_isLoadingCoreDnsConfig)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.public, size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('External DNS Forwarders', style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Gubernator uses these servers to resolve external internet domains. You can enter one or more IP addresses separated by spaces (e.g. 8.8.8.8 1.1.1.1). Changes here sync automatically with the raw JSON-like configuration below.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _dnsForwardersController,
                            decoration: const InputDecoration(
                              labelText: 'DNS Forwarders (IP addresses separated by spaces)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _syncTextFromForwarders(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Raw Corefile Configuration', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _coreDnsConfigController,
                      maxLines: 15,
                      style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'CoreDNS Corefile Configuration',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save & Restart CoreDNS'),
                        onPressed: _saveCoreDnsConfig,
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCaddySection(ThemeData theme) {
    // Fallback logic to get selected node
    final selectedNode = _state.nodes.firstWhere(
      (n) => n.id == _selectedCaddyNode,
      orElse: () => _state.nodes.firstWhere(
        (n) => n.role == 'manager',
        orElse: () => Node(
          id: 'node-local-manager',
          ip: '127.0.0.1',
          role: 'manager',
          status: 'active',
          caddyStatus: _state.caddyStatus,
          caddyfile: _state.caddyfile,
        ),
      ),
    );

    final status = selectedNode.caddyStatus.isNotEmpty ? selectedNode.caddyStatus : 'not running';
    final caddyfile = selectedNode.caddyfile;
    final isDark = theme.brightness == Brightness.dark;

    final rules = _parseCaddyfile(caddyfile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dropdown to select Node Caddy Ingress
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.dns, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Select Node Ingress Proxy:',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _state.nodes.any((n) => n.id == _selectedCaddyNode)
                      ? _selectedCaddyNode
                      : (_state.nodes.any((n) => n.role == 'manager')
                          ? _state.nodes.firstWhere((n) => n.role == 'manager').id
                          : (_state.nodes.isNotEmpty ? _state.nodes.first.id : 'node-local-manager')),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCaddyNode = val;
                      });
                    }
                  },
                  items: _state.nodes.map((node) {
                    final displayName = node.role == 'manager' ? '${node.id} (Manager)' : node.id;
                    return DropdownMenuItem<String>(
                      value: node.id,
                      child: Text(displayName),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Status Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.alt_route, size: 40, color: theme.colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Caddy Ingress Gateway',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Caddy acts as the reverse proxy / ingress controller, exposing services to external traffic.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'STATUS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusBadge(label: status.contains('|') ? status.split('|').first.trim() : status),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Active Routing Rules Table
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fork_right, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Ingress Routing Rules',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (rules.isEmpty)
                  _emptyState('No ingress rules defined. Add "ingress.host" deploy constraint in your Legion stack YAML.', Icons.fork_right_outlined)
                else
                  Scrollbar(
                    controller: _ingressScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _ingressScrollController,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                      columns: const [
                        DataColumn(label: Text('INGRESS HOST')),
                        DataColumn(label: Text('UPSTREAMS (CONTAINER BACKENDS)')),
                        DataColumn(label: Text('TEST COMMAND')),
                      ],
                      rows: rules.map((rule) {
                        final host = rule['host'] ?? '';
                        final upstreams = rule['upstreams'] ?? '';
                        final curlCmd = 'curl -H "Host: $host" http://localhost';

                        return DataRow(cells: [
                          DataCell(SelectableText(
                            host,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier New', fontSize: 13),
                          )),
                          DataCell(SelectableText(
                            upstreams,
                            style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                          )),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SelectableText(
                                curlCmd,
                                style: TextStyle(fontFamily: 'Courier New', fontSize: 12, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 14),
                                tooltip: 'Copy curl command',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: curlCmd));
                                  _showSnackBar('Copied curl command to clipboard!');
                                },
                              ),
                            ],
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Caddyfile Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Generated Caddyfile',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Copy Caddyfile',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: caddyfile));
                        _showSnackBar('Copied Caddyfile content to clipboard!');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: SelectableText(
                    caddyfile.isEmpty ? '# No configuration loaded' : caddyfile,
                    style: const TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, String>> _parseCaddyfile(String caddyfile) {
    final List<Map<String, String>> rules = [];
    final lines = caddyfile.split('\n');
    String? currentHost;
    final List<String> currentUpstreams = [];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.endsWith('{')) {
        currentHost = line.replaceAll('{', '').trim();
        currentUpstreams.clear();
      } else if (line.startsWith('reverse_proxy') && currentHost != null) {
        final parts = line.split(' ');
        for (final part in parts) {
          if (part == 'reverse_proxy' || part == '{' || part.isEmpty) continue;
          currentUpstreams.add(part);
        }
      } else if (line == '}') {
        if (currentHost != null) {
          if (currentHost != ':80') {
            rules.add({
              'host': currentHost,
              'upstreams': currentUpstreams.join(', '),
            });
          }
          currentHost = null;
        }
      }
    }
    return rules;
  }
}
