import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../../widgets/sre_profiles_dialog.dart';

/// Embedded OpenSearch Trace Analytics (APM) page.
/// Replaces Jaeger when the active SRE profile is 'enterprise-elk'.
/// Displays service maps, distributed spans, latency percentiles, and error traces.
class OpenSearchTracesPage extends StatelessWidget {
  final VoidCallback? onSwitchedProfile;

  const OpenSearchTracesPage({super.key, this.onSwitchedProfile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = html.window.location.hostname ?? 'localhost';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepOrangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.polyline, color: Colors.deepOrangeAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'OpenSearch Trace Analytics & APM',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.deepOrangeAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'OPENSEARCH LIVE :5601',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepOrangeAccent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.business_outlined, size: 12, color: Color(0xFF0284C7)),
                            SizedBox(width: 4),
                            Text(
                              'ENTERPRISE SIEM & APM',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rastreo distribuido de microservicios, mapa de topología de dependencias, latencias P50/P90/P99 y grupos de trazas.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              const Spacer(),

              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepOrangeAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => SreProfilesDialog(
                      onProfileChanged: onSwitchedProfile,
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome_motion, size: 16),
                label: const Text(
                  'Perfiles SRE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  html.window.open('http://$host:5601/app/observability-dashboards#/trace_analytics', '_blank');
                },
                icon: const Icon(Icons.launch, size: 16),
                label: const Text('Direct Port :5601'),
              ),
            ],
          ),
        ),

        // IFrame View — Embeds OpenSearch Trace Analytics directly across the entire screen
        const Expanded(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: HtmlElementView(viewType: 'opensearch-traces-iframe'),
            ),
          ),
        ),
      ],
    );
  }
}
