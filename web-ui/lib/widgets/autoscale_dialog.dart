import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Modal dialog providing interactive controls to configure and manage
/// Horizontal Autoscaling (GPU & CPU, Single-Host vs Cluster-wide) for Stacks and Services.
class AutoscaleControlDialog extends StatefulWidget {
  final StackModel? stack;
  final Service? service;
  final List<Service> stackServices;
  final VoidCallback? onSaved;

  const AutoscaleControlDialog({
    super.key,
    this.stack,
    this.service,
    this.stackServices = const [],
    this.onSaved,
  });

  @override
  State<AutoscaleControlDialog> createState() => _AutoscaleControlDialogState();
}

class _AutoscaleControlDialogState extends State<AutoscaleControlDialog> {
  late bool _enabled;
  late String _metric; // 'gpu' or 'cpu'
  late String _scope; // 'host' or 'cluster'
  late double _target;
  late int _minReplicas;
  late int _maxReplicas;
  late String _cooldown;

  String? _selectedServiceId; // null means "All Services in Stack"
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Resolve initial service to pull defaults from
    final initialSvc = widget.service ??
        (widget.stackServices.isNotEmpty ? widget.stackServices.first : null);

    if (initialSvc != null && initialSvc.isAutoscalingEnabled) {
      _enabled = true;
      _metric = initialSvc.autoscaleMetric;
      _scope = initialSvc.autoscaleScope;
      _target = initialSvc.autoscaleTarget;
      _minReplicas = initialSvc.autoscaleMin;
      _maxReplicas = initialSvc.autoscaleMax;
      _cooldown = initialSvc.autoscaleCooldown;
    } else {
      _enabled = false;
      _metric = 'gpu'; // Default to prominent GPU metric
      _scope = 'host';
      _target = 80.0;
      _minReplicas = 1;
      _maxReplicas = 5;
      _cooldown = '60s';
    }

