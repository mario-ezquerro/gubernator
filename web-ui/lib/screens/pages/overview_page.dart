import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';

/// Overview page — shows stats row + stacks/nodes side by side (compact).
class OverviewPage extends StatelessWidget {
  final DashboardState state;
  final VoidCallback onRefresh;
  // Callbacks to navigate to detail pages
  final VoidCallback onViewLegions;
  final VoidCallback onViewCenturions;
  final VoidCallback onViewTasks;

  const OverviewPage({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onViewLegions,
    required this.onViewCenturions,
    required this.onViewTasks,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = state.tasks.where((t) => t.status == 'running').length;
    final activeNodes = state.nodes.where((n) => n.status == 'active' || n.status == 'ready').length;

    return Align(
      alignment: Alignment.topLeft,
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // ─── Stats Cards ───────────────────────────────
            _buildStatsRow(theme, running, activeNodes),
            const SizedBox(height: 24),

            // ─── Quick Links Row ───────────────────────────
            _buildQuickLinksRow(theme),
            const SizedBox(height: 24),

            // ─── Stacks + Nodes Overview ───────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 700) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      _buildStacksSummaryCard(theme),
                      const SizedBox(height: 16),
                      _buildNodesSummaryCard(theme),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Expanded(child: _buildStacksSummaryCard(theme)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _buildNodesSummaryCard(theme)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildStatsRow(ThemeData theme, int running, int activeNodes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final cards = [
          _AnimatedStatCard(
            label: 'Nodes',
            value: '${state.nodes.length}',
            subtitle: '$activeNodes active',
            icon: Icons.dns,
            color: const Color(0xFF3B82F6),
          ),
          _AnimatedStatCard(
            label: 'Stacks',
            value: '${state.stacks.length}',
            icon: Icons.layers,
            color: const Color(0xFF8B5CF6),
          ),
          _AnimatedStatCard(
            label: 'Services',
            value: '${state.services.length}',
            icon: Icons.miscellaneous_services,
            color: const Color(0xFF06B6D4),
          ),
          _AnimatedStatCard(
            label: 'Tasks',
            value: '${state.tasks.length}',
            icon: Icons.task,
            color: const Color(0xFFF97316),
          ),
          _AnimatedStatCard(
            label: 'Running',
            value: '$running',
            icon: Icons.play_circle,
            color: const Color(0xFF10B981),
            isHighlight: true,
          ),
        ];

        if (isWide) {
          return Row(
            children: cards.map((c) => Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: c,
            ))).toList(),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cards
              .map((c) => SizedBox(width: constraints.maxWidth / 2 - 8, child: c))
              .toList(),
        );
      },
    );
  }

  Widget _buildQuickLinksRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _QuickLinkCard(
            icon: Icons.layers,
            label: 'Legions',
            count: state.stacks.length,
            color: const Color(0xFF8B5CF6),
            onTap: onViewLegions,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickLinkCard(
            icon: Icons.dns,
            label: 'Centurions',
            count: state.nodes.length,
            color: const Color(0xFF3B82F6),
            onTap: onViewCenturions,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickLinkCard(
            icon: Icons.view_in_ar,
            label: 'Tasks',
            count: state.tasks.length,
            color: const Color(0xFFF97316),
            onTap: onViewTasks,
          ),
        ),
      ],
    );
  }

  Widget _buildStacksSummaryCard(ThemeData theme) {
    final recentStacks = state.stacks.take(5).toList();

    return Card(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.layers, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Recent Legions',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: onViewLegions,
                    child: const Text('View All →'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (recentStacks.isEmpty)
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.layers_clear, size: 36,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                        const SizedBox(height: 8),
                        Text('No stacks deployed',
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                      ],
                    ),
                  ),
                )
              else
                ...recentStacks.map((s) {
                  final taskCount = state.tasks.where((t) {
                    final svc = state.services.where((sv) => sv.id == t.serviceId).firstOrNull;
                    return svc?.stackId == s.id;
                  }).length;
                  final runningCount = state.tasks.where((t) {
                    final svc = state.services.where((sv) => sv.id == t.serviceId).firstOrNull;
                    return svc?.stackId == s.id && t.status == 'running';
                  }).length;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.layers_outlined, size: 16,
                              color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(s.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: runningCount == taskCount
                                  ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                  : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$runningCount/$taskCount',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: runningCount == taskCount
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodesSummaryCard(ThemeData theme) {
    return Card(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.dns, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Centurions',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: onViewCenturions,
                    child: const Text('View All →'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (state.nodes.isEmpty)
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dns, size: 36,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                        const SizedBox(height: 8),
                        Text('No nodes registered',
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                      ],
                    ),
                  ),
                )
            else
              ...state.nodes.map((n) {
                final nodeTaskCount = state.tasks.where((t) => t.nodeId == n.id).length;
                final nodeRunningCount = state.tasks.where((t) => t.nodeId == n.id && t.status == 'running').length;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Pulsating status dot
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: n.status == 'active' || n.status == 'ready'
                                ? const Color(0xFF10B981)
                                : n.status == 'down'
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFFF59E0B),
                            boxShadow: (n.status == 'active' || n.status == 'ready')
                                ? [BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                    blurRadius: 6,
                                  )]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // ID + IP Column
                        SizedBox(
                          width: 120,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.id,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                              Text(n.ip,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                    fontFamily: 'Courier New',
                                  )),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        StatusBadge(label: n.role),
                        const SizedBox(width: 6),
                        StatusBadge(label: n.status),
                        const SizedBox(width: 10),

                        // Inline CPU Thermometer Bar
                        Expanded(
                          child: _buildInlineThermometer('CPU', '${n.cpuPercent.toStringAsFixed(1)}%', n.cpuPercent, const Color(0xFF3B82F6), theme),
                        ),
                        const SizedBox(width: 10),

                        // Inline RAM Thermometer Bar
                        Expanded(
                          flex: 2,
                          child: _buildInlineThermometer('RAM', '${_formatBytes(n.memUsedBytes)}/${_formatBytes(n.memTotalBytes)} (${n.memPercent.toStringAsFixed(0)}%)', n.memPercent, const Color(0xFF10B981), theme),
                        ),
                        const SizedBox(width: 10),

                        // Inline Network Speed Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.swap_vert, size: 12, color: Color(0xFF8B5CF6)),
                              const SizedBox(width: 2),
                              Text(
                                _formatNetSpeed(n.netBps),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Tasks Count Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$nodeRunningCount/$nodeTaskCount tasks',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildInlineThermometer(String label, String valueText, double percent, Color defaultColor, ThemeData theme) {
    final color = percent > 90 ? Colors.red : (percent > 75 ? Colors.orange : defaultColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            Text(valueText, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatNetSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    const suffixes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    int i = 0;
    double speed = bytesPerSec;
    while (speed >= 1024 && i < suffixes.length - 1) {
      speed /= 1024;
      i++;
    }
    return '${speed.toStringAsFixed(1)} ${suffixes[i]}';
  }
}

/// Animated stat card with hover effect and accent color.
class _AnimatedStatCard extends StatefulWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool isHighlight;

  const _AnimatedStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.isHighlight = false,
  });

  @override
  State<_AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends State<_AnimatedStatCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: _hovering
            ? (Matrix4.identity()..translate(0.0, -2.0))
            : Matrix4.identity(),
        child: Card(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: _hovering
                  ? Border.all(color: widget.color.withValues(alpha: 0.3), width: 1)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(widget.icon, size: 18, color: widget.color),
                    ),
                    const Spacer(),
                    if (widget.isHighlight)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.color,
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(widget.value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: widget.isHighlight ? widget.color : theme.colorScheme.onSurface,
                    )),
                const SizedBox(height: 4),
                Text(widget.label,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    )),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.subtitle!,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        fontSize: 11,
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick link card for navigating to sections.
class _QuickLinkCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _QuickLinkCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  State<_QuickLinkCard> createState() => _QuickLinkCardState();
}

class _QuickLinkCardState extends State<_QuickLinkCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovering
                ? widget.color.withValues(alpha: 0.08)
                : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovering
                  ? widget.color.withValues(alpha: 0.3)
                  : theme.dividerColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, size: 20, color: widget.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('${widget.count} total',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        )),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
