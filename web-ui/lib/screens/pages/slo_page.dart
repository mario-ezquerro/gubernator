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

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _slos.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 16),
      itemBuilder: (ctx, idx) {
        final item = _slos[idx];
        final budgetColor = _getBudgetColor(item.errorBudgetRemaining);

        return Card(
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
                      Chip(
                        avatar: const Icon(Icons.dashboard_customize, size: 14),
                        label: Text(item.template, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                    if (item.journey.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Chip(
                        avatar: const Icon(Icons.route, size: 14),
                        label: Text(item.journey, style: const TextStyle(fontSize: 11)),
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        visualDensity: VisualDensity.compact,
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
        );
      },
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
                    'Google SRE Multi-Burn-Rate Sloth Engine & Prometheus Integration',
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
                label: const Text('Sync Prometheus Rules'),
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
