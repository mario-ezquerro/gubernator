import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Interactive modal dialog displaying SRE Observability Architecture Profiles & Presets.
class SreProfilesDialog extends StatefulWidget {
  final VoidCallback? onProfileChanged;

  const SreProfilesDialog({super.key, this.onProfileChanged});

  @override
  State<SreProfilesDialog> createState() => _SreProfilesDialogState();
}

class _SreProfilesDialogState extends State<SreProfilesDialog> {
  bool _loading = true;
  String? _switchingProfileId;
  String? _errorMessage;
  List<dynamic> _profiles = [];
  String _activeProfile = 'cloud-native';

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.getMonitorProfiles();
      if (mounted) {
        setState(() {
          _profiles = res['profiles'] as List<dynamic>? ?? [];
          _activeProfile = res['active_profile'] as String? ?? 'cloud-native';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmSwitchProfile(Map<String, dynamic> profile) async {
    final profileId = profile['id'] as String? ?? '';
    final profileName = profile['name'] as String? ?? '';
    final isAlreadyActive = profile['is_active'] == true || profileId == _activeProfile;

    if (isAlreadyActive) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.swap_horiz, color: Color(0xFFF97316)),
            const SizedBox(width: 8),
            Text('Cambiar a $profileName'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Deseas desplegar el perfil "$profileName"?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gubernator detendrá el stack actual de observabilidad y desplegará los nuevos contenedores adaptados a este perfil.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade300),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.rocket_launch, size: 16),
            label: const Text('Confirmar y Desplegar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _switchingProfileId = profileId;
    });

    try {
      await ApiService.switchMonitorProfile(profileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Pila SRE cambiada exitosamente al perfil "$profileName".'),
            backgroundColor: Colors.green.shade800,
          ),
        );
        widget.onProfileChanged?.call();
        await _loadProfiles();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al cambiar perfil: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _switchingProfileId = null;
        });
      }
    }
  }

  IconData _getIconForProfile(String iconName) {
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
        return Icons.analytics_outlined;
    }
  }

  Color _getColorForProfile(String id) {
    switch (id) {
      case 'ultra-light':
        return Colors.amber;
      case 'cloud-native':
        return Colors.indigoAccent;
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

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 850),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_motion, color: Color(0xFFF97316), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'SRE Observability Architecture Profiles',
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF97316).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PLUGINS & PRESETS',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFF97316)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Selecciona y despliega la arquitectura de métricas y logs adaptada al número de Centuriones y memoria de tu clúster.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Cargando perfiles SRE disponibles...'),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 12),
                              Text('Error: $_errorMessage'),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _loadProfiles,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: _profiles.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 18),
                          itemBuilder: (context, index) {
                            final p = _profiles[index] as Map<String, dynamic>;
                            return _buildProfileCard(p, theme, isDark);
                          },
                        ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Text(
                    'También disponible por CLI: gbnt monitor profiles | gbnt monitor switch <id>',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> p, ThemeData theme, bool isDark) {
    final id = p['id'] as String? ?? '';
    final name = p['name'] as String? ?? '';
    final subtitle = p['subtitle'] as String? ?? '';
    final iconName = p['icon'] as String? ?? '';
    final recHosts = p['recommended_hosts'] as String? ?? '';
    final recContainers = p['recommended_containers'] as String? ?? '';
    final recRAM = p['recommended_ram'] as String? ?? '';
    final idealEnv = p['ideal_environment'] as String? ?? '';
    final description = p['description'] as String? ?? '';
    final components = (p['components'] as Map<String, dynamic>?) ?? {};
    final isActive = p['is_active'] == true || id == _activeProfile;
    final isSwitching = _switchingProfileId == id;
    final accentColor = _getColorForProfile(id);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? Colors.green.withValues(alpha: 0.6) : theme.dividerColor.withValues(alpha: 0.6),
          width: isActive ? 2 : 1,
        ),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Header (Avatar, Title, Subtitle, Active Badge/Button)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_getIconForProfile(iconName), color: accentColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'ACTIVO',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              // Action Button
              if (isSwitching)
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (isActive)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.12),
                    foregroundColor: Colors.green,
                  ),
                  onPressed: null,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Perfil Activo'),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _switchingProfileId != null ? null : () => _confirmSwitchProfile(p),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Desplegar Perfil'),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 2: Sizing & Capacity Badges
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildSizingChip(
                icon: Icons.computer,
                label: 'Hosts:',
                value: recHosts,
                color: Colors.teal,
              ),
              _buildSizingChip(
                icon: Icons.inventory_2_outlined,
                label: 'Capacidad:',
                value: recContainers,
                color: Colors.lightBlue,
              ),
              _buildSizingChip(
                icon: Icons.memory,
                label: 'RAM Manager:',
                value: recRAM,
                color: Colors.purpleAccent,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Row 3: Ideal Environment Callout Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14171E) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
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

          const SizedBox(height: 10),

          // Row 4: Description
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 12),

          // Row 5: Component breakdown chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: components.entries.map((entry) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${entry.key}: ${entry.value}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              );
            }).toList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$label ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
