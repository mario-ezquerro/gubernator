import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../utils/clipboard_service.dart';
import '../../widgets/common_widgets.dart';

/// Comprehensive CoreDNS 4-Tab Management Suite
class CoreDnsPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;

  const CoreDnsPage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<CoreDnsPage> createState() => _CoreDnsPageState();
}

class _CoreDnsPageState extends State<CoreDnsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  CoreDNSStatusInfo? _statusInfo;
  List<CustomDNSRecord> _customRecords = [];
  bool _loadingData = true;

  // Tab 0: Auto Search
  String _autoSearchQuery = '';

  // Tab 1: Custom Search
  String _customSearchQuery = '';

  // Tab 2: Dig Playground
  final TextEditingController _digDomainController = TextEditingController(text: 'payment.checkout-stack.gbnt');
  String _digRecordType = 'A';
  DNSDigResult? _digResult;
  bool _runningDig = false;

  // Tab 3: Config Editor
  final TextEditingController _configController = TextEditingController();
  final TextEditingController _forwardersController = TextEditingController();
  bool _loadingConfig = false;
  bool _savingConfig = false;

  final ScrollController _autoScrollController = ScrollController();
  final ScrollController _customScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _configController.addListener(_onConfigTextChange);
    _loadSuiteData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _digDomainController.dispose();
    _configController.removeListener(_onConfigTextChange);
    _configController.dispose();
    _forwardersController.dispose();
    _autoScrollController.dispose();
    _customScrollController.dispose();
    super.dispose();
  }

  void _onConfigTextChange() {
    final lines = _configController.text.split('\n');
    for (var line in lines) {
      if (line.trim().startsWith('forward . ')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        final ips = parts.length > 2 ? parts.sublist(2).join(' ') : '';
        if (_forwardersController.text != ips) {
          _forwardersController.text = ips;
        }
        break;
      }
    }
  }

  Future<void> _loadSuiteData() async {
    setState(() => _loadingData = true);
    try {
      final statusFuture = ApiService.fetchCoreDNSStatusInfo();
      final customFuture = ApiService.fetchCustomDNSRecords();

      final results = await Future.wait([statusFuture, customFuture]);

      if (mounted) {
        setState(() {
          _statusInfo = results[0] as CoreDNSStatusInfo;
          _customRecords = results[1] as List<CustomDNSRecord>;
          _loadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _loadConfig() async {
    setState(() => _loadingConfig = true);
    try {
      final config = await ApiService.getCoreDNSConfig();
      if (mounted) {
        setState(() {
          _configController.text = config;
          _loadingConfig = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingConfig = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load Corefile: $e')));
      }
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _savingConfig = true);
    try {
      final ok = await ApiService.updateCoreDNSConfig(_configController.text);
      if (mounted) {
        setState(() => _savingConfig = false);
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CoreDNS configuration saved and container restarted.')),
          );
          _loadSuiteData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save Corefile.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingConfig = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving Corefile: $e')));
      }
    }
  }

  void _applyForwarderPreset(String ips) {
    _forwardersController.text = ips;
    _syncTextFromForwarders();
  }

  void _syncTextFromForwarders() {
    final ipsStr = _forwardersController.text.trim();
    var newForward = '    forward .';
    if (ipsStr.isNotEmpty) {
      final ips = ipsStr.split(RegExp(r'\s+'));
      newForward += ' ${ips.join(' ')}';
    }
    final lines = _configController.text.split('\n');
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
      if (_configController.text != newText) {
        _configController.text = newText;
      }
    }
  }

  Future<void> _runDigQuery() async {
    final domain = _digDomainController.text.trim();
    if (domain.isEmpty) return;

    setState(() => _runningDig = true);
    try {
      final res = await ApiService.performDNSDig(domain: domain, recordType: _digRecordType);
      if (mounted) {
        setState(() {
          _digResult = res;
          _runningDig = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _runningDig = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DNS Query Error: $e')));
      }
    }
  }

  void _showAddCustomRecordDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddCustomRecordDialog(
        onSaved: () => _loadSuiteData(),
      ),
    );
  }

  Future<void> _deleteCustomRecord(String id) async {
    final ok = await ApiService.deleteCustomDNSRecord(id);
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom DNS record deleted.')));
        _loadSuiteData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete custom record.')));
      }
    }
  }

  void _showCurlDialog(String hostname, String ip) {
    String selectedProtocol = 'http';
    String selectedMethod = 'GET';
    bool followRedirect = true;
    bool insecure = true;
    int timeoutSec = 5;
    bool running = true;
    DNSCurlResult? curlResult;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);

          void runCurl() async {
            setDialogState(() {
              running = true;
            });
            final res = await ApiService.performDNSCurl(
              hostname: hostname,
              ip: ip,
              protocol: selectedProtocol,
              method: selectedMethod,
              followRedirect: followRedirect,
              insecure: insecure,
              timeoutSeconds: timeoutSec,
            );
            if (context.mounted) {
              setDialogState(() {
                curlResult = res;
                running = false;
              });
            }
          }

          if (curlResult == null && running) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              runCurl();
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.terminal, color: Color(0xFF58A6FF), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Curl Resolution Test — $hostname',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Executing from Cluster Manager (Target IP: ${ip.isNotEmpty ? ip : "Dynamic"})',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 720,
              height: 540,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'http', label: Text('HTTP')),
                              ButtonSegment(value: 'https', label: Text('HTTPS')),
                            ],
                            selected: {selectedProtocol},
                            onSelectionChanged: (newVal) {
                              setDialogState(() {
                                selectedProtocol = newVal.first;
                              });
                              runCurl();
                            },
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: selectedMethod,
                            isDense: true,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 'GET', child: Text('GET')),
                              DropdownMenuItem(value: 'HEAD', child: Text('HEAD')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => selectedMethod = val);
                                runCurl();
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: followRedirect,
                                visualDensity: VisualDensity.compact,
                                onChanged: (v) {
                                  setDialogState(() => followRedirect = v ?? true);
                                  runCurl();
                                },
                              ),
                              const Text('-L (Follow)', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: running ? null : runCurl,
                            icon: running
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh, size: 16),
                            label: const Text('Re-run Curl'),
                            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (curlResult != null) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (curlResult!.statusCode >= 200 && curlResult!.statusCode < 300)
                                ? Colors.green.withValues(alpha: 0.2)
                                : (curlResult!.statusCode >= 300 && curlResult!.statusCode < 400)
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (curlResult!.statusCode >= 200 && curlResult!.statusCode < 300)
                                  ? Colors.green
                                  : (curlResult!.statusCode >= 300 && curlResult!.statusCode < 400)
                                      ? Colors.amber
                                      : Colors.red,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            curlResult!.statusCode > 0
                                ? '${curlResult!.statusCode} ${curlResult!.statusText}'
                                : (curlResult!.error ?? 'FAILED'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: (curlResult!.statusCode >= 200 && curlResult!.statusCode < 300)
                                  ? Colors.green
                                  : (curlResult!.statusCode >= 300 && curlResult!.statusCode < 400)
                                      ? Colors.amber
                                      : Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          avatar: const Icon(Icons.timer_outlined, size: 14),
                          label: Text('${curlResult!.latencyMs.toStringAsFixed(1)} ms'),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          avatar: const Icon(Icons.dns, size: 14),
                          label: Text(ip.isNotEmpty ? ip : 'Dynamic DNS'),
                          visualDensity: VisualDensity.compact,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy Curl Command',
                          onPressed: () {
                            ClipboardService.copy(curlResult!.command);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied curl command!')),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          tooltip: 'Open in Browser ($selectedProtocol://$hostname)',
                          onPressed: () {
                            html.window.open('$selectedProtocol://$hostname', '_blank');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: running && curlResult == null
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('Executing curl resolution test from cluster manager...',
                                      style: TextStyle(fontFamily: 'Courier New', color: Color(0xFF8B949E))),
                                ],
                              ),
                            )
                          : SelectableText(
                              curlResult?.rawOutput.isNotEmpty == true
                                  ? curlResult!.rawOutput
                                  : (curlResult?.error ?? 'No output returned'),
                              style: const TextStyle(
                                fontFamily: 'Courier New',
                                fontSize: 12,
                                color: Color(0xFF58A6FF),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (curlResult != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Output'),
                  onPressed: () {
                    ClipboardService.copy(curlResult!.rawOutput);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied curl output to clipboard!')),
                    );
                  },
                ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('Open in Browser ($selectedProtocol)'),
                onPressed: () {
                  html.window.open('$selectedProtocol://$hostname', '_blank');
                },
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPingDialog(String hostname, String ip) {
    int packetCount = 3;
    bool running = true;
    DNSPingResult? pingResult;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);

          void runPing() async {
            setDialogState(() {
              running = true;
            });
            final res = await ApiService.performDNSPing(
              hostname: hostname,
              ip: ip,
              count: packetCount,
            );
            if (context.mounted) {
              setDialogState(() {
                pingResult = res;
                running = false;
              });
            }
          }

          if (pingResult == null && running) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              runPing();
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3FB950).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.network_ping, color: Color(0xFF3FB950), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ping Reachability Test — $hostname',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('ICMP Network Reachability (Target: ${ip.isNotEmpty ? ip : hostname})',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 680,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          const Text('Packets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: packetCount,
                            isDense: true,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('1 packet')),
                              DropdownMenuItem(value: 3, child: Text('3 packets')),
                              DropdownMenuItem(value: 5, child: Text('5 packets')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => packetCount = val);
                                runPing();
                              }
                            },
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: running ? null : runPing,
                            icon: running
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh, size: 16),
                            label: const Text('Re-run Ping'),
                            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (pingResult != null) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: pingResult!.packetLoss == 0
                                ? Colors.green.withValues(alpha: 0.2)
                                : (pingResult!.packetLoss < 50)
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: pingResult!.packetLoss == 0
                                  ? Colors.green
                                  : (pingResult!.packetLoss < 50)
                                      ? Colors.amber
                                      : Colors.red,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '${pingResult!.packetLoss.toStringAsFixed(0)}% Packet Loss (${pingResult!.packetsRecv}/${pingResult!.packetsSent})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: pingResult!.packetLoss == 0
                                  ? Colors.green
                                  : (pingResult!.packetLoss < 50)
                                      ? Colors.amber
                                      : Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (pingResult!.avgLatency > 0)
                          Chip(
                            avatar: const Icon(Icons.speed, size: 14),
                            label: Text('Avg: ${pingResult!.avgLatency.toStringAsFixed(2)} ms'),
                            visualDensity: VisualDensity.compact,
                          ),
                        const SizedBox(width: 8),
                        if (pingResult!.minLatency > 0)
                          Chip(
                            label: Text('Min: ${pingResult!.minLatency.toStringAsFixed(2)} ms | Max: ${pingResult!.maxLatency.toStringAsFixed(2)} ms'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: running && pingResult == null
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('Executing ping from cluster manager...',
                                      style: TextStyle(fontFamily: 'Courier New', color: Color(0xFF8B949E))),
                                ],
                              ),
                            )
                          : SelectableText(
                              pingResult?.rawOutput.isNotEmpty == true
                                  ? pingResult!.rawOutput
                                  : (pingResult?.error ?? 'No output returned'),
                              style: const TextStyle(
                                fontFamily: 'Courier New',
                                fontSize: 12,
                                color: Color(0xFF3FB950),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (pingResult != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Output'),
                  onPressed: () {
                    ClipboardService.copy(pingResult!.rawOutput);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied ping output to clipboard!')),
                    );
                  },
                ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditClusterDomainDialog(String currentDomain) {
    final controller = TextEditingController(text: currentDomain);
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.language, color: Colors.cyanAccent),
              SizedBox(width: 10),
              Text('Edit Cluster Base Domain'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set the base DNS domain for internal service resolution across all Centurion nodes. '
                  'Gubernator will automatically regenerate container hostnames and reload CoreDNS without downtime.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Cluster Domain',
                    hintText: 'e.g. gbnt.local, acme.corp, internal.banco.es',
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Example: node-1.caddy.${controller.text.isNotEmpty ? controller.text.trim() : "domain"}',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 16),
              label: const Text('Save & Reload DNS'),
              onPressed: saving
                  ? null
                  : () async {
                      final newDomain = controller.text.trim().toLowerCase();
                      if (newDomain.isEmpty) return;
                      setDialogState(() => saving = true);
                      final ok = await ApiService.updateClusterDomain(newDomain);
                      if (mounted) {
                        Navigator.of(ctx).pop();
                        if (ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cluster base domain updated to $newDomain and CoreDNS reloaded.')),
                          );
                          widget.onRefresh();
                          _loadSuiteData();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to update cluster domain.')),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme) {
    final status = _statusInfo?.status ?? 'running';
    final totalRecords = _statusInfo?.totalRecords ?? widget.state.dnsRecords.length;
    final forwardersCount = _statusInfo?.forwarders.length ?? 2;
    final listeningPort = _statusInfo?.listeningPort ?? 5354;
    final clusterDomain = widget.state.clusterDomain.isNotEmpty ? widget.state.clusterDomain : 'gbnt.local';
    final canEdit = widget.state.currentUser?.role == 'admin';

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'SERVER STATUS',
            value: status.toUpperCase(),
            icon: Icons.dns,
            valueColor: status == 'running' ? Colors.green : Colors.red,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StatCard(
            label: 'CLUSTER DOMAIN',
            value: clusterDomain,
            icon: Icons.language,
            valueColor: Colors.cyanAccent,
            trailing: canEdit
                ? IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    tooltip: 'Edit Base Domain',
                    onPressed: () => _showEditClusterDomainDialog(clusterDomain),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StatCard(
            label: 'LISTENER PORT',
            value: '53 / $listeningPort',
            icon: Icons.settings_ethernet,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StatCard(
            label: 'TOTAL DNS RECORDS',
            value: '$totalRecords',
            icon: Icons.format_list_bulleted,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StatCard(
            label: 'FORWARDERS',
            value: '$forwardersCount Active',
            icon: Icons.public,
          ),
        ),
      ],
    );
  }

  // TAB 0: Auto-Discovered Stacks
  Widget _buildTabAutoDiscovered(ThemeData theme) {
    final filteredDns = widget.state.dnsRecords.where((d) {
      if (_autoSearchQuery.isEmpty) return true;
      return d.ip.toLowerCase().contains(_autoSearchQuery) || d.hostname.toLowerCase().contains(_autoSearchQuery);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search auto-discovered DNS records (*.gbnt)...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (val) => setState(() => _autoSearchQuery = val.toLowerCase()),
        ),
        const SizedBox(height: 16),
        if (filteredDns.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  Icon(Icons.dns, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text(
                    widget.state.dnsRecords.isEmpty ? 'No auto-discovered container DNS records' : 'No matching records found',
                    style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Scrollbar(
                controller: _autoScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _autoScrollController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('IP ADDRESS')),
                      DataColumn(label: Text('HOSTNAME (DOMAIN)')),
                      DataColumn(label: Text('TYPE')),
                      DataColumn(label: Text('ACTIONS & RESOLUTION TEST')),
                    ],
                    rows: filteredDns.map((d) {
                      return DataRow(cells: [
                        DataCell(SelectableText(d.ip, style: const TextStyle(fontFamily: 'Courier New', fontSize: 13))),
                        DataCell(SelectableText(d.hostname,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier New', fontSize: 13))),
                        DataCell(const Chip(label: Text('A', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), visualDensity: VisualDensity.compact)),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Curl Dialog Trigger
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.terminal, size: 14, color: Color(0xFF58A6FF)),
                              label: const Text('Curl', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF))),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _showCurlDialog(d.hostname, d.ip),
                            ),
                            const SizedBox(width: 6),
                            // Ping Dialog Trigger
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.network_ping, size: 14, color: Color(0xFF3FB950)),
                              label: const Text('Ping', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3FB950))),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _showPingDialog(d.hostname, d.ip),
                            ),
                            const SizedBox(width: 6),
                            // Browser Open (HTTP / HTTPS)
                            PopupMenuButton<String>(
                              tooltip: 'Open in Browser (HTTP / HTTPS)',
                              icon: const Icon(Icons.open_in_new, size: 18),
                              onSelected: (proto) {
                                final url = '$proto://${d.hostname}';
                                html.window.open(url, '_blank');
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'http',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.http, size: 16, color: Color(0xFFE3B341)),
                                      const SizedBox(width: 8),
                                      Text('Open http://${d.hostname}'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'https',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.lock_outline, size: 16, color: Color(0xFF3FB950)),
                                      const SizedBox(width: 8),
                                      Text('Open https://${d.hostname}'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // Copy Commands Menu
                            PopupMenuButton<String>(
                              tooltip: 'Copy Command or URL',
                              icon: const Icon(Icons.copy, size: 16),
                              onSelected: (cmd) {
                                ClipboardService.copy(cmd);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $cmd')));
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'curl -i http://${d.hostname}',
                                  child: const Text('Copy: curl -i http://...'),
                                ),
                                PopupMenuItem(
                                  value: 'curl -k -i https://${d.hostname}',
                                  child: const Text('Copy: curl -k -i https://...'),
                                ),
                                PopupMenuItem(
                                  value: 'ping -c 3 ${d.hostname}',
                                  child: const Text('Copy: ping -c 3 ...'),
                                ),
                                PopupMenuItem(
                                  value: 'http://${d.hostname}',
                                  child: const Text('Copy HTTP URL'),
                                ),
                                PopupMenuItem(
                                  value: 'https://${d.hostname}',
                                  child: const Text('Copy HTTPS URL'),
                                ),
                              ],
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
      ],
    );
  }

  // TAB 1: Custom Static DNS Records
  Widget _buildTabCustomRecords(ThemeData theme) {
    final filteredCustom = _customRecords.where((r) {
      if (_customSearchQuery.isEmpty) return true;
      final q = _customSearchQuery.toLowerCase();
      return r.domain.toLowerCase().contains(q) || r.ip.toLowerCase().contains(q) || r.recordType.toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search custom static DNS records...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (val) => setState(() => _customSearchQuery = val.toLowerCase()),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _showAddCustomRecordDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('+ Add Static Record'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filteredCustom.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.edit_note, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Text(
                      _customRecords.isEmpty ? 'No Custom Static DNS Records Configured' : 'No matching custom records found',
                      style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _showAddCustomRecordDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Static DNS Entry'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Scrollbar(
                controller: _customScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _customScrollController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('DOMAIN NAME')),
                      DataColumn(label: Text('RECORD TYPE')),
                      DataColumn(label: Text('TARGET VALUE / IP')),
                      DataColumn(label: Text('TTL (SEC)')),
                      DataColumn(label: Text('ACTIONS')),
                    ],
                    rows: filteredCustom.map((r) {
                      return DataRow(cells: [
                        DataCell(SelectableText(r.domain, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier New', fontSize: 13))),
                        DataCell(Chip(
                          label: Text(r.recordType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          visualDensity: VisualDensity.compact,
                        )),
                        DataCell(SelectableText(r.ip, style: const TextStyle(fontFamily: 'Courier New', fontSize: 13))),
                        DataCell(Text('${r.ttl}s')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.terminal, size: 16, color: Color(0xFF58A6FF)),
                                tooltip: 'Curl Test',
                                onPressed: () => _showCurlDialog(r.domain, r.ip),
                              ),
                              IconButton(
                                icon: const Icon(Icons.network_ping, size: 16, color: Color(0xFF3FB950)),
                                tooltip: 'Ping Test',
                                onPressed: () => _showPingDialog(r.domain, r.ip),
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 16),
                                tooltip: 'Open in Browser',
                                onPressed: () => html.window.open('http://${r.domain}', '_blank'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                tooltip: 'Delete custom record',
                                onPressed: () => _deleteCustomRecord(r.id),
                              ),
                            ],
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // TAB 2: DNS Playground & Dig Tester
  Widget _buildTabPlayground(ThemeData theme) {
    final sampleQueries = [
      'payment.checkout-stack.gbnt',
      'hello-101.gbnt.local',
      'google.com',
      'cloudflare.com',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CoreDNS Dig / Nslookup Playground', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Test domain resolution against CoreDNS (127.0.0.1:5354) and benchmark query latency',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _digDomainController,
                        decoration: const InputDecoration(
                          labelText: 'Domain Name to Query',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _digRecordType,
                        decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'A', child: Text('A Record')),
                          DropdownMenuItem(value: 'AAAA', child: Text('AAAA Record')),
                          DropdownMenuItem(value: 'CNAME', child: Text('CNAME')),
                          DropdownMenuItem(value: 'TXT', child: Text('TXT Record')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _digRecordType = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _runningDig ? null : _runDigQuery,
                      icon: _runningDig
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.play_arrow),
                      label: const Text('Execute Dig'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Sample Queries:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ...sampleQueries.map((q) => ActionChip(
                          label: Text(q, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _digDomainController.text = q;
                            _runDigQuery();
                          },
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_digResult != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _digResult!.status == 'NOERROR' ? Icons.check_circle : Icons.error,
                        color: _digResult!.status == 'NOERROR' ? Colors.green : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text('DNS Query Result — ${_digResult!.domain}',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Chip(
                        label: Text('Latency: ${_digResult!.queryTimeMs.toStringAsFixed(2)} ms',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green)),
                        backgroundColor: Colors.green.withValues(alpha: 0.1),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(_digResult!.status, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        backgroundColor: (_digResult!.status == 'NOERROR' ? Colors.green : Colors.red).withValues(alpha: 0.15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_digResult!.answers.isNotEmpty) ...[
                    const Text('Resolved Answers:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('NAME')),
                        DataColumn(label: Text('TYPE')),
                        DataColumn(label: Text('TTL')),
                        DataColumn(label: Text('DATA / IP')),
                      ],
                      rows: _digResult!.answers
                          .map((ans) => DataRow(cells: [
                                DataCell(SelectableText(ans.name, style: const TextStyle(fontFamily: 'Courier New', fontSize: 12))),
                                DataCell(Chip(label: Text(ans.type, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), visualDensity: VisualDensity.compact)),
                                DataCell(Text('${ans.ttl}s')),
                                DataCell(SelectableText(ans.data, style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, fontWeight: FontWeight.bold))),
                              ]))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Raw Nslookup Output:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _digResult!.rawOutput.isNotEmpty ? _digResult!.rawOutput : 'No raw stdout',
                      style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, color: Colors.greenAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // TAB 3: Upstream Forwarders & Corefile Editor
  Widget _buildTabConfig(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.public, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text('External Upstream DNS Forwarders', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Gubernator routes external internet domain queries through these servers. Enter IP addresses separated by spaces.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _forwardersController,
                  decoration: const InputDecoration(
                    labelText: 'DNS Forwarder IPs',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _syncTextFromForwarders(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Quick Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ActionChip(
                      label: const Text('Cloudflare (1.1.1.1 1.0.0.1)'),
                      onPressed: () => _applyForwarderPreset('1.1.1.1 1.0.0.1'),
                    ),
                    ActionChip(
                      label: const Text('Google (8.8.8.8 8.8.4.4)'),
                      onPressed: () => _applyForwarderPreset('8.8.8.8 8.8.4.4'),
                    ),
                    ActionChip(
                      label: const Text('Quad9 (9.9.9.9 149.112.112.112)'),
                      onPressed: () => _applyForwarderPreset('9.9.9.9 149.112.112.112'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                    Icon(Icons.code, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text('Raw Corefile Configuration', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _loadConfig,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reload Corefile'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _loadingConfig
                    ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                    : TextField(
                        controller: _configController,
                        maxLines: 14,
                        style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'CoreDNS Corefile Content',
                        ),
                      ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _savingConfig ? null : _saveConfig,
                    icon: _savingConfig
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: const Text('Save & Restart CoreDNS Container'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CoreDNS Management Suite', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Cluster Service Discovery, Static Records & DNS Playground',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                ],
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  widget.onRefresh();
                  _loadSuiteData();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _showAddCustomRecordDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('+ Add Static Record'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSummaryCards(theme),
          const SizedBox(height: 20),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            onTap: (idx) {
              if (idx == 3 && _configController.text.isEmpty) {
                _loadConfig();
              }
            },
            tabs: const [
              Tab(icon: Icon(Icons.lan, size: 18), text: 'Auto-Discovered (*.gbnt)'),
              Tab(icon: Icon(Icons.edit_note, size: 18), text: 'Custom Static Records'),
              Tab(icon: Icon(Icons.play_arrow, size: 18), text: 'DNS Playground (Dig)'),
              Tab(icon: Icon(Icons.settings, size: 18), text: 'Upstream & Corefile'),
            ],
          ),
          const SizedBox(height: 20),
          if (_loadingData)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else
            AnimatedBuilder(
              animation: _tabController,
              builder: (ctx, child) {
                switch (_tabController.index) {
                  case 0:
                    return _buildTabAutoDiscovered(theme);
                  case 1:
                    return _buildTabCustomRecords(theme);
                  case 2:
                    return _buildTabPlayground(theme);
                  case 3:
                    return _buildTabConfig(theme);
                  default:
                    return _buildTabAutoDiscovered(theme);
                }
              },
            ),
        ],
      ),
    );
  }
}

// Modal Dialog to Add Custom Static DNS Record
class _AddCustomRecordDialog extends StatefulWidget {
  final VoidCallback onSaved;

  const _AddCustomRecordDialog({required this.onSaved});

  @override
  State<_AddCustomRecordDialog> createState() => _AddCustomRecordDialogState();
}

class _AddCustomRecordDialogState extends State<_AddCustomRecordDialog> {
  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _ttlController = TextEditingController(text: '60');
  String _recordType = 'A';
  bool _saving = false;

  @override
  void dispose() {
    _domainController.dispose();
    _ipController.dispose();
    _ttlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final domain = _domainController.text.trim();
    final ip = _ipController.text.trim();
    final ttl = int.tryParse(_ttlController.text.trim()) ?? 60;

    if (domain.isEmpty || ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Domain and IP/Value are required.')));
      return;
    }

    setState(() => _saving = true);
    final ok = await ApiService.createCustomDNSRecord(
      domain: domain,
      ip: ip,
      recordType: _recordType,
      ttl: ttl,
    );

    if (mounted) {
      setState(() => _saving = false);
      if (ok) {
        widget.onSaved();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom static DNS record added successfully.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add custom DNS record.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text('Add Custom Static DNS Record', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _domainController,
                    decoration: const InputDecoration(
                      labelText: 'Domain Name',
                      hintText: 'e.g. redis.gbnt or api.mycompany.test',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _recordType,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'A', child: Text('A (IPv4)')),
                      DropdownMenuItem(value: 'AAAA', child: Text('AAAA (IPv6)')),
                      DropdownMenuItem(value: 'CNAME', child: Text('CNAME')),
                      DropdownMenuItem(value: 'TXT', child: Text('TXT')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _recordType = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Target Value / IP Address',
                hintText: 'e.g. 192.168.252.30',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ttlController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'TTL (Seconds)',
                suffixText: 'sec',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: const Text('Save Record & Reload DNS'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
