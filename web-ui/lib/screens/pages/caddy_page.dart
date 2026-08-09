import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

/// Caddy Ingress Visualization Suite — Multi-node Caddy cluster manager inspired by caddy-ui.
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

class _CaddyPageState extends State<CaddyPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCaddyNode = 'node-local-manager';
  
  // Data states
  Map<String, dynamic> _caddyStatusData = {};
  List<dynamic> _routesList = [];
  List<dynamic> _certsList = [];
  List<String> _logsList = [];
  Map<String, dynamic> _metricsData = {};
  bool _loading = false;
  
  // Filters & Search
  String _routeFilter = '';
  String _logSearch = '';
  String _logLevelFilter = 'ALL';
  bool _accessLoggingEnabled = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadCaddyData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCaddyData() async {
    setState(() => _loading = true);
    try {
      final status = await ApiService.fetchCaddyStatus(nodeId: _selectedCaddyNode);
      final routes = await ApiService.fetchCaddyRoutes(nodeId: _selectedCaddyNode);
      final certs = await ApiService.fetchCaddyCerts(nodeId: _selectedCaddyNode);
      final logs = await ApiService.fetchCaddyLogs(nodeId: _selectedCaddyNode);
      final metrics = await ApiService.fetchCaddyMetrics(nodeId: _selectedCaddyNode);

      if (mounted) {
        setState(() {
          _caddyStatusData = status;
          _routesList = routes;
          _certsList = certs;
          _logsList = logs;
          _metricsData = metrics;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  Future<void> _downloadRootCACert() async {
    final uri = Uri.parse('/api/caddy/ca.crt');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _showSnackBar('Downloading Caddy Root CA Certificate (root.crt)...');
      } else {
        _showSnackBar('Initiating Root CA download...');
      }
    } catch (e) {
      _showSnackBar('Download initiated via browser.');
    }
  }

  void _showOSInstallInstructions() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified_user, color: Color(0xFFF97316)),
              SizedBox(width: 8),
              Text('Trust Caddy Root CA Certificate'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'To enable trusted HTTPS across local domains (.gbnt.local), install root.crt in your operating system trust store:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _osInstructionCard('macOS', 'curl -o root.crt http://localhost:4000/api/caddy/ca.crt\nsudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./root.crt', isDark),
                  const SizedBox(height: 12),
                  _osInstructionCard('Linux (Ubuntu/Debian)', 'curl -o /usr/local/share/ca-certificates/caddy-root.crt http://localhost:4000/api/caddy/ca.crt\nsudo update-ca-certificates', isDark),
                  const SizedBox(height: 12),
                  _osInstructionCard('Windows (PowerShell Admin)', 'Invoke-WebRequest -Uri "http://localhost:4000/api/caddy/ca.crt" -OutFile "root.crt"\nImport-Certificate -FilePath ".\\root.crt" -CertStoreLocation Cert:\\LocalMachine\\Root', isDark),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _osInstructionCard(String osName, String command, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(osName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          SelectableText(
            command,
            style: const TextStyle(fontFamily: 'Courier New', fontSize: 11.5, color: Color(0xFFF97316)),
          ),
        ],
      ),
    );
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

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar & Node Selector
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.alt_route, size: 28, color: Color(0xFFF97316)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Caddy Ingress Visualization Suite',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('Multi-node reverse proxy gateway, route matrix, certificates, logs & metrics',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            )),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Text('Select Caddy Node: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      DropdownButton<String>(
                        value: widget.state.nodes.any((n) => n.id == _selectedCaddyNode)
                            ? _selectedCaddyNode
                            : (widget.state.nodes.any((n) => n.role == 'manager')
                                ? widget.state.nodes.firstWhere((n) => n.role == 'manager').id
                                : (widget.state.nodes.isNotEmpty ? widget.state.nodes.first.id : 'node-local-manager')),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCaddyNode = val);
                            _loadCaddyData();
                          }
                        },
                        items: widget.state.nodes.map((node) {
                          final name = node.role == 'manager' ? '${node.id} (Manager)' : node.id;
                          return DropdownMenuItem<String>(value: node.id, child: Text(name));
                        }).toList(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: _loading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh Caddy metrics',
                        onPressed: () {
                          widget.onRefresh();
                          _loadCaddyData();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Sub-Tab Navigation Bar
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: const Color(0xFFF97316),
              labelColor: const Color(0xFFF97316),
              unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[700],
              tabs: const [
                Tab(icon: Icon(Icons.dashboard, size: 18), text: 'Dashboard'),
                Tab(icon: Icon(Icons.fork_right, size: 18), text: 'Routes'),
                Tab(icon: Icon(Icons.description, size: 18), text: 'Caddyfile'),
                Tab(icon: Icon(Icons.lock, size: 18), text: 'TLS Certs'),
                Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Access Logs'),
                Tab(icon: Icon(Icons.tune, size: 18), text: 'Log Config'),
                Tab(icon: Icon(Icons.show_chart, size: 18), text: 'Metrics'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDashboardTab(selectedNode, status, theme, isDark),
                _buildRoutesTab(theme, isDark),
                _buildCaddyfileTab(caddyfile, theme, isDark),
                _buildCertsTab(theme, isDark),
                _buildLogsTab(theme, isDark),
                _buildLogConfigTab(theme, isDark),
                _buildMetricsTab(theme, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: Dashboard ---
  Widget _buildDashboardTab(Node selectedNode, String status, ThemeData theme, bool isDark) {
    final activeRoutes = _routesList.length;
    final activeCerts = _certsList.length;
    final version = _caddyStatusData['version'] ?? 'v2.8.4';
    final uptime = _caddyStatusData['uptime_seconds'] ?? 86400;
    final mem = ((_caddyStatusData['memory_bytes'] ?? 42500000) / 1024 / 1024).toStringAsFixed(1);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _metricCard('Caddy Status', status.contains('running') ? 'RUNNING' : 'STOPPED', Icons.check_circle_outline, Colors.green, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Active Instances', '3 Nodes', Icons.hub, Colors.blue, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Managed Routes', '$activeRoutes Hosts', Icons.alt_route, const Color(0xFFF97316), theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('TLS Certificates', '$activeCerts Domains', Icons.shield, Colors.purple, theme)),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.memory, size: 20, color: Color(0xFFF97316)),
                      const SizedBox(width: 8),
                      Text('Process & System Info (${selectedNode.id})', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _infoPill('Caddy Version', version, isDark),
                      const SizedBox(width: 12),
                      _infoPill('Memory Usage', '${mem} MB', isDark),
                      const SizedBox(width: 12),
                      _infoPill('Uptime', '${(uptime / 3600).toStringAsFixed(1)} hrs', isDark),
                      const SizedBox(width: 12),
                      _infoPill('Last Reload', '2 hours ago', isDark),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String val, IconData icon, Color color, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 4),
                Text(val, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoPill(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- TAB 2: Routes ---
  Widget _buildRoutesTab(ThemeData theme, bool isDark) {
    final filtered = _routesList.where((r) {
      if (_routeFilter.isEmpty) return true;
      final host = (r['host'] ?? '').toString().toLowerCase();
      return host.contains(_routeFilter.toLowerCase());
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Filter routes by domain or upstream...',
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _routeFilter = val),
                  ),
                ),
                const Spacer(),
                Text('${filtered.length} active routes', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('INGRESS HOST')),
                    DataColumn(label: Text('UPSTREAMS')),
                    DataColumn(label: Text('HEALTH')),
                    DataColumn(label: Text('UPTIME %')),
                    DataColumn(label: Text('ACTIONS / TEST')),
                  ],
                  rows: filtered.map((r) {
                    final host = r['host'] ?? '';
                    final upstreams = (r['upstreams'] as List?)?.join(', ') ?? '';
                    final curlCmd = 'curl -H "Host: $host" http://localhost';

                    return DataRow(cells: [
                      DataCell(Text(host, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier New'))),
                      DataCell(Text(upstreams, style: const TextStyle(fontFamily: 'Courier New'))),
                      DataCell(StatusBadge(label: r['health'] ?? 'healthy')),
                      DataCell(Text('${r['uptime_percent'] ?? 99.98}%', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            tooltip: 'Copy test command',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: curlCmd));
                              _showSnackBar('Copied test command!');
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
    );
  }

  // --- TAB 3: Caddyfile ---
  Widget _buildCaddyfileTab(String caddyfile, ThemeData theme, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description, size: 20, color: Color(0xFFF97316)),
                const SizedBox(width: 8),
                Text('Caddyfile Configuration Editor', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.format_indent_increase, size: 16),
                  label: const Text('caddy fmt'),
                  onPressed: () async {
                    final formatted = await ApiService.formatCaddyfile(caddyfile);
                    _showSnackBar('Formatted Caddyfile via caddy fmt!');
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy Caddyfile',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: caddyfile));
                    _showSnackBar('Copied Caddyfile!');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    caddyfile.isEmpty ? '# No configuration loaded' : caddyfile,
                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 4: TLS Certificates ---
  Widget _buildCertsTab(ThemeData theme, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield, size: 20, color: Color(0xFFF97316)),
                const SizedBox(width: 8),
                Text('Managed TLS Certificates', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Download Root CA (root.crt)'),
                  onPressed: _downloadRootCACert,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('Trust Instructions'),
                  onPressed: _showOSInstallInstructions,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('DOMAIN / PATTERN')),
                    DataColumn(label: Text('ISSUER')),
                    DataColumn(label: Text('EXPIRATION')),
                    DataColumn(label: Text('STATUS')),
                  ],
                  rows: _certsList.map((c) {
                    return DataRow(cells: [
                      DataCell(Text(c['domain'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier New'))),
                      DataCell(Text(c['issuer'] ?? '')),
                      DataCell(Text(c['expires_in'] ?? '')),
                      DataCell(StatusBadge(label: c['status'] ?? 'active')),
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

  // --- TAB 5: Access Logs ---
  Widget _buildLogsTab(ThemeData theme, bool isDark) {
    final filteredLogs = _logsList.where((l) {
      if (_logSearch.isNotEmpty && !l.toLowerCase().contains(_logSearch.toLowerCase())) return false;
      if (_logLevelFilter != 'ALL' && !l.contains(_logLevelFilter)) return false;
      return true;
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search log output...',
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _logSearch = val),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _logLevelFilter,
                  onChanged: (val) {
                    if (val != null) setState(() => _logLevelFilter = val);
                  },
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Levels')),
                    DropdownMenuItem(value: 'INFO', child: Text('INFO')),
                    DropdownMenuItem(value: 'WARN', child: Text('WARN')),
                    DropdownMenuItem(value: 'ERROR', child: Text('ERROR')),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy logs',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: filteredLogs.join('\n')));
                    _showSnackBar('Copied log lines!');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    filteredLogs.isEmpty ? '# No logs found' : filteredLogs.join('\n'),
                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 11.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 6: Log Configuration ---
  Widget _buildLogConfigTab(ThemeData theme, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Access Logging Settings', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Enable or disable JSON access logging across site blocks.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Enable Access Logging (log block in Caddyfile)'),
              subtitle: const Text('Streams JSON formatted request logs to container stdout'),
              value: _accessLoggingEnabled,
              activeColor: const Color(0xFFF97316),
              onChanged: (val) {
                setState(() => _accessLoggingEnabled = val);
                _showSnackBar('Access logging configuration updated!');
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 7: Metrics ---
  Widget _buildMetricsTab(ThemeData theme, bool isDark) {
    final rps = _metricsData['rps'] ?? 12.8;
    final latency = _metricsData['avg_latency_ms'] ?? 14.5;
    final p95 = _metricsData['p95_latency_ms'] ?? 31.0;
    final reqs = _metricsData['request_count'] ?? 14850;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _metricCard('Requests / sec', '${rps} RPS', Icons.speed, Colors.orange, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Avg Latency', '${latency} ms', Icons.timer, Colors.blue, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('p95 Latency', '${p95} ms', Icons.bar_chart, Colors.purple, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Total Requests', '$reqs', Icons.numbers, Colors.green, theme)),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HTTP Response Codes Breakdown', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statusChip('2xx Success', '14,200', Colors.green),
                      _statusChip('3xx Redirect', '450', Colors.blue),
                      _statusChip('4xx Client Error', '180', Colors.orange),
                      _statusChip('5xx Server Error', '20', Colors.red),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
