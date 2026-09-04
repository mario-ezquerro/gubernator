import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../../widgets/sre_profiles_dialog.dart';

/// Grafana metrics page — embeds the Grafana dashboard with toolbar controls and direct links.
class GrafanaPage extends StatelessWidget {
  const GrafanaPage({super.key});

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
                  color: const Color(0xFFF97316).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.analytics, color: Color(0xFFF97316), size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Cluster Monitoring',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'GRAFANA LIVE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_motion, size: 12, color: Color(0xFFF97316)),
                            SizedBox(width: 4),
                            Text(
                              'ARQUITECTURA SRE',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFF97316)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Real-time metrics for CPU, RAM, disk, and container health powered by Prometheus.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const SreProfilesDialog(),
                  );
                },
                icon: const Icon(Icons.auto_awesome_motion, size: 16),
                label: const Text(
                  'Perfiles SRE / Presets',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  html.window.open('/grafana/d/gubernator/gubernator-cluster-overview?orgId=1', '_blank');
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Grafana (Proxy)'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  html.window.open('http://$host:3000/grafana/', '_blank');
                },
                icon: const Icon(Icons.launch, size: 16),
                label: const Text('Direct Port :3000'),
              ),
            ],
          ),
        ),

        // IFrame View
        const Expanded(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: HtmlElementView(viewType: 'grafana-iframe'),
            ),
          ),
        ),
      ],
    );
  }
}
