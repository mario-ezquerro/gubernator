import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../../widgets/sre_profiles_dialog.dart';

/// OpenSearch Dashboards page — embeds OpenSearch Dashboards with segmented tabs for
/// Cluster Logs Overview, SIEM Security Audit, and Discover Explorer.
class OpenSearchDashboardsPage extends StatefulWidget {
  const OpenSearchDashboardsPage({super.key});

  @override
  State<OpenSearchDashboardsPage> createState() => _OpenSearchDashboardsPageState();
}

class _OpenSearchDashboardsPageState extends State<OpenSearchDashboardsPage> {
  int _selectedTab = 0;

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
                child: const Icon(Icons.dashboard_customize, color: Colors.deepOrangeAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'OpenSearch Dashboards & SIEM',
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
                              'ENTERPRISE SIEM',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Full-text Lucene search, enterprise security analytics, SIEM compliance dashboards, and audit logs.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              const Spacer(),

              // Segmented view selector
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.bar_chart, size: 16),
                    label: Text('Logs Overview', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.security, size: 16),
                    label: Text('SIEM Audit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    icon: Icon(Icons.travel_explore, size: 16),
                    label: Text('Discover', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedTab = newSelection.first;
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 12),

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
                    builder: (_) => const SreProfilesDialog(),
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
                  html.window.open('http://$host:5601', '_blank');
                },
                icon: const Icon(Icons.launch, size: 16),
                label: const Text('Direct Port :5601'),
              ),
            ],
          ),
        ),

        // IFrame View
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: IndexedStack(
                index: _selectedTab,
                children: const [
                  HtmlElementView(viewType: 'opensearch-iframe'),
                  HtmlElementView(viewType: 'opensearch-siem-iframe'),
                  HtmlElementView(viewType: 'opensearch-discover-iframe'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
