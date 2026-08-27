import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

/// Dedicated Loki Logs Explorer Page for cluster-wide container and node log inspection.
class LokiLogsPage extends StatefulWidget {
  final String? initialContainer;

  const LokiLogsPage({super.key, this.initialContainer});

  @override
  State<LokiLogsPage> createState() => _LokiLogsPageState();
}

class _LokiLogsPageState extends State<LokiLogsPage> {
  // Data State
  List<LokiLogEntry> _logs = [];
  bool _loading = true;
  String _driver = "loki";
  bool _lokiActive = false;

  // Available Filter Options
  List<String> _availableContainers = [];
  List<String> _availableNodes = [];
  List<String> _availableStreams = ["stdout", "stderr"];

  // Selected Filter State
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedNode = "";
  String _selectedContainer = "";
  String _selectedStream = "";
  String _selectedLevel = "";
  String _selectedRange = "1h";
  int _limit = 200;

  // Live Tail / Auto Refresh
  bool _liveTail = false;
  Timer? _tailTimer;
  final Set<String> _expandedLogIds = {};

  final List<String> _timeRanges = ["5m", "15m", "1h", "6h", "24h", "7d"];
  final List<int> _limits = [50, 100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    if (widget.initialContainer != null && widget.initialContainer!.isNotEmpty) {
      _selectedContainer = widget.initialContainer!;
    }
    _loadLabelsAndStatus();
    _fetchLogs();
  }

