import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

/// Dedicated eBPF Live Hub Page for Kernel Network Observability,
/// L4/L7 Flow Tracing, and Service Mesh Topology.
class EbpfPage extends StatefulWidget {
  const EbpfPage({super.key});

  @override
  State<EbpfPage> createState() => _EbpfPageState();
}

class _EbpfPageState extends State<EbpfPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Telemetry & State
  EbpfStats? _stats;
  List<EbpfFlow> _flows = [];
  EbpfTopology? _topology;
  bool _loading = true;

  // Filters
  String _selectedProtocol = 'ALL';
  String _selectedStatus = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();
  int _limit = 50;

  // Live Auto-Refresh
  bool _autoRefresh = true;
  Timer? _refreshTimer;

  final List<String> _protocols = [
    'ALL',
    'HTTP',
    'gRPC',
    'DNS',
    'TCP',
    'UDP',
    'REDIS',
    'POSTGRES',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
    _startTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    if (_autoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) {
          _fetchFlowsAndStatsSilently();
        }
      });
    }
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
      if (_autoRefresh) {
        _startTimer();
      } else {
        _refreshTimer?.cancel();
      }
    });
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      final statsFuture = ApiService.fetchEbpfStats();
      final flowsFuture = ApiService.fetchEbpfFlows(
        limit: _limit,
        protocol: _selectedProtocol,
        status: _selectedStatus,
        query: _searchCtrl.text.trim(),
      );
      final topoFuture = ApiService.fetchEbpfTopology();

      final results = await Future.wait([statsFuture, flowsFuture, topoFuture]);
      if (mounted) {
        setState(() {
          _stats = results[0] as EbpfStats;
          _flows = results[1] as List<EbpfFlow>;
          _topology = results[2] as EbpfTopology;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _fetchFlowsAndStatsSilently() async {
    try {
      final statsFuture = ApiService.fetchEbpfStats();
      final flowsFuture = ApiService.fetchEbpfFlows(
        limit: _limit,
        protocol: _selectedProtocol,
        status: _selectedStatus,
        query: _searchCtrl.text.trim(),
      );
      final topoFuture = _tabController.index == 1 ? ApiService.fetchEbpfTopology() : null;

      final stats = await statsFuture;
      final flows = await flowsFuture;
      EbpfTopology? topo;
      if (topoFuture != null) {
        topo = await topoFuture;
      }

      if (mounted) {
        setState(() {
          _stats = stats;
          _flows = flows;
          if (topo != null) {
            _topology = topo;
          }
        });
      }
    } catch (_) {}
  }

  void _openSimulationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _SimulationDialog(
        onSimulate: (pattern, rate, duration, errors) async {
          final success = await ApiService.simulateEbpfTraffic(
            pattern: pattern,
            rate: rate,
            durationS: duration,
            errorPct: errors,
          );
          if (mounted && success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚡ eBPF traffic simulation started ($pattern @ $rate req/s)'),
                backgroundColor: const Color(0xFF06B6D4),
                behavior: SnackBarBehavior.floating,
              ),
            );
            _fetchFlowsAndStatsSilently();
          }
        },
      ),
    );
  }

  void _openFlowDetails(EbpfFlow flow) {
    showDialog(
      context: context,
      builder: (ctx) => _FlowDetailsDialog(flow: flow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top Header Toolbar ─────────────────────────────────────────
          _buildHeaderToolbar(theme),

          // ── Navigation Tabs ────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFF06B6D4),
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: const Color(0xFF06B6D4),
              indicatorWeight: 3,
              tabs: [
                Tab(
                  icon: const Icon(Icons.swap_calls, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Live Captured Flows'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_flows.length}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF06B6D4)),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  icon: const Icon(Icons.hub, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Service Mesh Topology'),
                      if (_topology != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_topology!.nodes.length} Nodes',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(
                  icon: Icon(Icons.memory, size: 18),
                  text: 'Kernel Probes & Diagnostics',
                ),
              ],
            ),
          ),

          // ── Tab Views ──────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFlowsTab(theme),
                      _buildTopologyTab(theme),
                      _buildDiagnosticsTab(theme),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderToolbar(ThemeData theme) {
    final mode = _stats?.mode ?? 'kernel';
    final isKernel = mode == 'kernel';
    final kernelVer = _stats?.kernelVersion ?? 'detecting...';
    final activeProbes = _stats?.activeProbes ?? 8;
    final pktsRate = _stats?.packetsPerSec ?? 0.0;
    final bytesRate = _stats?.bytesPerSec ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.grain, color: Color(0xFF06B6D4), size: 22),
          ),
          const SizedBox(width: 14),

          // Title & Subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'eBPF Live Hub & Kernel Observability',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  // Mode Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isKernel
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isKernel
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isKernel ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isKernel ? 'eBPF KERNEL ACTIVE' : 'eBPF EMULATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isKernel ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Kernel $kernelVer • Socket & packet tracing with L4/L7 protocol decoding and service mesh topology.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),

          const Spacer(),

          // Telemetry Pills
          _buildPill(
            icon: Icons.shield,
            label: 'Probes',
            value: '$activeProbes Active',
            color: const Color(0xFF06B6D4),
            theme: theme,
          ),
          const SizedBox(width: 8),
          _buildPill(
            icon: Icons.speed,
            label: 'Rate',
            value: '${pktsRate.toStringAsFixed(1)} pkts/s',
            color: Colors.blueAccent,
            theme: theme,
          ),
          const SizedBox(width: 8),
          _buildPill(
            icon: Icons.swap_vert,
            label: 'Throughput',
            value: _formatBytesRate(bytesRate),
            color: Colors.tealAccent,
            theme: theme,
          ),

          const SizedBox(width: 16),

          // Live Tail Toggle
          OutlinedButton.icon(
            onPressed: _toggleAutoRefresh,
            icon: Icon(
              _autoRefresh ? Icons.pause_circle_outline : Icons.play_circle_outline,
              size: 16,
              color: _autoRefresh ? const Color(0xFF10B981) : Colors.grey,
            ),
            label: Text(
              _autoRefresh ? 'Live Tail (2s)' : 'Paused',
              style: TextStyle(color: _autoRefresh ? const Color(0xFF10B981) : null),
            ),
          ),
          const SizedBox(width: 8),

          // Refresh Button
          IconButton(
            tooltip: 'Refresh Now',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadAllData,
          ),
          const SizedBox(width: 8),

          // Simulation Button
          FilledButton.icon(
            onPressed: _openSimulationDialog,
            icon: const Icon(Icons.bolt, size: 16),
            label: const Text('Simulate Traffic'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF06B6D4),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 0: Flows Stream ───────────────────────────────────────────────────

  Widget _buildFlowsTab(ThemeData theme) {
    return Column(
      children: [
        // Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              // Protocol Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _protocols.map((p) {
                    final selected = _selectedProtocol == p;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: selected,
                        label: Text(p, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : null)),
                        selectedColor: const Color(0xFF06B6D4).withValues(alpha: 0.25),
                        checkmarkColor: const Color(0xFF06B6D4),
                        onSelected: (val) {
                          setState(() {
                            _selectedProtocol = val ? p : 'ALL';
                          });
                          _fetchFlowsAndStatsSilently();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(width: 12),
              Container(width: 1, height: 24, color: theme.dividerColor),
              const SizedBox(width: 12),

              // Status Dropdown
              DropdownButton<String>(
                value: _selectedStatus,
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All Health', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'healthy', child: Text('Healthy 🟢', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'warning', child: Text('Warning 🟡', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'error', child: Text('Errors 🔴', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'ERRORS', child: Text('Any Issues ⚠️', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedStatus = val);
                    _fetchFlowsAndStatsSilently();
                  }
                },
              ),

              const SizedBox(width: 16),

              // Search Text Field
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search container, IP, method or path...',
                      hintStyle: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchCtrl.clear();
                                _fetchFlowsAndStatsSilently();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _fetchFlowsAndStatsSilently(),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Limit Dropdown
              DropdownButton<int>(
                value: _limit,
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 25, child: Text('25 rows', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 50, child: Text('50 rows', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 100, child: Text('100 rows', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 200, child: Text('200 rows', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _limit = val);
                    _fetchFlowsAndStatsSilently();
                  }
                },
              ),
            ],
          ),
        ),

        // Flows Table
        Expanded(
          child: _flows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        'No captured network flows matching criteria.',
                        style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _openSimulationDialog,
                        icon: const Icon(Icons.bolt, size: 16),
                        label: const Text('Inject Test Traffic'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _flows.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.2)),
                  itemBuilder: (ctx, idx) {
                    final flow = _flows[idx];
                    return _buildFlowRow(flow, theme);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFlowRow(EbpfFlow flow, ThemeData theme) {
    final timeStr = "${flow.timestamp.hour.toString().padLeft(2, '0')}:${flow.timestamp.minute.toString().padLeft(2, '0')}:${flow.timestamp.second.toString().padLeft(2, '0')}";
    final protoColor = _getProtocolColor(flow.protocol);
    final isErr = flow.status == 'error';
    final isWarn = flow.status == 'warning';

    Color statusColor = const Color(0xFF10B981);
    String statusLabel = 'HEALTHY';
    if (isErr) {
      statusColor = const Color(0xFFEF4444);
      statusLabel = flow.statusCode > 0 ? '${flow.statusCode} ERR' : 'DROPPED';
    } else if (isWarn) {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = flow.statusCode > 0 ? '${flow.statusCode} WARN' : 'SLOW';
    } else if (flow.statusCode > 0) {
      statusLabel = '${flow.statusCode} OK';
    }

    return InkWell(
      onTap: () => _openFlowDetails(flow),
      hoverColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Time
            Text(
              timeStr,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 14),

            // Protocol Chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: protoColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: protoColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                flow.protocol,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: protoColor),
              ),
            ),
            const SizedBox(width: 14),

            // Source Container & IP
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          flow.sourceName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          "${flow.sourceIp}:${flow.sourcePort}",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Arrow
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
            ),

            // Destination Container & IP
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  const Icon(Icons.cloud_download_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          flow.destName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          "${flow.destIp}:${flow.destPort}",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Target Method / Path
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    if (flow.method.isNotEmpty) ...[
                      Text(
                        flow.method,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: flow.method == 'POST' ? Colors.blueAccent : Colors.tealAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        flow.path.isNotEmpty ? flow.path : '${flow.destPort}/tcp',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Latency (RTT)
            SizedBox(
              width: 75,
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 13,
                    color: flow.latencyMs > 50 ? Colors.amber : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${flow.latencyMs.toStringAsFixed(1)} ms',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: flow.latencyMs > 100
                          ? Colors.redAccent
                          : (flow.latencyMs > 30 ? Colors.amber : null),
                    ),
                  ),
                ],
              ),
            ),

            // Bandwidth Rate
            SizedBox(
              width: 85,
              child: Text(
                _formatBytesRate(flow.throughputBps),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
              ),
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Service Mesh Topology ──────────────────────────────────────────

  Widget _buildTopologyTab(ThemeData theme) {
    if (_topology == null || _topology!.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'No active topology nodes registered yet.',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    final nodes = _topology!.nodes;
    final edges = _topology!.edges;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topology KPI Banner
          Row(
            children: [
              _buildMetricCard(
                title: 'MESH NODES',
                value: '${nodes.length}',
                subtitle: 'Discovered services & containers',
                icon: Icons.device_hub,
                color: const Color(0xFF06B6D4),
                theme: theme,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                title: 'ACTIVE EDGES',
                value: '${edges.length}',
                subtitle: 'Inter-service communication links',
                icon: Icons.linear_scale,
                color: Colors.purpleAccent,
                theme: theme,
              ),
              const SizedBox(width: 14),
              _buildMetricCard(
                title: 'AGGREGATE RATE',
                value: _formatBytesRate(_stats?.bytesPerSec ?? 0.0),
                subtitle: 'Throughput across all mesh edges',
                icon: Icons.speed,
                color: Colors.tealAccent,
                theme: theme,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Communication Edges Table
          Text(
            'Active Service Communication Edges',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Real-time traffic flow matrix monitored by kernel socket filters and eBPF probes.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: edges.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.2)),
              itemBuilder: (ctx, idx) {
                final e = edges[idx];
                final protoColor = _getProtocolColor(e.protocol);
                final hasErrors = e.errorRate > 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Source
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(e.sourceId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),

                      // Direction Arrow with Protocol
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: protoColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(e.protocol, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: protoColor)),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_right_alt, size: 20, color: Color(0xFF06B6D4)),
                          ],
                        ),
                      ),

                      // Target
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(e.targetId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),

                      const Spacer(),

                      // Latency (RTT)
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('${e.rttMs.toStringAsFixed(1)} ms', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ],
                      ),
                      const SizedBox(width: 20),

                      // Throughput
                      Row(
                        children: [
                          const Icon(Icons.swap_vert, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(_formatBytesRate(e.throughputBps), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ],
                      ),
                      const SizedBox(width: 20),

                      // Active flows count
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${e.activeFlows} flows', style: const TextStyle(fontSize: 10, color: Colors.blueAccent)),
                      ),

                      const SizedBox(width: 14),

                      // Error Rate badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: hasErrors ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: hasErrors ? Colors.red.withValues(alpha: 0.4) : Colors.green.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          hasErrors ? '${e.errorRate.toStringAsFixed(1)}% ERR' : 'HEALTHY 100%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: hasErrors ? Colors.redAccent : Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Mesh Nodes Cards Grid
          Text(
            'Service Mesh Nodes & Container Endpoints',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisExtent: 135,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: nodes.length,
            itemBuilder: (ctx, idx) {
              final n = nodes[idx];
              final isDb = n.type == 'database';
              final isIngress = n.type == 'ingress';
              final isDns = n.type == 'dns';

              IconData icon = Icons.apps;
              Color iconColor = const Color(0xFF06B6D4);
              if (isDb) {
                icon = Icons.storage;
                iconColor = Colors.orangeAccent;
              } else if (isIngress) {
                icon = Icons.alt_route;
                iconColor = Colors.purpleAccent;
              } else if (isDns) {
                icon = Icons.manage_search;
                iconColor = Colors.tealAccent;
              }

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(icon, color: iconColor, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  n.ip.isNotEmpty ? n.ip : n.type.toUpperCase(),
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('RUNNING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green)),
                          ),
                        ],
                      ),

                      Divider(height: 12, color: theme.dividerColor.withValues(alpha: 0.2)),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('INBOUND', style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                              Text(_formatBytesRate(n.inboundBps), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('OUTBOUND', style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                              Text(_formatBytesRate(n.outboundBps), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('FLOWS', style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                              Text('${n.activeFlows}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF06B6D4))),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Kernel Diagnostics & Probes ────────────────────────────────────

  Widget _buildDiagnosticsTab(ThemeData theme) {
    final stats = _stats;
    final probes = stats?.probesList ?? [];
    final ifaces = stats?.interfaces ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kernel & BPF Capabilities Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.security, color: Color(0xFF06B6D4), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Kernel Subsystem & eBPF Capabilities',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildDetailRow('Host OS / Kernel', stats?.kernelVersion ?? 'Unknown', theme),
                      _buildDetailRow('Operational Mode', (stats?.mode ?? 'kernel').toUpperCase(), theme),
                      _buildDetailRow('Total Probes', '${stats?.activeProbes ?? 0}', theme),
                      _buildDetailRow('Dropped Packets', '${stats?.droppedPackets ?? 0}', theme),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Active eBPF Probes / Tracepoints
          Text(
            'Active Probes & Tracing Attach Points',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: probes.map((p) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    Text(
                      p,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Protocol Breakdown Cards
          if (stats != null && stats.protocolCounts.isNotEmpty) ...[
            Text(
              'Protocol Distribution (Recent 30s)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: stats.protocolCounts.entries.map((entry) {
                final protoColor = _getProtocolColor(entry.key);
                return Expanded(
                  child: Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(right: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: protoColor),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'captured flows',
                            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Network Devices Table
          if (ifaces.isNotEmpty) ...[
            Text(
              'Host Network Interfaces (/proc/net/dev)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
              ),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('INTERFACE')),
                  DataColumn(label: Text('RX BYTES')),
                  DataColumn(label: Text('TX BYTES')),
                  DataColumn(label: Text('RX PACKETS')),
                  DataColumn(label: Text('TX PACKETS')),
                  DataColumn(label: Text('PACKET DROPS')),
                ],
                rows: ifaces.map((i) {
                  return DataRow(cells: [
                    DataCell(Text(i.name, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
                    DataCell(Text(_formatBytes(i.rxBytes), style: const TextStyle(fontFamily: 'monospace'))),
                    DataCell(Text(_formatBytes(i.txBytes), style: const TextStyle(fontFamily: 'monospace'))),
                    DataCell(Text('${i.rxPackets}', style: const TextStyle(fontFamily: 'monospace'))),
                    DataCell(Text('${i.txPackets}', style: const TextStyle(fontFamily: 'monospace'))),
                    DataCell(Text('${i.rxDrops + i.txDrops}', style: const TextStyle(fontFamily: 'monospace'))),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Simulation Launcher Quick Card
          Card(
            elevation: 0,
            color: const Color(0xFF06B6D4).withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFF06B6D4), size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'On-Demand eBPF Flow Generator & Test Suite',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Generate real-time synthetic traffic across cluster services to benchmark latency, test SLO multi-window alerts, or simulate upstream 502/504 faults.',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: _openSimulationDialog,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Open Simulator'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.black,
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

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
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

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Color _getProtocolColor(String proto) {
    switch (proto.toUpperCase()) {
      case 'HTTP':
        return Colors.blueAccent;
      case 'GRPC':
        return Colors.purpleAccent;
      case 'DNS':
        return Colors.greenAccent;
      case 'REDIS':
        return Colors.orangeAccent;
      case 'POSTGRES':
        return Colors.tealAccent;
      case 'TCP':
        return const Color(0xFF06B6D4);
      case 'UDP':
        return Colors.amberAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  String _formatBytesRate(double bps) {
    if (bps >= 1024 * 1024) {
      return "${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s";
    } else if (bps >= 1024) {
      return "${(bps / 1024).toStringAsFixed(1)} KB/s";
    }
    return "${bps.toStringAsFixed(0)} B/s";
  }

  String _formatBytes(int b) {
    if (b >= 1024 * 1024 * 1024) {
      return "${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
    } else if (b >= 1024 * 1024) {
      return "${(b / (1024 * 1024)).toStringAsFixed(1)} MB";
    } else if (b >= 1024) {
      return "${(b / 1024).toStringAsFixed(1)} KB";
    }
    return "$b B";
  }
}

// ── Flow Details Dialog ─────────────────────────────────────────────────────

class _FlowDetailsDialog extends StatelessWidget {
  final EbpfFlow flow;

  const _FlowDetailsDialog({required this.flow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.grain, color: Color(0xFF06B6D4), size: 20),
          const SizedBox(width: 8),
          Text('eBPF Captured Flow Telemetry', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRow('Flow ID', flow.id, theme, copyable: true),
              _buildRow('Timestamp', flow.timestamp.toIso8601String(), theme),
              _buildRow('Protocol', flow.protocol, theme),
              _buildRow('Status', '${flow.status.toUpperCase()} (${flow.statusCode})', theme),
              _buildRow('Source Endpoint', '${flow.sourceName} (${flow.sourceIp}:${flow.sourcePort})', theme),
              _buildRow('Destination Endpoint', '${flow.destName} (${flow.destIp}:${flow.destPort})', theme),
              if (flow.path.isNotEmpty) _buildRow('Path / Method', '${flow.method} ${flow.path}', theme),
              _buildRow('Latency (RTT)', '${flow.latencyMs.toStringAsFixed(2)} ms', theme),
              _buildRow('Bytes Sent / Recv', '${flow.bytesSent} B / ${flow.bytesReceived} B', theme),
              _buildRow('Throughput Rate', '${(flow.throughputBps / 1024).toStringAsFixed(2)} KB/s', theme),
              _buildRow('Retransmits / Drops', '${flow.retransmits} / ${flow.drops}', theme),
            ],
          ),
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

  Widget _buildRow(String label, String value, ThemeData theme, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                if (copyable)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Simulation Dialog ───────────────────────────────────────────────────────

class _SimulationDialog extends StatefulWidget {
  final Function(String pattern, int rate, int duration, double errors) onSimulate;

  const _SimulationDialog({required this.onSimulate});

  @override
  State<_SimulationDialog> createState() => _SimulationDialogState();
}

class _SimulationDialogState extends State<_SimulationDialog> {
  String _pattern = 'burst';
  int _rate = 15;
  int _duration = 10;
  double _errors = 0.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.bolt, color: Color(0xFF06B6D4)),
          SizedBox(width: 8),
          Text('Trigger eBPF Traffic Simulation'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inject simulated traffic flows across discovered cluster containers to evaluate live graphs, test filters, or trigger SLO error budget burns.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Pattern Selector
            DropdownButtonFormField<String>(
              value: _pattern,
              decoration: const InputDecoration(labelText: 'Traffic Pattern', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal Web Traffic (200 OK)')),
                DropdownMenuItem(value: 'burst', child: Text('Burst Spike (High Rate)')),
                DropdownMenuItem(value: 'errors', child: Text('Fault Injection (500/502 Errors)')),
                DropdownMenuItem(value: 'mixed', child: Text('Mixed Microservices')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _pattern = val);
              },
            ),
            const SizedBox(height: 14),

            // Rate Slider
            Text('Rate: $_rate events/sec', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Slider(
              value: _rate.toDouble(),
              min: 2,
              max: 50,
              divisions: 24,
              activeColor: const Color(0xFF06B6D4),
              onChanged: (val) => setState(() => _rate = val.toInt()),
            ),

            // Duration Slider
            Text('Duration: $_duration seconds', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Slider(
              value: _duration.toDouble(),
              min: 3,
              max: 60,
              divisions: 19,
              activeColor: const Color(0xFF06B6D4),
              onChanged: (val) => setState(() => _duration = val.toInt()),
            ),

            // Error Injection Slider
            Text('Error Percentage: ${_errors.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Slider(
              value: _errors,
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: Colors.redAccent,
              onChanged: (val) => setState(() => _errors = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onSimulate(_pattern, _rate, _duration, _errors);
          },
          icon: const Icon(Icons.bolt, size: 16),
          label: const Text('Start Simulation'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF06B6D4), foregroundColor: Colors.black),
        ),
      ],
    );
  }
}
