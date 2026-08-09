import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String releaseUrl;
  final VoidCallback onUpdateTriggered;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.onUpdateTriggered,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _ParsedCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  _ParsedCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _applying = false;
  String? _error;

  void _closeDialog() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _openReleaseUrl() async {
    if (widget.releaseUrl.isEmpty) return;
    final uri = Uri.parse(widget.releaseUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _handleApply() async {
    setState(() {
      _applying = true;
      _error = null;
    });

    try {
      final success = await ApiService.applyUpdate(widget.latestVersion);
      if (mounted) {
        if (success) {
          _closeDialog();
          widget.onUpdateTriggered();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🚀 Cluster update to ${widget.latestVersion} initiated! Nodes are pulling new images...',
              ),
              backgroundColor: const Color(0xFFF97316),
            ),
          );
        } else {
          setState(() {
            _applying = false;
            _error = 'Failed to initiate update on the cluster manager.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _applying = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  List<_ParsedCategory> _parseNotes(String notes) {
    final Map<String, List<String>> categories = {
      'features': [],
      'fixes': [],
      'slo': [],
      'security': [],
      'other': [],
    };

    final lines = notes.split('\n');
    for (var line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('---') || trimmed.startsWith('===') || trimmed.startsWith('|')) continue;

      // Remove markdown list indicators (#, ##, *, -, •, numbers)
      trimmed = trimmed.replaceAll(RegExp(r'^(#{1,6}\s*|\*\s*|-\s*|•\s*|\d+\.\s*)'), '').trim();
      if (trimmed.isEmpty) continue;

      // Clean markdown formatting (**bold**, `code`)
      trimmed = trimmed.replaceAll('**', '').replaceAll('`', '');

      final lower = trimmed.toLowerCase();
      if (lower.startsWith('what') || lower.startsWith('release notes') || lower.startsWith('changelog')) {
        continue;
      }

      if (lower.contains('feat') || lower.contains('add') || lower.contains('new') || lower.contains('novedad') || lower.contains('mejora')) {
        categories['features']!.add(trimmed);
      } else if (lower.contains('fix') || lower.contains('bug') || lower.contains('patch') || lower.contains('solucion') || lower.contains('correcci')) {
        categories['fixes']!.add(trimmed);
      } else if (lower.contains('slo') || lower.contains('perf') || lower.contains('speed') || lower.contains('optimi') || lower.contains('rendimiento')) {
        categories['slo']!.add(trimmed);
      } else if (lower.contains('sec') || lower.contains('auth') || lower.contains('token') || lower.contains('tls') || lower.contains('seguridad')) {
        categories['security']!.add(trimmed);
      } else {
        categories['other']!.add(trimmed);
      }
    }

    final List<_ParsedCategory> result = [];

    if (categories['features']!.isNotEmpty) {
      result.add(_ParsedCategory(
        title: 'Features & Enhancements',
        icon: Icons.auto_awesome,
        color: const Color(0xFF10B981),
        items: categories['features']!,
      ));
    }
    if (categories['fixes']!.isNotEmpty) {
      result.add(_ParsedCategory(
        title: 'Bug Fixes & Stability',
        icon: Icons.bug_report,
        color: const Color(0xFF3B82F6),
        items: categories['fixes']!,
      ));
    }
    if (categories['slo']!.isNotEmpty) {
      result.add(_ParsedCategory(
        title: 'Performance & SLO Engine',
        icon: Icons.speed,
        color: const Color(0xFFF59E0B),
        items: categories['slo']!,
      ));
    }
    if (categories['security']!.isNotEmpty) {
      result.add(_ParsedCategory(
        title: 'Security & Infrastructure',
        icon: Icons.shield,
        color: const Color(0xFF8B5CF6),
        items: categories['security']!,
      ));
    }
    if (categories['other']!.isNotEmpty) {
      result.add(_ParsedCategory(
        title: 'General Improvements',
        icon: Icons.checklist,
        color: const Color(0xFF6B7280),
        items: categories['other']!,
      ));
    }

    if (result.isEmpty) {
      result.add(_ParsedCategory(
        title: 'Cluster Core Update',
        icon: Icons.system_update,
        color: const Color(0xFFF97316),
        items: [
          'Automated rolling upgrade to version ${widget.latestVersion}',
          'Updated Docker container base images and dependencies',
          'Cluster state synchronization and stability enhancements',
        ],
      ));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    final categories = _parseNotes(widget.releaseNotes);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: maxHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.system_update_alt,
                      color: Color(0xFFF97316),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cluster Auto-Update Available',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'A new version of Gubernator is ready to deploy',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: _closeDialog,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Version Transition Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFF97316).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Installed Version',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currentVersion,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Courier New',
                                  ),
                                ),
                              ],
                            ),
                            const Icon(
                              Icons.arrow_forward,
                              color: Color(0xFFF97316),
                              size: 20,
                            ),
                            Column(
                              children: [
                                const Text(
                                  'New Version',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFF97316),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF97316).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.latestVersion,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF97316),
                                      fontFamily: 'Courier New',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Release Notes Header & Summary Badges Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Update Improvements:',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Wrap(
                                spacing: 4,
                                children: categories.map((cat) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cat.color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(cat.icon, size: 12, color: cat.color),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${cat.items.length}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: cat.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                          if (widget.releaseUrl.isNotEmpty)
                            InkWell(
                              onTap: _openReleaseUrl,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Row(
                                  children: [
                                    Text(
                                      'GitHub Release',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.open_in_new,
                                      size: 12,
                                      color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Structured Release Notes List Box
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: categories.map((cat) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Category Header
                                    Row(
                                      children: [
                                        Icon(cat.icon, size: 15, color: cat.color),
                                        const SizedBox(width: 6),
                                        Text(
                                          cat.title,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: cat.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Items List
                                    ...cat.items.map((item) {
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '• ',
                                              style: TextStyle(
                                                color: cat.color,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                item,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                                                  height: 1.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Cluster Notice Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                color: Colors.amber, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Confirming will trigger an automated rolling update across the Manager and all registered Worker nodes in the cluster.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.amber[200] : Colors.amber[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _applying ? null : _closeDialog,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _applying ? null : _handleApply,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF97316),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.rocket_launch, size: 18),
                    label: Text(
                      _applying
                          ? 'Applying Cluster Update...'
                          : 'Apply Update Cluster-Wide',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