  @override
  void dispose() {
    _tailTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLabelsAndStatus() async {
    final status = await ApiService.fetchLokiStatus();
    final labels = await ApiService.fetchLokiLogLabels();
    if (mounted) {
      setState(() {
        _lokiActive = status["active"] == true;
        _driver = status["driver"] ?? "loki";
        _availableContainers = labels.containers;
        _availableNodes = labels.nodes;
        _availableStreams = labels.streams.isNotEmpty ? labels.streams : ["stdout", "stderr"];
      });
    }
  }

  Future<void> _fetchLogs() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService.queryLokiLogs(
        query: _searchCtrl.text.trim(),
        container: _selectedContainer,
        node: _selectedNode,
        stream: _selectedStream,
        level: _selectedLevel,
        timeRange: _selectedRange,
        limit: _limit,
      );
      if (mounted) {
        setState(() {
          _logs = (res["logs"] as List<LokiLogEntry>?) ?? [];
          _driver = res["driver"] ?? _driver;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _toggleLiveTail() {
    setState(() {
      _liveTail = !_liveTail;
      if (_liveTail) {
        _tailTimer?.cancel();
        _tailTimer = Timer.periodic(const Duration(seconds: 3), (t) {
          if (!_loading) {
            _fetchLogs();
          }
        });
      } else {
        _tailTimer?.cancel();
      }
    });
  }

  void _exportLogs() {
    List<String> params = [];
    if (_searchCtrl.text.trim().isNotEmpty) {
      params.add("query=${Uri.encodeQueryComponent(_searchCtrl.text.trim())}");
    }
    if (_selectedContainer.isNotEmpty) {
      params.add("container=${Uri.encodeQueryComponent(_selectedContainer)}");
    }
    if (_selectedNode.isNotEmpty) {
      params.add("node=${Uri.encodeQueryComponent(_selectedNode)}");
    }
    if (_selectedStream.isNotEmpty) {
      params.add("stream=${Uri.encodeQueryComponent(_selectedStream)}");
    }
    if (_selectedLevel.isNotEmpty) {
      params.add("level=${Uri.encodeQueryComponent(_selectedLevel)}");
    }
    params.add("range=$_selectedRange");

    final url = "/api/logs/export?${params.join("&")}";
    html.window.open(url, "_blank");
  }

  void _copyAllLogs() {
    if (_logs.isEmpty) return;
    final text = _logs.map((l) => "[${l.timestamp}] [${l.node}] [${l.container}] [${l.level}] ${l.message}").join("\n");
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Text("Copied ${_logs.length} log lines to clipboard"),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _selectedNode = "";
      _selectedContainer = "";
      _selectedStream = "";
      _selectedLevel = "";
      _selectedRange = "1h";
    });
    _fetchLogs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final errorCount = _logs.where((l) => l.level == "ERROR").length;
    final warnCount = _logs.where((l) => l.level == "WARN").length;
    final infoCount = _logs.length - errorCount - warnCount;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.receipt_long, color: theme.colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Loki Logs Explorer',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_driver == 'loki' ? Colors.green : Colors.blue).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (_driver == 'loki' ? Colors.green : Colors.blue).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _driver == 'loki' ? Icons.bolt : Icons.layers,
                                  size: 12,
                                  color: _driver == 'loki' ? Colors.green : Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _driver == 'loki' ? 'LOKI AGGREGATOR' : 'DOCKER DRIVER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _driver == 'loki' ? Colors.green : Colors.blue,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Cluster-wide container log aggregation and live stream search',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Action Toolbar
              Row(
                children: [
                  // Live Tail Toggle
                  OutlinedButton.icon(
                    onPressed: _toggleLiveTail,
                    icon: Icon(
                      _liveTail ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      size: 16,
                      color: _liveTail ? Colors.greenAccent : null,
                    ),
                    label: Text(
                      _liveTail ? 'Live Tail: ON' : 'Live Tail: OFF',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _liveTail ? FontWeight.bold : FontWeight.normal,
                        color: _liveTail ? Colors.greenAccent : null,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _liveTail ? Colors.green.withValues(alpha: 0.1) : null,
                      side: _liveTail ? const BorderSide(color: Colors.greenAccent) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Refresh Button
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh Logs',
                    onPressed: _loading ? null : _fetchLogs,
                  ),
                  const SizedBox(width: 8),
                  // Copy All
                  IconButton(
                    icon: const Icon(Icons.copy_all, size: 18),
                    tooltip: 'Copy all visible logs',
                    onPressed: _logs.isEmpty ? null : _copyAllLogs,
                  ),
                  const SizedBox(width: 8),
                  // Export Logs
                  OutlinedButton.icon(
                    onPressed: _exportLogs,
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('Export .log', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Deep link to Grafana Explore
                  OutlinedButton.icon(
                    onPressed: () {
                      final host = html.window.location.hostname ?? 'localhost';
                      html.window.open('http://$host:3000/explore', '_blank');
                    },
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Grafana Explore', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filters Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Search & Multi-filter Row
                  Row(
                    children: [
                      // Search Query Field
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _searchCtrl,
                          onSubmitted: (_) => _fetchLogs(),
                          decoration: InputDecoration(
                            hintText: 'Search text, error keyword, status code or regex...',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _fetchLogs();
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Node Dropdown
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedNode,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Centurion / Node',
                            prefixIcon: const Icon(Icons.dns, size: 16),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: [
                            const DropdownMenuItem(value: "", child: Text("All Nodes", style: TextStyle(fontSize: 12))),
                            ..._availableNodes.map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 12)))),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedNode = val ?? "");
                            _fetchLogs();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Container Dropdown
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedContainer,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Container / Service',
                            prefixIcon: const Icon(Icons.inventory_2, size: 16),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: [
                            const DropdownMenuItem(value: "", child: Text("All Containers", style: TextStyle(fontSize: 12))),
                            ..._availableContainers.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedContainer = val ?? "");
                            _fetchLogs();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Time Range Selector
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedRange,
                          decoration: InputDecoration(
                            labelText: 'Time Range',
                            prefixIcon: const Icon(Icons.access_time, size: 16),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: _timeRanges.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (val) {
                            setState(() => _selectedRange = val ?? "1h");
                            _fetchLogs();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Limit Selector
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<int>(
                          initialValue: _limit,
                          decoration: InputDecoration(
                            labelText: 'Limit',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: _limits.map((l) => DropdownMenuItem(value: l, child: Text("$l lines", style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (val) {
                            setState(() => _limit = val ?? 200);
                            _fetchLogs();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Search Button
                      ElevatedButton(
                        onPressed: _fetchLogs,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Search'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Quick Filter Chips Row (Level / Stream)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('Log Level: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          _buildFilterChip('All', _selectedLevel == '', () {
                            setState(() => _selectedLevel = '');
                            _fetchLogs();
                          }),
                          const SizedBox(width: 6),
                          _buildFilterChip('ERROR', _selectedLevel == 'ERROR', () {
                            setState(() => _selectedLevel = 'ERROR');
                            _fetchLogs();
                          }, color: Colors.redAccent),
                          const SizedBox(width: 6),
                          _buildFilterChip('WARN', _selectedLevel == 'WARN', () {
                            setState(() => _selectedLevel = 'WARN');
                            _fetchLogs();
                          }, color: Colors.orangeAccent),
                          const SizedBox(width: 6),
                          _buildFilterChip('INFO', _selectedLevel == 'INFO', () {
                            setState(() => _selectedLevel = 'INFO');
                            _fetchLogs();
                          }, color: Colors.blueAccent),
                          const SizedBox(width: 16),
                          const Text('Stream: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          _buildFilterChip('stdout', _selectedStream == 'stdout', () {
                            setState(() => _selectedStream = _selectedStream == 'stdout' ? '' : 'stdout');
                            _fetchLogs();
                          }),
                          const SizedBox(width: 6),
                          _buildFilterChip('stderr', _selectedStream == 'stderr', () {
                            setState(() => _selectedStream = _selectedStream == 'stderr' ? '' : 'stderr');
                            _fetchLogs();
                          }),
                        ],
                      ),

                      if (_selectedNode.isNotEmpty || _selectedContainer.isNotEmpty || _selectedLevel.isNotEmpty || _selectedStream.isNotEmpty || _searchCtrl.text.isNotEmpty)
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.filter_alt_off, size: 14),
                          label: const Text('Clear Filters', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Summary Ribbon
          Row(
            children: [
              _buildMetricBadge('Total Logs', '${_logs.length}', Icons.article, Colors.grey),
              const SizedBox(width: 12),
              _buildMetricBadge('Errors', '$errorCount', Icons.error_outline, Colors.redAccent),
              const SizedBox(width: 12),
              _buildMetricBadge('Warnings', '$warnCount', Icons.warning_amber, Colors.orangeAccent),
              const SizedBox(width: 12),
              _buildMetricBadge('Info / Output', '$infoCount', Icons.info_outline, Colors.blueAccent),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Terminal Log Stream View
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey.shade600),
                          const SizedBox(height: 12),
                          Text(
                            _loading ? 'Fetching logs from cluster...' : 'No logs found matching criteria',
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                          if (!_loading && (_selectedContainer.isNotEmpty || _searchCtrl.text.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _clearFilters,
                              child: const Text('Reset search filters'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (context, idx) {
                        final log = _logs[idx];
                        final logId = "${log.timestampNs}_$idx";
                        final isExpanded = _expandedLogIds.contains(logId);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedLogIds.remove(logId);
                                  } else {
                                    _expandedLogIds.add(logId);
                                  }
                                });
                              },
                              hoverColor: Colors.white.withValues(alpha: 0.04),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Expand toggle icon
                                    Icon(
                                      isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                                      size: 16,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),

                                    // Timestamp
                                    Text(
                                      log.timestamp,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // Node pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.purple.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        log.node,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Color(0xFFC084FC),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Container pill
                                    InkWell(
                                      onTap: () {
                                        setState(() => _selectedContainer = log.container);
                                        _fetchLogs();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.cyan.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
                                        ),
                                        child: Text(
                                          log.container,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF38BDF8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Level pill
                                    _buildLevelBadge(log.level, log.stream),
                                    const SizedBox(width: 12),

                                    // Message Body with search highlighting
                                    Expanded(
                                      child: _buildHighlightedMessage(log.message, _searchCtrl.text.trim()),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Expandable Details Box
                            if (isExpanded)
                              Container(
                                margin: const EdgeInsets.only(left: 36, right: 16, bottom: 8, top: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Structured Stream Metadata',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                        ),
                                        TextButton.icon(
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: log.message));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text("Log line copied to clipboard"),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.copy, size: 12),
                                          label: const Text('Copy Raw Message', style: TextStyle(fontSize: 11)),
                                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        _buildMetaItem('Timestamp (ns)', log.timestampNs),
                                        _buildMetaItem('Container', log.container),
                                        _buildMetaItem('Node', log.node),
                                        _buildMetaItem('Stream', log.stream),
                                        _buildMetaItem('Level', log.level),
                                        if (log.labels.isNotEmpty)
                                          ...log.labels.entries.map((e) => _buildMetaItem(e.key, e.value)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            Divider(height: 1, color: Colors.white.withValues(alpha: 0.04)),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap, {Color? color}) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? chipColor : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? chipColor : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricBadge(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildLevelBadge(String level, String stream) {
    Color bg = Colors.blue;
    Color fg = Colors.white;
    String text = level;

    switch (level.toUpperCase()) {
      case 'ERROR':
      case 'FATAL':
      case 'PANIC':
        bg = Colors.red.shade700;
        text = 'ERR';
        break;
      case 'WARN':
      case 'WARNING':
        bg = Colors.orange.shade700;
        text = 'WARN';
        break;
      case 'INFO':
        bg = Colors.blue.shade700;
        text = 'INFO';
        break;
      default:
        bg = stream == 'stderr' ? Colors.red.shade700 : Colors.grey.shade700;
        text = stream.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: bg.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: bg,
        ),
      ),
    );
  }

  Widget _buildHighlightedMessage(String message, String searchTerm) {
    if (searchTerm.isEmpty || !message.toLowerCase().contains(searchTerm.toLowerCase())) {
      return Text(
        message,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Color(0xFFE2E8F0),
          height: 1.3,
        ),
      );
    }

    final lowerMsg = message.toLowerCase();
    final lowerTerm = searchTerm.toLowerCase();
    List<TextSpan> spans = [];
    int start = 0;

    while (true) {
      final idx = lowerMsg.indexOf(lowerTerm, start);
      if (idx == -1) {
        spans.add(TextSpan(text: message.substring(start), style: const TextStyle(color: Color(0xFFE2E8F0))));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: message.substring(start, idx), style: const TextStyle(color: Color(0xFFE2E8F0))));
      }
      spans.add(TextSpan(
        text: message.substring(idx, idx + searchTerm.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFF59E0B),
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = idx + searchTerm.length;
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.3),
        children: spans,
      ),
    );
  }

  Widget _buildMetaItem(String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          children: [
            TextSpan(text: '$key: ', style: const TextStyle(color: Colors.grey)),
            TextSpan(text: value, style: const TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
