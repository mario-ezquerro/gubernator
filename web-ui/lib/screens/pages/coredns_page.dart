import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../utils/clipboard_service.dart';

/// CoreDNS page — records table + config editor.
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

class _CoreDnsPageState extends State<CoreDnsPage> {
  String _searchQuery = '';
  int _tabIndex = 0; // 0 = Records, 1 = Configuration
  final TextEditingController _configController = TextEditingController();
  final TextEditingController _forwardersController = TextEditingController();
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _configController.addListener(() {
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
    });
  }

  @override
  void dispose() {
    _configController.dispose();
    _forwardersController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final config = await ApiService.getCoreDNSConfig();
      if (mounted) {
        setState(() { _configController.text = config; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load CoreDNS config: $e')));
      }
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.updateCoreDNSConfig(_configController.text);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CoreDNS configuration saved and container restarted')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredDns = widget.state.dnsRecords.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.ip.toLowerCase().contains(_searchQuery) ||
          d.hostname.toLowerCase().contains(_searchQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_outlined, size: 22, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text('CoreDNS', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Records')),
                        ButtonSegment(value: 1, label: Text('Configuration')),
                      ],
                      selected: {_tabIndex},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() => _tabIndex = newSelection.first);
                        if (_tabIndex == 1 && _configController.text.isEmpty) {
                          _loadConfig();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_tabIndex == 0) ...[
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search DNS records...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  ),
                  const SizedBox(height: 16),
                  if (filteredDns.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(children: [
                          Icon(Icons.dns, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Text(
                            widget.state.dnsRecords.isEmpty ? 'No DNS records found' : 'No matching records found',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ]),
                      ),
                    )
                  else
                    Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('IP ADDRESS')),
                            DataColumn(label: Text('HOSTNAME (DOMAIN)')),
                            DataColumn(label: Text('TEST RESOLUTION (CURL)')),
                          ],
                          rows: filteredDns.map((d) => DataRow(cells: [
                            DataCell(SelectableText(d.ip,
                                style: const TextStyle(fontFamily: 'Courier New', fontSize: 13))),
                            DataCell(SelectableText(d.hostname,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Courier New', fontSize: 13))),
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copied curl command!')),
                                  );
                                },
                              ),
                            ])),
                          ])).toList(),
                        ),
                      ),
                    ),
                ] else ...[
                  if (_isLoading)
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
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.public, size: 20, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('External DNS Forwarders', style: theme.textTheme.titleMedium),
                              ]),
                              const SizedBox(height: 8),
                              Text(
                                'Gubernator uses these servers to resolve external internet domains. '
                                'You can enter one or more IP addresses separated by spaces (e.g. 8.8.8.8 1.1.1.1).',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _forwardersController,
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
                          controller: _configController,
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
                            onPressed: _saveConfig,
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
