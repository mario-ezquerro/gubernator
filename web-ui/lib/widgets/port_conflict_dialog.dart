import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// User action choice when resolving host port collisions
enum PortConflictAction {
  autoRemap,
  force,
  cancel,
}

/// Helper to execute stack deployment with interactive port collision handling
Future<DeployStackResult> deployWithConflictResolution({
  required BuildContext context,
  required String stackName,
  required String compose,
  String? targetNode,
}) async {
  var result = await ApiService.deployStackDetailed(
    stackName,
    compose,
    targetNode: targetNode,
  );
  if (!result.success && result.isConflict && result.conflicts.isNotEmpty && context.mounted) {
    final action = await showDialog<PortConflictAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PortConflictDialog(
        stackName: stackName,
        conflicts: result.conflicts,
      ),
    );
    if (action == PortConflictAction.autoRemap && context.mounted) {
      result = await ApiService.deployStackDetailed(
        stackName,
        compose,
        targetNode: targetNode,
        autoRemapPorts: true,
      );
    } else if (action == PortConflictAction.force && context.mounted) {
      result = await ApiService.deployStackDetailed(
        stackName,
        compose,
        targetNode: targetNode,
        force: true,
      );
    }
  }
  return result;
}

/// A modern Material 3 diagnostic dialog displaying conflicting host ports
/// and offering one-click resolution (Auto-Remap, Force Deploy, or Cancel).
class PortConflictDialog extends StatelessWidget {
  final String stackName;
  final List<PortConflictModel> conflicts;

  const PortConflictDialog({
    super.key,
    required this.stackName,
    required this.conflicts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Host Port Conflict Detected',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ports requested by "$stackName" are already allocated',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E222A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Scheduling cannot bind to the requested host ports because existing workloads are occupying them. Review the collisions below and select a resolution.',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'CONFLICTING PORT MAPPINGS (${conflicts.length})',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ...conflicts.map((c) => _buildConflictCard(context, c, isDark)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(PortConflictAction.cancel),
          child: const Text('Cancel / Edit Compose'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(PortConflictAction.force),
          icon: const Icon(Icons.bolt, size: 16, color: Colors.orangeAccent),
          label: const Text('Force Deploy Anyway', style: TextStyle(color: Colors.orangeAccent)),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(PortConflictAction.autoRemap),
          icon: const Icon(Icons.auto_fix_high, size: 16),
          label: const Text('Auto-Remap & Deploy'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildConflictCard(BuildContext context, PortConflictModel conflict, bool isDark) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(
                conflict.service,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Port ${conflict.hostPort}/${conflict.protocol.toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.link_off, size: 14, color: Colors.orangeAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Occupied by ',
                    style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                    children: [
                      TextSpan(
                        text: conflict.conflictingStack,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent),
                      ),
                      if (conflict.conflictingService.isNotEmpty) ...[
                        const TextSpan(text: ' (service: '),
                        TextSpan(
                          text: conflict.conflictingService,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ')'),
                      ],
                      const TextSpan(text: ' on '),
                      TextSpan(
                        text: conflict.nodeId,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (conflict.nodeIp.isNotEmpty) ...[
                        TextSpan(text: ' (${conflict.nodeIp})'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 14, color: Colors.tealAccent),
              const SizedBox(width: 6),
              Text(
                'Available free port suggested:',
                style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_forward, size: 12, color: Colors.tealAccent),
                    const SizedBox(width: 4),
                    Text(
                      '${conflict.suggestedPort}:${conflict.hostPort}',
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
