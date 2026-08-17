import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/node_labels_dialog.dart';
import '../../widgets/shell_dialog.dart';
import '../../utils/clipboard_service.dart';

/// Centurions page — full-width nodes table with all actions.
class CenturionsPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;

  const CenturionsPage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<CenturionsPage> createState() => _CenturionsPageState();
}

class _CenturionsPageState extends State<CenturionsPage> {
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

  void _viewNodeShell(String id, String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ShellDialog(taskId: id, containerName: name, isNode: true),
    );
  }

  void _showNodeLabelsDialog(Node n) {
    showDialog(
      context: context,
      builder: (ctx) => NodeLabelsDialog(
        node: n,
        onLabelsSaved: () {
          _showSnackBar('Node labels updated successfully!');
          widget.onRefresh();
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
                        child: Text('Node Details',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
                        Text('Labels', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: SelectableText(labelsJson,
                              style: const TextStyle(fontFamily: 'Courier New', fontSize: 13)),
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
                    children: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
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
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            )),
        const SizedBox(height: 4),
        isBadge
            ? StatusBadge(label: value)
            : SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      ],
    );
  }

  Future<void> _updateNodeRole(String id, String role) async {
    final ok = await ApiService.updateNodeRole(id, role);
    _showSnackBar(ok ? 'Node role updated successfully!' : 'Failed to update node role.', isError: !ok);
    if (ok) widget.onRefresh();
  }

  Future<void> _updateNodeAvailability(String id, String availability, [Node? node]) async {
    final res = await ApiService.updateNodeAvailability(id, availability);
    if (res['error'] != null) {
      _showSnackBar('Failed to update availability: ${res['error']}', isError: true);
      return;
    }

    if (res['auth_mismatch'] == true && node != null) {
      _showSnackBar('⚡ Token desincronizado detectado: Gubernator ha auto-sincronizado el nodo vía SSH automáticamente.');
      widget.onRefresh();
      return;
    }

    _showSnackBar('Node availability updated!');
    widget.onRefresh();
  }

  void _showTokenMismatchDialog(Node node, [Map<String, dynamic>? res]) {
    final activeToken = res?['active_token'] ?? widget.state.activeApiToken;
    final joinToken = res?['join_token'] ?? widget.state.clusterJoinToken;
    final managerAddr = res?['manager_addr'] ?? (widget.state.managerIp.isNotEmpty ? '${widget.state.managerIp}:4000' : '192.168.252.27:4000');
    final command = res?['update_command'] ??
        'gbnt legion join --token $joinToken --api-token $activeToken --manager $managerAddr';

    bool syncing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sync_lock, color: Colors.blue, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Auto-Sincronización de Token',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.blue, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Gubernator detectó credenciales antiguas en el worker "${node.id}" (${node.ip}) y ha lanzado la auto-sincronización en segundo plano vía SSH para actualizar sus tokens activos.',
                              style: const TextStyle(fontSize: 12.5, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Comando para actualizar el worker manualmente:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              command,
                              style: const TextStyle(
                                fontFamily: 'Courier New',
                                fontSize: 11.5,
                                color: Color(0xFFF97316),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            tooltip: 'Copiar comando',
                            onPressed: () {
                              ClipboardService.copy(command);
                              _showSnackBar('Comando de actualización copiado');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'O sincronizar automáticamente ahora vía conexión SSH remota:',
                      style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                ),
                onPressed: syncing
                    ? null
                    : () async {
                        setDialogState(() => syncing = true);
                        final res = await ApiService.syncNodeToken(node.id);
                        setDialogState(() => syncing = false);
                        if (res['error'] != null) {
                          _showSnackBar('Error al sincronizar token: ${res['error']}', isError: true);
                        } else {
                          _showSnackBar(res['message'] ?? 'Token sincronizado y worker reiniciado correctamente!');
                          Navigator.pop(ctx);
                          widget.onRefresh();
                        }
                      },
                icon: syncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync_lock, size: 16),
                label: Text(syncing ? 'Sincronizando...' : 'Auto-Sync vía SSH'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rebootNode(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reboot Node'),
        content: const Text('Are you sure you want to reboot this node? Running containers will be evacuated first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reboot Host')),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await ApiService.rebootNode(id);
      _showSnackBar(ok ? 'Node reboot initiated!' : 'Failed to initiate reboot.', isError: !ok);
      if (ok) widget.onRefresh();
    }
  }

  Future<void> _leaveNode(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force Node Leave'),
        content: const Text('Are you sure you want to force this node to leave the legion?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Force Leave'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await ApiService.leaveNode(id);
      _showSnackBar(ok ? 'Node left the cluster.' : 'Failed to remove node.', isError: !ok);
      if (ok) widget.onRefresh();
    }
  }

  void _showAddHostDialog() {
    final hostController = TextEditingController();
    final userController = TextEditingController(text: 'ubuntu');
    final passwordController = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.dns, color: Colors.green),
            SizedBox(width: 8),
            Text('Add Worker Host (Centurion)'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Specify the remote host connection details. Gubernator will connect via SSH, '
                'detect system resources, and deploy the worker node agent.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: hostController,
                decoration: const InputDecoration(
                  labelText: 'IP Address / FQDN',
                  hintText: 'e.g. 192.168.252.14 or worker3.local',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userController,
                decoration: const InputDecoration(
                  labelText: 'SSH Username',
                  hintText: 'ubuntu / root',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'SSH Password',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add, size: 18),
              label: Text(isLoading ? 'Adding...' : 'Add Host'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: isLoading
                  ? null
                  : () async {
                      final host = hostController.text.trim();
                      final user = userController.text.trim();
                      final pass = passwordController.text;
                      if (host.isEmpty || user.isEmpty || pass.isEmpty) {
                        setDialogState(() => errorText = 'All fields are required');
                        return;
                      }
                      setDialogState(() { isLoading = true; errorText = null; });
                      final err = await ApiService.addHost(host, user, pass);
                      if (err == null) {
                        Navigator.of(ctx).pop();
                        _showSnackBar('Host $host successfully added to cluster!');
                        widget.onRefresh();
                      } else {
                        setDialogState(() { isLoading = false; errorText = err; });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<Node> filteredNodes = widget.state.nodes.where((n) {
      if (_searchQuery.isEmpty) return true;
      return n.id.toLowerCase().contains(_searchQuery) ||
          n.ip.toLowerCase().contains(_searchQuery) ||
          n.role.toLowerCase().contains(_searchQuery) ||
          n.status.toLowerCase().contains(_searchQuery);
    }).toList();

    if (_sortColumnIndex != null) {
      Comparable Function(Node n) getField;
      switch (_sortColumnIndex) {
        case 0: getField = (n) => n.id; break;
        case 1: getField = (n) => n.ip; break;
        case 2: getField = (n) => n.role; break;
        case 3: getField = (n) => n.status; break;
        default: getField = (n) => n.id;
      }
      filteredNodes.sort((a, b) {
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
                  Icon(Icons.dns, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text('Centurions (Nodes)',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Host'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _showAddHostDialog,
                  ),
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
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filteredNodes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns, size: 48,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text(
                              widget.state.nodes.isEmpty ? 'No nodes registered' : 'No matching nodes found',
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
                              DataColumn(label: const Text('ID'), onSort: (col, asc) => setState(() { _sortColumnIndex = col; _sortAscending = asc; })),
                              DataColumn(label: const Text('IP'), onSort: (col, asc) => setState(() { _sortColumnIndex = col; _sortAscending = asc; })),
                              DataColumn(label: const Text('ROLE'), onSort: (col, asc) => setState(() { _sortColumnIndex = col; _sortAscending = asc; })),
                              DataColumn(label: const Text('STATUS'), onSort: (col, asc) => setState(() { _sortColumnIndex = col; _sortAscending = asc; })),
                              const DataColumn(label: Text('CPU')),
                              const DataColumn(label: Text('MEMORY (USED / TOTAL)')),
                              const DataColumn(label: Text('NETWORK')),
                              const DataColumn(label: Text('LABELS')),
                              const DataColumn(label: Text('ACTIONS')),
                            ],
                            rows: filteredNodes.map((n) => DataRow(cells: [
                              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                SelectableText(n.id, style: const TextStyle(fontFamily: 'Courier New', fontSize: 13)),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 14),
                                  tooltip: 'Copy full ID',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () { ClipboardService.copy(n.id); _showSnackBar('Copied Node ID!'); },
                                ),
                              ])),
                              DataCell(Text(n.ip)),
                              DataCell(StatusBadge(label: n.role)),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusBadge(label: n.status),
                                  if (n.authMismatch) ...[
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Token de autenticación antiguo/desincronizado detectado. Haz clic para actualizar.',
                                      child: InkWell(
                                        onTap: () => _showTokenMismatchDialog(n),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.orange.shade700),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.key_off, size: 12, color: Colors.orange),
                                              SizedBox(width: 4),
                                              Text(
                                                'Token Mismatch',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.orange,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )),
                              DataCell(SizedBox(width: 90, child: _buildMiniThermometer(theme, '${n.cpuPercent.toStringAsFixed(1)}%', n.cpuPercent, const Color(0xFF3B82F6)))),
                              DataCell(SizedBox(width: 170, child: _buildMiniThermometer(theme, '${_formatBytes(n.memUsedBytes)} / ${_formatBytes(n.memTotalBytes)}', n.memPercent, const Color(0xFF10B981)))),
                              DataCell(Text(_formatNetSpeed(n.netBps), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF8B5CF6)))),
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
                                                color: isFixed ? theme.colorScheme.primary : theme.colorScheme.secondary,
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
                                    if (action == 'shell') _viewNodeShell(n.id, n.ip);
                                    else if (action == 'inspect') _showNodeInspectDialog(n);
                                    else if (action == 'labels') _showNodeLabelsDialog(n);
                                    else if (action == 'promote') _updateNodeRole(n.id, 'manager');
                                    else if (action == 'demote') _updateNodeRole(n.id, 'worker');
                                    else if (action == 'reboot') _rebootNode(n.id);
                                    else if (action == 'activate') _updateNodeAvailability(n.id, 'active', n);
                                    else if (action == 'maintenance') _updateNodeAvailability(n.id, 'maintenance', n);
                                    else if (action == 'sync-token') _showTokenMismatchDialog(n);
                                    else if (action == 'leave') _leaveNode(n.id);
                                  },
                                  itemBuilder: (context) => [
                                     if (n.status != 'left' && n.status != 'down')
                                       const PopupMenuItem(value: 'shell', child: Row(children: [Icon(Icons.terminal, size: 18), SizedBox(width: 8), Text('Shell')])),
                                    const PopupMenuItem(value: 'inspect', child: Row(children: [Icon(Icons.info_outline, size: 18), SizedBox(width: 8), Text('Inspect')])),
                                    const PopupMenuItem(value: 'labels', child: Row(children: [Icon(Icons.label_outline, size: 18), SizedBox(width: 8), Text('Edit Labels')])),
                                    const PopupMenuDivider(),
                                    if (n.role == 'worker')
                                      const PopupMenuItem(value: 'promote', child: Row(children: [Icon(Icons.trending_up, size: 18, color: Colors.green), SizedBox(width: 8), Text('Promote to Manager')])),
                                    if (n.role == 'manager')
                                      const PopupMenuItem(value: 'demote', child: Row(children: [Icon(Icons.trending_down, size: 18, color: Colors.orange), SizedBox(width: 8), Text('Demote to Worker')])),
                                    const PopupMenuDivider(),
                                    if (n.status == 'maintenance')
                                      const PopupMenuItem(value: 'activate', child: Row(children: [Icon(Icons.check_circle_outline, size: 18, color: Colors.green), SizedBox(width: 8), Text('Exit Maintenance')]))
                                    else if (n.status != 'active')
                                      const PopupMenuItem(value: 'activate', child: Row(children: [Icon(Icons.play_arrow, size: 18, color: Colors.green), SizedBox(width: 8), Text('Activate Node')]))
                                    else
                                      const PopupMenuItem(value: 'maintenance', child: Row(children: [Icon(Icons.build_circle_outlined, size: 18, color: Colors.orange), SizedBox(width: 8), Text('Set Maintenance')])),
                                    if (n.role == 'worker') ...[
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(value: 'sync-token', child: Row(children: [Icon(Icons.sync_lock, size: 18, color: Color(0xFFF97316)), SizedBox(width: 8), Text('Sync Auth Token')])),
                                    ],
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(value: 'reboot', child: Row(children: [Icon(Icons.restart_alt, size: 18, color: Colors.orangeAccent), SizedBox(width: 8), Text('Reboot Node')])),
                                    PopupMenuItem(value: 'leave', enabled: n.status != 'left', child: const Row(children: [Icon(Icons.exit_to_app, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('Force Leave')])),
                                  ],
                                ),
                              ),
                            ])).toList(),
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatNetSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    const suffixes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    int i = 0;
    double speed = bytesPerSec;
    while (speed >= 1024 && i < suffixes.length - 1) {
      speed /= 1024;
      i++;
    }
    return '${speed.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildMiniThermometer(ThemeData theme, String text, double percent, Color defaultColor) {
    final color = percent > 90 ? Colors.red : (percent > 75 ? Colors.orange : defaultColor);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
