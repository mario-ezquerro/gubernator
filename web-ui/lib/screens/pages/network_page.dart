import 'dart:html' as html;
import 'package:flutter/material.dart';

/// Network monitoring page — embeds the Grafana Network Monitor iframe with toolbar controls.
class NetworkPage extends StatelessWidget {
  const NetworkPage({super.key});

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
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.network_check, color: Color(0xFF06B6D4), size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Network Bandwidth & Traffic Monitor',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NETWORK LIVE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF06B6D4)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cluster-wide rx/tx transfer rates, container bandwidth, and interface packet statistics.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  html.window.open('/grafana/d/gubernator-network/gubernator-network-monitor?orgId=1', '_blank');
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open in Tab (Proxy)'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  html.window.open('http://$host:3000/grafana/d/gubernator-network/gubernator-network-monitor?orgId=1', '_blank');
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
              child: HtmlElementView(viewType: 'grafana-network-iframe'),
            ),
          ),
        ),
      ],
    );
  }
}
