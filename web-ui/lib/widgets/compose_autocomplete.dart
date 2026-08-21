import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

class ComposeSnippet {
  final String label;
  final String category;
  final String description;
  final IconData icon;
  final String snippet;

  const ComposeSnippet({
    required this.label,
    required this.category,
    required this.description,
    required this.icon,
    required this.snippet,
  });
}

class ComposeAutocomplete {
  static const List<ComposeSnippet> snippets = [
    // Caddy Ingress
    ComposeSnippet(
      label: 'ingress.host',
      category: 'Caddy',
      description: 'Define public domain or hostname for Caddy routing',
      icon: Icons.public,
      snippet: '        - "ingress.host=app.gbnt.local"\n',
    ),
    ComposeSnippet(
      label: 'gbnt.caddy.port',
      category: 'Caddy',
      description: 'Internal container port to proxy HTTP traffic to',
      icon: Icons.alt_route,
      snippet: '        - "gbnt.caddy.port=8080"\n',
    ),
    ComposeSnippet(
      label: 'gbnt.caddy.tls',
      category: 'Caddy',
      description: 'Force internal or custom TLS certificate',
      icon: Icons.lock,
      snippet: '        - "gbnt.caddy.tls=internal"\n',
    ),

    // SLO Engine (Sloth)
    ComposeSnippet(
      label: 'gbnt.slo.target',
      category: 'SLO',
      description: 'Target availability percentage (e.g. 99.9%)',
      icon: Icons.speed,
      snippet: '        - "gbnt.slo.enable=true"\n        - "gbnt.slo.target=99.9"\n        - "gbnt.slo.window=30d"\n',
    ),
    ComposeSnippet(
      label: 'gbnt.slo.latency',
      category: 'SLO',
      description: 'Latency threshold SLO definition for Sloth',
      icon: Icons.timer,
      snippet: '        - "gbnt.slo.indicator=latency"\n        - "gbnt.slo.latency.threshold=200ms"\n',
    ),

    // Security Gatekeeper
    ComposeSnippet(
      label: 'gbnt.security.require-signature',
      category: 'Security',
      description: 'Block deployment if image lacks valid Cosign signature',
      icon: Icons.verified_user,
      snippet: '        - "gbnt.security.require-signature=true"\n',
    ),
    ComposeSnippet(
      label: 'gbnt.security.max-cve-severity',
      category: 'Security',
      description: 'Reject images with CVE vulnerabilities above threshold',
      icon: Icons.security,
      snippet: '        - "gbnt.security.max-cve-severity=critical"\n',
    ),

    // Node Placement & Labels
    ComposeSnippet(
      label: 'placement.constraints',
      category: 'Placement',
      description: 'Pin service to worker nodes or specific hostnames',
      icon: Icons.memory,
      snippet: '      placement:\n        constraints:\n          - "node.role == worker"\n',
    ),
    ComposeSnippet(
      label: 'placement.gpu',
      category: 'Placement',
      description: 'Target nodes with NVIDIA GPU hardware',
      icon: Icons.developer_board,
      snippet: '      placement:\n        constraints:\n          - "gbnt.node.gpu == nvidia"\n',
    ),

    // Storage & Granaries
    ComposeSnippet(
      label: '/var/contenedores/',
      category: 'Storage',
      description: 'Persistent shared storage mount with automated backup support',
      icon: Icons.storage,
      snippet: '      - /var/contenedores/\${STACK_NAME}/data:/data\n',
    ),

    // Core Compose
    ComposeSnippet(
      label: 'healthcheck',
      category: 'Compose',
      description: 'Container healthcheck command and interval',
      icon: Icons.favorite,
      snippet: '    healthcheck:\n      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]\n      interval: 10s\n      timeout: 5s\n      retries: 3\n',
    ),
    ComposeSnippet(
      label: 'deploy.replicas',
      category: 'Compose',
      description: 'Scale service replicas',
      icon: Icons.control_point_duplicate,
      snippet: '    deploy:\n      replicas: 2\n',
    ),
    ComposeSnippet(
      label: 'environment',
      category: 'Compose',
      description: 'Environment variables section',
      icon: Icons.tune,
      snippet: '    environment:\n      - NODE_ENV=production\n      - LOG_LEVEL=info\n',
    ),
  ];

  static void insertSnippet(CodeController controller, String snippet) {
    final text = controller.text;
    final pos = controller.selection.baseOffset;
    if (pos >= 0 && pos <= text.length) {
      controller.text = text.substring(0, pos) + snippet + text.substring(pos);
      controller.selection = TextSelection.collapsed(offset: pos + snippet.length);
    } else {
      controller.text = text + (text.endsWith('\n') ? '' : '\n') + snippet;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }
  }
}

/// Horizontal interactive suggestion bar that filters snippets based on the active word.
class ComposeSuggestionBar extends StatelessWidget {
  final CodeController controller;
  final ValueChanged<String>? onSnippetInserted;

  const ComposeSuggestionBar({
    super.key,
    required this.controller,
    this.onSnippetInserted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // Detect current word before cursor
        final pos = value.selection.baseOffset;
        String query = '';
        if (pos > 0 && pos <= value.text.length) {
          final prefix = value.text.substring(0, pos);
          final match = RegExp(r'[a-zA-Z0-9_\.\-/]+$').firstMatch(prefix);
          if (match != null) {
            query = match.group(0)?.toLowerCase() ?? '';
          }
        }

        final filtered = query.isEmpty
            ? ComposeAutocomplete.snippets
            : ComposeAutocomplete.snippets.where((s) =>
                s.label.toLowerCase().contains(query) ||
                s.category.toLowerCase().contains(query) ||
                s.description.toLowerCase().contains(query)).toList();

        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F5F9),
            border: Border(
              top: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
              bottom: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 8),
              Text(
                'Suggestions:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ActionChip(
                      avatar: Icon(item.icon, size: 14, color: theme.colorScheme.primary),
                      label: Text(item.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      tooltip: '${item.category}: ${item.description}',
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                      onPressed: () {
                        ComposeAutocomplete.insertSnippet(controller, item.snippet);
                        onSnippetInserted?.call(item.label);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
