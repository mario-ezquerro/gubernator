import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'sre_profiles_dialog.dart';

/// Prominent SRE Observability Architecture overview card displayed on the main Overview page.
class SreProfileOverviewCard extends StatefulWidget {
  final VoidCallback onRefresh;
  final VoidCallback? onViewMonitoring;

  const SreProfileOverviewCard({
    super.key,
    required this.onRefresh,
    this.onViewMonitoring,
  });

  @override
  State<SreProfileOverviewCard> createState() => _SreProfileOverviewCardState();
}

class _SreProfileOverviewCardState extends State<SreProfileOverviewCard> {
  bool _loading = true;
  String _activeProfileId = 'cloud-native';
  Map<String, dynamic>? _activeProfile;
  List<dynamic> _allProfiles = [];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final res = await ApiService.getMonitorProfiles();
      if (mounted) {
        final profiles = res['profiles'] as List<dynamic>? ?? [];
        final activeId = res['active_profile'] as String? ?? 'cloud-native';
        final active = profiles.firstWhere(
          (p) => p['id'] == activeId,
          orElse: () => profiles.isNotEmpty ? profiles.first : null,
        );

        setState(() {
          _allProfiles = profiles;
          _activeProfileId = activeId;
          _activeProfile = active != null ? Map<String, dynamic>.from(active as Map) : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openProfilesDialog() {
    showDialog(
      context: context,
      builder: (_) => SreProfilesDialog(
        onProfileChanged: () {
          _loadProfiles();
          widget.onRefresh();
        },
      ),
    );
  }

  IconData _getProfileIcon(String iconName) {
    switch (iconName) {
      case 'bolt':
        return Icons.bolt;
      case 'cloud':
        return Icons.cloud_outlined;
      case 'rocket_launch':
        return Icons.rocket_launch_outlined;
      case 'business':
        return Icons.business_outlined;
      case 'language':
        return Icons.language_outlined;
      default:
        return Icons.auto_awesome_motion;
    }
  }

  Color _getProfileColor(String id) {
    switch (id) {
      case 'ultra-light':
        return Colors.amber;
      case 'cloud-native':
        return const Color(0xFFF97316);
      case 'unified-otel':
        return Colors.cyan;
      case 'enterprise-elk':
        return Colors.deepOrangeAccent;
      case 'external-saas':
        return Colors.teal;
      default:
        return const Color(0xFFF97316);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading && _activeProfile == null) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    final p = _activeProfile ?? {
      'id': 'cloud-native',
      'name': 'Cloud-Native Balanced',
      'subtitle': 'Prometheus + Loki + Promtail + Grafana + Sloth',
      'icon': 'cloud',
      'recommended_hosts': '3 – 15 Centuriones',
      'recommended_containers': '20 – 100 contenedores',
      'recommended_ram': '1.5 – 2 GB',
      'ideal_environment': 'Startups y empresas, propósito general, cálculo de SLOs en tiempo real con Sloth y dashboards analíticos listos.',
    };

    final profileId = p['id'] as String? ?? 'cloud-native';
    final name = p['name'] as String? ?? 'Cloud-Native Balanced';
    final subtitle = p['subtitle'] as String? ?? '';
    final iconName = p['icon'] as String? ?? 'cloud';
    final recHosts = p['recommended_hosts'] as String? ?? '3 – 15 Centuriones';
    final recContainers = p['recommended_containers'] as String? ?? '20 – 100 contenedores';
    final recRAM = p['recommended_ram'] as String? ?? '1.5 – 2 GB';
    final idealEnv = p['ideal_environment'] as String? ?? '';
    final accentColor = _getProfileColor(profileId);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getProfileIcon(iconName), color: accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Arquitectura de Observabilidad SRE: $name',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'ACTIVO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _openProfilesDialog,
                icon: const Icon(Icons.auto_awesome_motion, size: 16),
                label: const Text(
                  'Cambiar Perfil SRE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Sizing & Dimensioning Badges
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildSizingChip(
                icon: Icons.dns_outlined,
                label: 'Centuriones recomendados:',
                value: recHosts,
                color: Colors.teal,
              ),
              _buildSizingChip(
                icon: Icons.inventory_2_outlined,
                label: 'Capacidad contenedores:',
                value: recContainers,
                color: Colors.lightBlue,
              ),
              _buildSizingChip(
                icon: Icons.memory,
                label: 'Huella RAM Manager:',
                value: recRAM,
                color: Colors.purpleAccent,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Ideal Environment Callout
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14171E) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                      children: [
                        const TextSpan(
                          text: 'Entorno ideal: ',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                        TextSpan(
                          text: idealEnv,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSizingChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label ',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: color),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
