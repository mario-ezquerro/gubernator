import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';

/// Caddy ingress page — routing rules and Caddyfile per node.
class CaddyPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;

  const CaddyPage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<CaddyPage> createState() => _CaddyPageState();
}

class _CaddyPageState extends State<CaddyPage> {
  String _selectedCaddyNode = 'node-local-manager';
  final ScrollController _ingressScrollController = ScrollController();

  @override
  void dispose() {
    _ingressScrollController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
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
            rules.add({'host': currentHost, 'upstreams': currentUpstreams.join(', ')});
          }
          currentHost = null;
        }
      }
    }
    return rules;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedNode = widget.state.nodes.firstWhere(
      (n) => n.id == _selectedCaddyNode,
      orElse: () => widget.state.nodes.firstWhere(
        (n) => n.role == 'manager',
        orElse: () => Node(
          id: 'node-local-manager', ip: '127.0.0.1', role: 'manager', status: 'active',
          caddyStatus: widget.state.caddyStatus, caddyfile: widget.state.caddyfile,
        ),
      ),
    );

    final status = selectedNode.caddyStatus.isNotEmpty ? selectedNode.caddyStatus : 'not running';
    final caddyfile = selectedNode.caddyfile;
    final rules = _parseCaddyfile(caddyfile);

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Node selector
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.dns, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Select Node Ingress Proxy:',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: widget.state.nodes.any((n) => n.id == _selectedCaddyNode)
                          ? _selectedCaddyNode
                          : (widget.state.nodes.any((n) => n.role == 'manager')
                              ? widget.state.nodes.firstWhere((n) => n.role == 'manager').id
                              : (widget.state.nodes.isNotEmpty ? widget.state.nodes.first.id : 'node-local-manager')),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCaddyNode = val);
                      },
                      items: widget.state.nodes.map((node) {
                        final displayName = node.role == 'manager' ? '${node.id} (Manager)' : node.id;
                        return DropdownMenuItem<String>(value: node.id, child: Text(displayName));
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
                          Text('Caddy Ingress Gateway',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Caddy acts as the reverse proxy / ingress controller, exposing services to external traffic.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('STATUS', style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        StatusBadge(label: status.contains('|') ? status.split('|').first.trim() : status),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Routing Rules
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.fork_right, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Ingress Routing Rules',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 16),
                    if (rules.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(children: [
                            Icon(Icons.fork_right_outlined, size: 40,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text('No ingress rules defined. Add "ingress.host" deploy constraint in your Legion stack YAML.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                )),
                          ]),
                        ),
                      )
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
                                DataCell(SelectableText(host,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier New', fontSize: 13))),
                                DataCell(SelectableText(upstreams,
                                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 13))),
                                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                  SelectableText(curlCmd,
                                      style: TextStyle(fontFamily: 'Courier New', fontSize: 12, color: theme.colorScheme.primary)),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 14),
                                    tooltip: 'Copy curl command',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: curlCmd));
                                      _showSnackBar('Copied curl command!');
                                    },
                                  ),
                                ])),
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

            // Caddyfile
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.description, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Generated Caddyfile',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Copy Caddyfile',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: caddyfile));
                          _showSnackBar('Copied Caddyfile!');
                        },
                      ),
                    ]),
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
                        style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