    if (widget.service != null) {
      _selectedServiceId = widget.service!.id;
    }
  }

  void _onServiceSelected(String? svcId) {
    setState(() {
      _selectedServiceId = svcId;
      if (svcId != null) {
        final svc = widget.stackServices.where((s) => s.id == svcId).firstOrNull;
        if (svc != null && svc.isAutoscalingEnabled) {
          _enabled = true;
          _metric = svc.autoscaleMetric;
          _scope = svc.autoscaleScope;
          _target = svc.autoscaleTarget;
          _minReplicas = svc.autoscaleMin;
          _maxReplicas = svc.autoscaleMax;
          _cooldown = svc.autoscaleCooldown;
        }
      }
    });
  }

  Future<void> _saveAndApply() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final payload = {
      'enabled': _enabled,
      'metric': _metric,
      'scope': _scope,
      'target': _target,
      'min': _minReplicas,
      'max': _maxReplicas,
      'cooldown': _cooldown,
    };

    bool success = false;
    try {
      if (_selectedServiceId != null) {
        success = await ApiService.updateServiceAutoscale(_selectedServiceId!, payload);
      } else if (widget.service != null) {
        success = await ApiService.updateServiceAutoscale(widget.service!.id, payload);
      } else if (widget.stack != null) {
        success = await ApiService.updateStackAutoscale(widget.stack!.id, payload);
      }

      if (success) {
        if (mounted) {
          Navigator.of(context).pop(true);
          widget.onSaved?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text(_enabled
                      ? 'Autoscale configured: ${_metric.toUpperCase()} at ${_target.toInt()}% ($_scope)'
                      : 'Autoscale disabled successfully'),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to apply autoscale configuration. Please try again.';
          _saving = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGpu = _metric == 'gpu';
    final isCluster = _scope == 'cluster';

    final targetTitle = widget.service != null
        ? 'Service: ${widget.service!.name}'
        : (widget.stack != null ? 'Stack: ${widget.stack!.name}' : 'Autoscale Configuration');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isGpu
                            ? [const Color(0xFFA855F7), const Color(0xFF6366F1)]
                            : [const Color(0xFF06B6D4), const Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bolt, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Horizontal Autoscaling Controls',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          targetTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'Courier New',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Service Selector (if configuring stack with multiple services)
                    if (widget.stack != null && widget.stackServices.length > 1) ...[
                      Row(
                        children: [
                          const Icon(Icons.account_tree_outlined, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          const Text(
                            'Target Scope / Service',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedServiceId,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Services in Stack (${widget.stackServices.length})'),
                              ),
                              ...widget.stackServices.map(
                                (s) => DropdownMenuItem<String?>(
                                  value: s.id,
                                  child: Text('Service: ${s.name} (${s.image})'),
                                ),
                              ),
                            ],
                            onChanged: _onServiceSelected,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Master Enable / Disable Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _enabled
                            ? (isGpu
                                ? const Color(0xFFA855F7).withValues(alpha: 0.1)
                                : const Color(0xFF06B6D4).withValues(alpha: 0.1))
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _enabled
                              ? (isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4))
                              : theme.colorScheme.outlineVariant,
                          width: _enabled ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _enabled ? Icons.check_circle : Icons.power_settings_new,
                            color: _enabled
                                ? (_metric == 'gpu' ? const Color(0xFFA855F7) : const Color(0xFF06B6D4))
                                : Colors.grey,
                            size: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _enabled ? 'Autoscaling Active' : 'Autoscaling Disabled',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: _enabled ? null : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _enabled
                                      ? 'Workload metrics are evaluated every 15s. Replicas scale automatically within limits.'
                                      : 'Containers maintain fixed replica count. Watchdog will not auto-scale.',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _enabled,
                            activeThumbColor: isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4),
                            onChanged: (val) => setState(() => _enabled = val),
                          ),
                        ],
                      ),
                    ),

                    if (_enabled) ...[
                      const SizedBox(height: 24),

                      // Section: Metric Selection
                      const Text(
                        '1. SCALING METRIC',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _metricCard(
                              title: 'GPU (NVIDIA / CUDA)',
                              badge: 'AI / ML ACCELERATED',
                              subtitle: 'Monitors real-time GPU load & memory via DCGM. Binds to GPU-enabled Centurions.',
                              icon: Icons.developer_board,
                              selected: isGpu,
                              accentColor: const Color(0xFFA855F7),
                              onTap: () => setState(() => _metric = 'gpu'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _metricCard(
                              title: 'CPU Utilization',
                              badge: 'STANDARD COMPUTE',
                              subtitle: 'Monitors container CPU % against CPU quota / reservation limits.',
                              icon: Icons.speed,
                              selected: !isGpu,
                              accentColor: const Color(0xFF06B6D4),
                              onTap: () => setState(() => _metric = 'cpu'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Section: Scaling Scope
                      const Text(
                        '2. SCALING SCOPE & AFFINITY',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _scopeCard(
                              title: 'Single Host (Local)',
                              subtitle: 'All scaled instances run strictly on the local host node. Preserves host-local volumes and lowest latency.',
                              icon: Icons.computer,
                              selected: !isCluster,
                              onTap: () => setState(() => _scope = 'host'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _scopeCard(
                              title: 'All Centurions (Cluster)',
                              subtitle: 'Horizontally spreads new replicas across active worker nodes based on hardware availability.',
                              icon: Icons.hub,
                              selected: isCluster,
                              onTap: () => setState(() => _scope = 'cluster'),
                            ),
                          ),
                        ],
                      ),

                      if (isGpu) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA855F7).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Color(0xFFA855F7), size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Centurion Affinity: Workload will only scale onto nodes with "gbnt.node.gpu=nvidia" hardware label.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFFA855F7)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Section: Target Utilization Threshold
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '3. TARGET UTILIZATION THRESHOLD',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1, color: Colors.grey),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4)).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_target.toInt()}% ${isGpu ? "GPU" : "CPU"}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4),
                          thumbColor: isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4),
                          overlayColor: (isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4)).withValues(alpha: 0.2),
                        ),
                        child: Slider(
                          value: _target,
                          min: 10,
                          max: 100,
                          divisions: 18,
                          label: '${_target.toInt()}%',
                          onChanged: (val) => setState(() => _target = val),
                        ),
                      ),
                      Text(
                        'When average workload utilization exceeds ${_target.toInt()}%, Gubernator automatically provisions an additional replica.',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),

                      const SizedBox(height: 24),

                      // Section: Replica Limits (Min & Max) and Cooldown
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Min Replicas
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MIN REPLICAS',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 6),
                                _numberStepper(
                                  value: _minReplicas,
                                  minValue: 1,
                                  maxValue: _maxReplicas,
                                  onChanged: (val) => setState(() => _minReplicas = val),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Max Replicas
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MAX REPLICAS',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 6),
                                _numberStepper(
                                  value: _maxReplicas,
                                  minValue: _minReplicas,
                                  maxValue: 50,
                                  onChanged: (val) => setState(() => _maxReplicas = val),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Cooldown
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'COOLDOWN',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: theme.colorScheme.outlineVariant),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _cooldown,
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(value: '30s', child: Text('30 sec')),
                                        DropdownMenuItem(value: '60s', child: Text('60 sec')),
                                        DropdownMenuItem(value: '2m', child: Text('2 min')),
                                        DropdownMenuItem(value: '5m', child: Text('5 min')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _cooldown = val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.colorScheme.error),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer / Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isGpu ? const Color(0xFFA855F7) : const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _saving ? null : _saveAndApply,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bolt, size: 18),
                    label: Text(_saving ? 'Applying...' : 'Save & Apply Autoscale'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String badge,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? accentColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accentColor : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: selected ? accentColor : Colors.grey, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: selected ? accentColor : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: selected ? theme.colorScheme.primary : Colors.grey, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: selected ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberStepper({
    required int value,
    required int minValue,
    required int maxValue,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: value > minValue ? () => onChanged(value - 1) : null,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '$value',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: value < maxValue ? () => onChanged(value + 1) : null,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
