import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

/// SLO & Error Budgets Page — displays Sloth SLO metrics, error budget remaining, and burn rates.
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

class _SloPageState extends State<SloPage> {
  List<SLOItem> _slos = [];
  bool _loading = true;
  String? _error;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadSLOs();
  }

  Future<void> _loadSLOs() async {
    try {
      final list = await ApiService.fetchSLOs();
      if (mounted) {
        setState(() {
          _slos = list;
          _loading = false;
          _error = null;
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
      _loadSLOs();
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
                    'SLO & Error Budgets',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Google SRE Multi-Burn-Rate Sloth Engine Metrics & Alerts',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _loadSLOs,
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
          const SizedBox(height: 24),
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
                      child: Text('Error loading SLOs: $_error',
                          style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _buildSummaryCards(theme),
            const SizedBox(height: 24),
            if (_slos.isEmpty)
              Card(
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
              )
            else
              ListView.separated(
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
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
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
              ),
          ],
        ],
      ),
    );
  }
}
