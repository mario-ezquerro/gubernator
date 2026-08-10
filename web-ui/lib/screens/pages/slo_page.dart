import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

/// Advanced SLO & Error Budgets Suite (5 Tabs)
class SloPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;

  const SloPage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<SloPage> createState() => _SloPageState();
}

class _SloPageState extends State<SloPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<SLOItem> _slos = [];
  List<UserJourney> _journeys = [];
  List<SLOCorrelationEvent> _correlations = [];
  List<SLOValidationItem> _validations = [];

  bool _loading = true;
  String? _error;
  bool _syncing = false;
  bool _validating = false;

  String _searchQuery = '';
  String _sortBy = 'lowest_budget'; // lowest_budget, highest_burn, name, target
  bool _isTableView = false;

  final TextEditingController _composeController = TextEditingController(
    text: '''version: "3.8"
name: checkout-stack

services:
  payment-api:
    image: hashicorp/http-echo:latest
    ports:
      - "8080:8080"
    labels:
      gbnt.slo.enable: "true"
      gbnt.slo.target: "99.9"
      gbnt.slo.window: "30d"
      gbnt.slo.template: "caddy-http"
      gbnt.slo.journey: "Checkout Flow"
''',
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _composeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slosFuture = ApiService.fetchSLOs();
      final journeysFuture = ApiService.fetchUserJourneys();
      final correlationsFuture = ApiService.fetchSLOCorrelations();

      final results = await Future.wait([slosFuture, journeysFuture, correlationsFuture]);

      if (mounted) {
        setState(() {
          _slos = results[0] as List<SLOItem>;
          _journeys = results[1] as List<UserJourney>;
          _correlations = results[2] as List<SLOCorrelationEvent>;
          _loading = false;
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

  Future<void> _syncSLOs() async {
    setState(() => _syncing = true);
    final ok = await ApiService.syncSLOs();
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'SLO rules synchronized with Prometheus.' : 'Failed to sync SLO rules.'),
          backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
        ),
      );
      _loadData();
    }
  }

  Future<void> _runBacktest() async {
    if (_composeController.text.trim().isEmpty) return;
    setState(() => _validating = true);
    try {
      final res = await ApiService.validateSLO(_composeController.text);
      if (mounted) {
        setState(() {
          _validations = res;
          _validating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _validating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backtest error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Color _getBudgetColor(double budgetRemaining) {
    if (budgetRemaining <= 0) return Colors.red;
    if (budgetRemaining < 20) return Colors.amber.shade800;
    if (budgetRemaining < 50) return Colors.amber.shade600;
    return Colors.green.shade600;
  }

  List<SLOItem> _getFilteredAndSortedSLOs() {
    List<SLOItem> list = _slos.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.serviceName.toLowerCase().contains(q) ||
          s.template.toLowerCase().contains(q) ||
          s.journey.toLowerCase().contains(q) ||
          s.errorQuery.toLowerCase().contains(q);
    }).toList();

    list.sort((a, b) {
      switch (_sortBy) {
        case 'lowest_budget':
          return a.errorBudgetRemaining.compareTo(b.errorBudgetRemaining);
        case 'highest_burn':
          return b.burnRate.compareTo(a.burnRate);
        case 'name':
          return a.serviceName.compareTo(b.serviceName);
        case 'target':
          return b.target.compareTo(a.target);
        default:
          return a.errorBudgetRemaining.compareTo(b.errorBudgetRemaining);
      }
    });

    return list;
  }

  void _showSLODetailModal(SLOItem item) {
    showDialog(
      context: context,
      builder: (ctx) => _SLODetailDialog(item: item),
    );
  }

  Widget _buildSummaryCards(ThemeData theme) {
    final total = _slos.length;
    final healthy = _slos.where((s) => s.status == 'healthy').length;
    final warning = _slos.where((s) => s.status == 'warning').length;
    final exhausted = _slos.where((s) => s.status == 'exhausted').length;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'TOTAL SLOs',
            value: '$total',
            icon: Icons.speed,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StatCard(
            label: 'HEALTHY',
            value: '$healthy',
            icon: Icons.check_circle,
            valueColor: Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StatCard(
            label: 'WARNING',
            value: '$warning',
            icon: Icons.warning,
            valueColor: Colors.amber.shade800,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StatCard(
            label: 'EXHAUSTED',
            value: '$exhausted',
            icon: Icons.error,
            valueColor: Colors.red,
          ),
        ),
      ],
    );
  }

  // TAB 1: Overview & Error Budgets
  Widget _buildTabOverview(ThemeData theme) {
    final filteredSLOs = _getFilteredAndSortedSLOs();

    if (_slos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.query_stats, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                const SizedBox(height: 16),
                Text(
                  'No Active SLOs Configured',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add "gbnt.slo.target=99.9" and "gbnt.slo.window=30d" labels to your Compose services to track error budgets.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controls Bar: Search, Sort, View Toggle
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Search by service, template, or journey...',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.sort, size: 18),
                  items: const [
                    DropdownMenuItem(value: 'lowest_budget', child: Text('Sort: Lowest Budget')),
                    DropdownMenuItem(value: 'highest_burn', child: Text('Sort: Highest Burn')),
                    DropdownMenuItem(value: 'name', child: Text('Sort: Name (A-Z)')),
                    DropdownMenuItem(value: 'target', child: Text('Sort: Target %')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _sortBy = val);
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: _isTableView ? 'Switch to Cards View' : 'Switch to Data Table View',
                  icon: Icon(_isTableView ? Icons.grid_view : Icons.table_rows),
                  onPressed: () => setState(() => _isTableView = !_isTableView),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (filteredSLOs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No SLOs match your search filter.')),
          )
        else if (_isTableView)
          // Data Table View
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Service')),
                  DataColumn(label: Text('Target')),
                  DataColumn(label: Text('Budget Remaining')),
                  DataColumn(label: Text('Burn Rate')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: filteredSLOs.map((item) {
                  final budgetColor = _getBudgetColor(item.errorBudgetRemaining);
                  return DataRow(
                    onSelectChanged: (_) => _showSLODetailModal(item),
                    cells: [
                      DataCell(
                        Row(
                          children: [
                            Text(item.serviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (item.template.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _searchQuery = item.template),
                                child: Chip(
                                  label: Text(item.template, style: const TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      DataCell(Text('${item.target}% (${item.window})')),
                      DataCell(
                        Text('${item.errorBudgetRemaining.toStringAsFixed(2)}%',
                            style: TextStyle(fontWeight: FontWeight.bold, color: budgetColor)),
                      ),
                      DataCell(
                        Text('${item.burnRate.toStringAsFixed(2)}x',
                            style: TextStyle(
                              color: item.burnRate > 1.0 ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                      DataCell(StatusBadge(label: item.status)),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.analytics, size: 18),
                          onPressed: () => _showSLODetailModal(item),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          )
        else
          // Cards View
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredSLOs.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 16),
            itemBuilder: (ctx, idx) {
              final item = filteredSLOs[idx];
              final budgetColor = _getBudgetColor(item.errorBudgetRemaining);

              return Card(
                child: InkWell(
                  onTap: () => _showSLODetailModal(item),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.api, size: 24, color: theme.colorScheme.primary),
                            const SizedBox(width: 10),
                            Text(
                              item.serviceName,
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            Chip(
                              label: Text('${item.target}% Target (${item.window})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              backgroundColor: theme.colorScheme.secondaryContainer,
                              visualDensity: VisualDensity.compact,
                            ),
                            if (item.template.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _searchQuery = item.template),
                                child: Chip(
                                  avatar: const Icon(Icons.dashboard_customize, size: 14),
                                  label: Text(item.template, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  backgroundColor: theme.colorScheme.tertiaryContainer,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                            if (item.journey.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _searchQuery = item.journey),
                                child: Chip(
                                  avatar: const Icon(Icons.route, size: 14),
                                  label: Text(item.journey, style: const TextStyle(fontSize: 11)),
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Chip(
                              label: Text('${item.burnRate.toStringAsFixed(2)}x Burn Rate',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: item.burnRate > 1.0 ? Colors.red : Colors.green,
                                  )),
                              backgroundColor: (item.burnRate > 1.0 ? Colors.red : Colors.green).withValues(alpha: 0.1),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            StatusBadge(label: item.status),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              'Error Budget Remaining: ',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${item.errorBudgetRemaining.toStringAsFixed(2)}%',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: budgetColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (item.errorBudgetRemaining / 100.0).clamp(0.0, 1.0),
                            minHeight: 12,
                            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                            color: budgetColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('SLI Queries', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                          children: [
                            if (item.errorQuery.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Error Query: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    Expanded(
                                      child: SelectableText(
                                        item.errorQuery,
                                        style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, color: Colors.redAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (item.totalQuery.isNotEmpty)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Total Query: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Expanded(
                                    child: SelectableText(
                                      item.totalQuery,
                                      style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, color: Colors.blueAccent),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // TAB 2: User Journeys (Composite SLOs)
  Widget _buildTabJourneys(ThemeData theme) {
    if (_journeys.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Text(
              'No User Journeys Defined\nAdd label "gbnt.slo.journey=My Journey Name" to Compose services to aggregate composite SLOs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _journeys.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 16),
      itemBuilder: (ctx, idx) {
        final j = _journeys[idx];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.route, size: 24, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(j.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Chip(
                      label: Text('${j.compositeTarget.toStringAsFixed(2)}% Avg Target',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    ),
                    const Spacer(),
                    StatusBadge(label: j.status),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Average Error Budget', style: theme.textTheme.bodySmall),
                          Text('${j.avgErrorBudget.toStringAsFixed(2)}%',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _getBudgetColor(j.avgErrorBudget),
                              )),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bottleneck Service', style: theme.textTheme.bodySmall),
                          Text('${j.bottleneckService} (${j.bottleneckBudget.toStringAsFixed(2)}% Budget)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.orangeAccent,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Services in Journey:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: j.services
                      .map((s) => Chip(
                            avatar: Icon(Icons.api, size: 14, color: _getBudgetColor(s.errorBudgetRemaining)),
                            label: Text('${s.serviceName} (${s.errorBudgetRemaining.toStringAsFixed(1)}%)'),
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // TAB 3: Deployment Events Correlation
  Widget _buildTabCorrelation(ThemeData theme) {
    if (_correlations.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Text(
              'No recent stack deployment events recorded.',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SLO Burn Rate vs Deployment Correlation Timeline',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Cross-references stack updates and restarts with service burn rates',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 20),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _correlations.length,
              separatorBuilder: (ctx, idx) => const Divider(),
              itemBuilder: (ctx, idx) {
                final ev = _correlations[idx];
                final isSpike = ev.burnRate > 1.0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSpike ? Colors.red.withValues(alpha: 0.2) : theme.colorScheme.primaryContainer,
                    child: Icon(
                      isSpike ? Icons.warning_amber : Icons.rocket_launch,
                      color: isSpike ? Colors.red : theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  title: Text('${ev.stackName} / ${ev.serviceName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${ev.description} • ${ev.timestamp}'),
                  trailing: Chip(
                    label: Text('Burn Rate: ${ev.burnRate.toStringAsFixed(2)}x',
                        style: TextStyle(
                          color: isSpike ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        )),
                    backgroundColor: (isSpike ? Colors.red : Colors.green).withValues(alpha: 0.1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // TAB 4: SLI Templates & PromQL Generator
  Widget _buildTabTemplates(ThemeData theme) {
    final templates = [
      {
        'id': 'caddy-http',
        'title': 'Caddy HTTP Status Code Rate',
        'desc': 'Reverse proxy HTTP 5xx error rate from Caddy access metrics.',
        'error': 'sum(rate(caddy_http_response_status_code_total{status=~"5.."}[{{.window}}]))',
        'total': 'sum(rate(caddy_http_response_status_code_total[{{.window}}]))',
        'label': 'gbnt.slo.template: "caddy-http"',
      },
      {
        'id': 'http-status',
        'title': 'Generic HTTP Container Status',
        'desc': 'Application container HTTP 5xx error rate.',
        'error': 'sum(rate(http_requests_total{status=~"5.."}[{{.window}}]))',
        'total': 'sum(rate(http_requests_total[{{.window}}]))',
        'label': 'gbnt.slo.template: "http-status"',
      },
      {
        'id': 'latency-p99',
        'title': 'P99 Latency Histogram',
        'desc': 'Proportion of requests completed in under 500ms.',
        'error': 'sum(rate(http_request_duration_seconds_bucket{le="0.5"}[{{.window}}]))',
        'total': 'sum(rate(http_request_duration_seconds_count[{{.window}}]))',
        'label': 'gbnt.slo.template: "latency-p99"',
      },
      {
        'id': 'grpc',
        'title': 'gRPC Server Handled Errors',
        'desc': 'gRPC error codes (Internal, Unavailable, DataLoss).',
        'error': 'sum(rate(grpc_server_handled_total{grpc_code=~"Unknown|Internal|Unavailable|DataLoss"}[{{.window}}]))',
        'total': 'sum(rate(grpc_server_handled_total[{{.window}}]))',
        'label': 'gbnt.slo.template: "grpc"',
      },
    ];

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: templates.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 16),
      itemBuilder: (ctx, idx) {
        final tmpl = templates[idx]!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dashboard_customize, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(tmpl['title']!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Chip(
                      label: Text(tmpl['label']!, style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, fontWeight: FontWeight.bold)),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(tmpl['desc']!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('Error Query: ${tmpl['error']}',
                          style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, color: Colors.redAccent)),
                      const SizedBox(height: 4),
                      SelectableText('Total Query: ${tmpl['total']}',
                          style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, color: Colors.blueAccent)),
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

  // TAB 5: Backtest & Dry-Run Validator
  Widget _buildTabBacktest(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backtest & Validate Compose SLO Labels',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Paste your docker-compose.yml to dry-run PromQL queries and validate SLO configuration.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 16),
                TextField(
                  controller: _composeController,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _validating ? null : _runBacktest,
                  icon: _validating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.science),
                  label: const Text('Run SLO Backtest & Syntax Validation'),
                ),
              ],
            ),
          ),
        ),
        if (_validations.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Backtest & Validation Results', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _validations.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final v = _validations[idx];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        v.valid ? Icons.check_circle : Icons.error,
                        color: v.valid ? Colors.green : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.serviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              v.valid ? 'Target: ${v.target}% (${v.window}) • Template: ${v.template.isEmpty ? 'Custom' : v.template}' : v.error,
                              style: TextStyle(color: v.valid ? theme.colorScheme.onSurface.withValues(alpha: 0.7) : Colors.red),
                            ),
                            const SizedBox(height: 4),
                            Text('Backtest: ${v.backtestDetails}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(v.backtestStatus.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        backgroundColor: v.backtestStatus == 'passed'
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.amber.withValues(alpha: 0.15),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
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
              Icon(Icons.speed, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SLO & Error Budgets Suite',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Google SRE Multi-Burn-Rate Sloth Engine & Pyrra Interactive Suite',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _syncing ? null : _syncSLOs,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync, size: 18),
                label: const Text('Sync Prometheus & Grafana'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSummaryCards(theme),
          const SizedBox(height: 20),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.speed, size: 18), text: 'Overview & Budgets'),
              Tab(icon: Icon(Icons.route, size: 18), text: 'User Journeys'),
              Tab(icon: Icon(Icons.timeline, size: 18), text: 'Deployment Correlation'),
              Tab(icon: Icon(Icons.dashboard_customize, size: 18), text: 'SLI Templates'),
              Tab(icon: Icon(Icons.science, size: 18), text: 'Backtest & Validator'),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Error loading SLO suite: $_error', style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ],
                ),
              ),
            )
          else
            AnimatedBuilder(
              animation: _tabController,
              builder: (ctx, child) {
                switch (_tabController.index) {
                  case 0:
                    return _buildTabOverview(theme);
                  case 1:
                    return _buildTabJourneys(theme);
                  case 2:
                    return _buildTabCorrelation(theme);
                  case 3:
                    return _buildTabTemplates(theme);
                  case 4:
                    return _buildTabBacktest(theme);
                  default:
                    return _buildTabOverview(theme);
                }
              },
            ),
        ],
      ),
    );
  }
}

// SLO Detail Modal Dialog
class _SLODetailDialog extends StatefulWidget {
  final SLOItem item;

  const _SLODetailDialog({required this.item});

  @override
  State<_SLODetailDialog> createState() => _SLODetailDialogState();
}

class _SLODetailDialogState extends State<_SLODetailDialog> {
  String _selectedRange = '24h';
  List<SLOHistoryPoint> _history = [];
  SLOREDMetrics? _redMetrics;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetailData();
  }

  Future<void> _fetchDetailData() async {
    setState(() => _loading = true);
    try {
      final historyFuture = ApiService.fetchSLOHistory(widget.item.serviceId, _selectedRange);
      final redFuture = ApiService.fetchSLOREDMetrics(widget.item.serviceId);

      final results = await Future.wait([historyFuture, redFuture]);

      if (mounted) {
        setState(() {
          _history = results[0] as List<SLOHistoryPoint>;
          _redMetrics = results[1] as SLOREDMetrics;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    final double currentAvail = 100.0 - (100.0 - item.target) * (item.burnRate > 0 ? item.burnRate : 1.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text('${item.serviceName} — SLO Deep Dive',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 20),

            // Big 3 Highlight Numbers
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('TARGET OBJECTIVE', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('${item.target}%', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text('Window: ${item.window}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('EST. AVAILABILITY', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('${currentAvail.toStringAsFixed(2)}%',
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text('Burn Rate: ${item.burnRate.toStringAsFixed(2)}x', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    color: theme.colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('BUDGET REMAINING', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('${item.errorBudgetRemaining.toStringAsFixed(2)}%',
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text('Status: ${item.status}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Range Selector & Trend Chart
            Row(
              children: [
                Text('Error Budget Trend Chart', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '1h', label: Text('1h')),
                    ButtonSegment(value: '6h', label: Text('6h')),
                    ButtonSegment(value: '24h', label: Text('24h')),
                    ButtonSegment(value: '7d', label: Text('7d')),
                    ButtonSegment(value: '30d', label: Text('30d')),
                  ],
                  selected: {_selectedRange},
                  onSelectionChanged: (set) {
                    setState(() => _selectedRange = set.first);
                    _fetchDetailData();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 180,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomPaint(
                      painter: _SLOTrendChartPainter(history: _history, theme: theme),
                    ),
            ),
            const SizedBox(height: 20),

            // RED Metrics Cards
            Text('RED Metrics (Request Rate, Error Rate, P99 Duration)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildREDCard('Requests / sec', '${(_redMetrics?.rps ?? 0).toStringAsFixed(1)} RPS', Icons.speed, Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildREDCard('Error Rate (5xx)', '${(_redMetrics?.errorRps ?? 0).toStringAsFixed(2)} RPS', Icons.error_outline, Colors.red),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildREDCard('P99 Latency', '${(_redMetrics?.p99LatencyMs ?? 0).toStringAsFixed(1)} ms', Icons.timer, Colors.amber),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildREDCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Painter for SLO Error Budget Trend Chart
class _SLOTrendChartPainter extends CustomPainter {
  final List<SLOHistoryPoint> history;
  final ThemeData theme;

  _SLOTrendChartPainter({required this.history, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintGrid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1.0;

    // Draw grid lines
    canvas.drawLine(Offset(0, size.height * 0.2), Offset(size.width, size.height * 0.2), paintGrid);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), paintGrid);
    canvas.drawLine(Offset(0, size.height * 0.8), Offset(size.width, size.height * 0.8), paintGrid);

    if (history.length < 2) {
      final textPainter = TextPainter(
        text: const TextSpan(text: 'Simulated Budget Trend: 100% Stable', style: TextStyle(color: Colors.white38, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2));
      return;
    }

    final path = Path();
    final double dx = size.width / (history.length - 1);

    for (int i = 0; i < history.length; i++) {
      final pt = history[i];
      final double y = size.height - (pt.budgetRemaining / 100.0) * size.height;
      final double x = i * dx;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant _SLOTrendChartPainter oldDelegate) => true;
}
