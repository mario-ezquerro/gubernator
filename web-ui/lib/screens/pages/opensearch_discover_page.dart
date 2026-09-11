import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../../widgets/sre_profiles_dialog.dart';

/// Embedded OpenSearch Discover & SIEM Logs Explorer Page.
/// Replaces Loki Logs when the active SRE profile is 'enterprise-elk'.
/// Displays the full native OpenSearch Discover explorer inside the Gubernator dashboard.
class OpenSearchDiscoverPage extends StatefulWidget {
  final VoidCallback? onSwitchedProfile;

  const OpenSearchDiscoverPage({super.key, this.onSwitchedProfile});

  @override
  State<OpenSearchDiscoverPage> createState() => _OpenSearchDiscoverPageState();
}

class _OpenSearchDiscoverPageState extends State<OpenSearchDiscoverPage> {
  int _selectedView = 0; // 0: All Logs Stream, 1: Error & Security Audit

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
                child: const Icon(Icons.security_update_good, color: Colors.deepOrangeAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'SIEM & Container Audit Logs',
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
                          'OPENSEARCH DISCOVER :5601',
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
                    'Explorador interactivo de logs de contenedores con sintaxis Lucene/DQL, inspección de streams y filtros de auditoría.',
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
                    icon: Icon(Icons.stream, size: 16),
                    label: Text('Live Logs Stream', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.warning_amber, size: 16),
                    label: Text('Errors & Security Audit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
                selected: {_selectedView},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedView = newSelection.first;
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
                    builder: (_) => SreProfilesDialog(
                      onProfileChanged: widget.onSwitchedProfile,
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
                  final targetUrl = _selectedView == 0
                      ? 'http://$host:5601/app/discover#/view/gubernator-all-logs'
                      : 'http://$host:5601/app/discover#/view/gubernator-error-logs';
                  html.window.open(targetUrl, '_blank');
                },
                icon: const Icon(Icons.launch, size: 16),
                label: const Text('Direct Port :5601'),
              ),
            ],
          ),
        ),

        // IFrame View — Embeds OpenSearch Discover directly across the entire screen
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: IndexedStack(
                index: _selectedView,
                children: const [
                  HtmlElementView(viewType: 'opensearch-discover-iframe'),
                  HtmlElementView(viewType: 'opensearch-discover-errors-iframe'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
