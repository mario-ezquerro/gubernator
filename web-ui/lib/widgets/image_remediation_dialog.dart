import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Modal dialog for interactive Image Vulnerability Auto-Remediation with Risk Warnings & Safe Rollback
class ImageRemediationDialog extends StatefulWidget {
  final String imageName;
  final String? initialStackId;
  final VoidCallback onRemediationComplete;
  final Function(String stackId)? onOpenInComposeStudio;

  const ImageRemediationDialog({
    super.key,
    required this.imageName,
    this.initialStackId,
    required this.onRemediationComplete,
    this.onOpenInComposeStudio,
  });

  @override
  State<ImageRemediationDialog> createState() => _ImageRemediationDialogState();
}

class _ImageRemediationDialogState extends State<ImageRemediationDialog> {
  bool _loading = true;
  String? _errorMessage;
  RemediationPreviewModel? _preview;

  // Form selections
  String? _selectedStackId;
  String? _selectedTargetImage;
  bool _isCustomVersion = false;
  final _customImageCtrl = TextEditingController();
  bool _autoRollback = true;

  // Execution state
  bool _executing = false;
  RemediationResultModel? _result;
  List<RemediationStepLogModel> _liveLogs = [];

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  @override
  void dispose() {
    _customImageCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPreview() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final preview = await ApiService.fetchRemediationPreview(widget.imageName);
      if (!mounted) return;

      final selectable = preview.affectedStacks.isNotEmpty
          ? preview.affectedStacks
          : preview.allAvailableStacks;

      String? defaultStack;
      if (widget.initialStackId != null && widget.initialStackId!.isNotEmpty) {
        defaultStack = widget.initialStackId;
      } else if (selectable.isNotEmpty) {
        defaultStack = selectable.first.stackId;
      }

      String? defaultTarget;
      final recommended = preview.suggestedVersions.where((v) => v.isRecommended).toList();
      if (recommended.isNotEmpty) {
        defaultTarget = recommended.first.version;
      } else if (preview.suggestedVersions.isNotEmpty) {
        defaultTarget = preview.suggestedVersions.first.version;
      } else {
        defaultTarget = '${widget.imageName}:latest';
      }

      setState(() {
        _preview = preview;
        _selectedStackId = defaultStack;
        _selectedTargetImage = defaultTarget;
        _customImageCtrl.text = defaultTarget ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _applyRemediation() async {
    final target = _isCustomVersion ? _customImageCtrl.text.trim() : (_selectedTargetImage ?? '');
    if (target.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or specify a target image tag')),
      );
      return;
    }

    String? stackIdToUse = _selectedStackId;
    if (stackIdToUse == null || stackIdToUse.isEmpty) {
      if (_preview != null) {
        final selectable = _preview!.affectedStacks.isNotEmpty
            ? _preview!.affectedStacks
            : _preview!.allAvailableStacks;
        if (selectable.isNotEmpty) {
          stackIdToUse = selectable.first.stackId;
        }
      }
    }

    if (stackIdToUse == null || stackIdToUse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a target stack to remediate')),
      );
      return;
    }

    setState(() {
      _selectedStackId = stackIdToUse;
      _executing = true;
      _liveLogs = [
        RemediationStepLogModel(
          step: 'Initialization',
          message: 'Preparing automated remediation workflow for ${widget.imageName} ➔ $target...',
          status: 'ok',
          timestamp: 'Now',
        ),
      ];
    });

    try {
      final result = await ApiService.executeRemediation(
        stackId: stackIdToUse,
        currentImage: widget.imageName,
        targetImage: target,
        autoRollback: _autoRollback,
      );

      if (mounted) {
        setState(() {
          _result = result;
          _liveLogs = result.logs;
          _executing = false;
        });

        if (result.success && !result.rolledBack) {
          widget.onRemediationComplete();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _executing = false;
          _liveLogs.add(RemediationStepLogModel(
            step: 'Error',
            message: 'Execution encountered an exception: $e',
            status: 'error',
            timestamp: 'Now',
          ));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt, color: Color(0xFFF97316), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Auto-Remediate Vulnerable Image',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.imageName,
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_preview != null) ...[
            _badgeChip('CRIT', _preview!.criticalCount, Colors.redAccent),
            const SizedBox(width: 4),
            _badgeChip('HIGH', _preview!.highCount, Colors.orange),
          ],
        ],
      ),
      content: SizedBox(
        width: 680,
        child: _loading
            ? const SizedBox(
                height: 280,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Analyzing CVEs, stacks, and calculating risk posture...'),
                    ],
                  ),
                ),
              )
            : _errorMessage != null
                ? SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                          const SizedBox(height: 10),
                          Text('Failed to load remediation preview: $_errorMessage'),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _fetchPreview, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 16),

                        // Stack Selector (Auto-detected affected stack or cluster stacks fallback)
                        if (_preview != null) ...[
                          () {
                            final selectableStacks = _preview!.affectedStacks.isNotEmpty
                                ? _preview!.affectedStacks
                                : _preview!.allAvailableStacks;
                            final isAutoDetected = _preview!.affectedStacks.isNotEmpty;

                            if (selectableStacks.isNotEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.layers_outlined, size: 16, color: Colors.blueAccent),
                                      const SizedBox(width: 6),
                                      Text(
                                        isAutoDetected ? 'Target Deployed Stack (Auto-Detected):' : 'Select Target Stack in Cluster:',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const Spacer(),
                                      if (widget.onOpenInComposeStudio != null && _selectedStackId != null)
                                        TextButton.icon(
                                          icon: const Icon(Icons.code, size: 14),
                                          label: const Text('Open in Compose Studio', style: TextStyle(fontSize: 12)),
                                          onPressed: () {
                                            Navigator.pop(context);
                                            widget.onOpenInComposeStudio!(_selectedStackId!);
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        value: _selectedStackId ?? selectableStacks.first.stackId,
                                        items: selectableStacks.map((st) {
                                          return DropdownMenuItem(
                                            value: st.stackId,
                                            child: Row(
                                              children: [
                                                Text(st.stackName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                const SizedBox(width: 8),
                                                Text('➔ service: ${st.serviceName}',
                                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                                                if (isAutoDetected) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blueAccent.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text('Detected', style: TextStyle(fontSize: 9, color: Colors.blueAccent)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: _executing
                                            ? null
                                            : (val) => setState(() => _selectedStackId = val),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                              );
                            } else {
                              return Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline, color: Colors.blueAccent, size: 20),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'No deployed stacks found in cluster. You can create a new stack in Compose Studio or deploy one first.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    if (widget.onOpenInComposeStudio != null)
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.code, size: 14),
                                        label: const Text('Compose Studio'),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          widget.onOpenInComposeStudio!('');
                                        },
                                      ),
                                  ],
                                ),
                              );
                            }
                          }(),
                        ],

                        // Version Candidate Selector
                        const Row(
                          children: [
                            Icon(Icons.new_releases_outlined, size: 16, color: Color(0xFF10B981)),
                            SizedBox(width: 6),
                            Text('Choose Patched / Safe Version:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),

                        for (final ver in _preview!.suggestedVersions)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: (_selectedTargetImage == ver.version && !_isCustomVersion)
                                  ? (ver.riskLevel == 'low' ? Colors.green : Colors.blue).withValues(alpha: 0.12)
                                  : (isDark ? const Color(0xFF1E293B) : Colors.grey[50]),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (_selectedTargetImage == ver.version && !_isCustomVersion)
                                    ? (ver.riskLevel == 'low' ? const Color(0xFF10B981) : Colors.blueAccent)
                                    : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
                              ),
                            ),
                            child: RadioListTile<String>(
                              dense: true,
                              value: ver.version,
                              groupValue: _isCustomVersion ? null : _selectedTargetImage,
                              onChanged: _executing
                                  ? null
                                  : (val) {
                                      setState(() {
                                        _selectedTargetImage = val;
                                        _isCustomVersion = false;
                                      });
                                    },
                              title: Row(
                                children: [
                                  Text(ver.version, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(width: 8),
                                  if (ver.isRecommended)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                      ),
                                      child: const Text('RECOMMENDED',
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                    ),
                                  const Spacer(),
                                  _riskBadge(ver.riskLevel),
                                ],
                              ),
                              subtitle: Text(ver.description, style: const TextStyle(fontSize: 11.5)),
                            ),
                          ),

                        // Custom Tag Option
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _isCustomVersion
                                ? Colors.purple.withValues(alpha: 0.1)
                                : (isDark ? const Color(0xFF1E293B) : Colors.grey[50]),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isCustomVersion
                                  ? Colors.purpleAccent
                                  : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
                            ),
                          ),
                          child: Column(
                            children: [
                              RadioListTile<bool>(
                                dense: true,
                                value: true,
                                groupValue: _isCustomVersion,
                                onChanged: _executing
                                    ? null
                                    : (val) {
                                        setState(() => _isCustomVersion = val ?? false);
                                      },
                                title: const Text('Specify Custom Tag or Image',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: const Text('Enter specific custom image repository and version tag',
                                    style: TextStyle(fontSize: 11.5)),
                              ),
                              if (_isCustomVersion)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: TextField(
                                    controller: _customImageCtrl,
                                    enabled: !_executing,
                                    decoration: const InputDecoration(
                                      labelText: 'Target Image (e.g. postgres:16.2-alpine)',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Risk & Impact Warnings Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Color(0xFFF97316), size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Risk & Operational Impact Assessment',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFF97316)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _preview!.riskAssessment,
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'A cryptographic backup of the previous Compose definition is created automatically.',
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Safe Automated Rollback Switch
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Row(
                            children: [
                              Icon(Icons.history_toggle_off, size: 18, color: Color(0xFF10B981)),
                              SizedBox(width: 8),
                              Text('Enable Safe Automated Rollback', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          subtitle: const Text(
                            'If the upgraded container crashes or fails healthchecks within 20s, automatically revert to the previous Compose state.',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          value: _autoRollback,
                          onChanged: _executing ? null : (val) => setState(() => _autoRollback = val),
                        ),

                        // Live Monospace Execution Terminal Console
                        if (_liveLogs.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(Icons.terminal, size: 16, color: Colors.blueAccent),
                              SizedBox(width: 6),
                              Text('Remediation & Rollback Execution Console:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 150,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF090D16),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _result != null
                                    ? (_result!.success && !_result!.rolledBack ? const Color(0xFF10B981) : Colors.orange)
                                    : Colors.blueAccent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: ListView.builder(
                              itemCount: _liveLogs.length,
                              itemBuilder: (c, idx) {
                                final log = _liveLogs[idx];
                                Color stColor = const Color(0xFF10B981);
                                if (log.status == 'warn') stColor = Colors.orange;
                                if (log.status == 'error') stColor = Colors.redAccent;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('[${log.timestamp}]', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
                                      const SizedBox(width: 6),
                                      Text('[${log.step}]', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: stColor, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          log.message,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color: log.status == 'error' ? Colors.redAccent : Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],

                        if (_result != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (_result!.success && !_result!.rolledBack ? const Color(0xFF10B981) : Colors.orange)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _result!.success && !_result!.rolledBack ? const Color(0xFF10B981) : Colors.orange,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _result!.success && !_result!.rolledBack ? Icons.check_circle : Icons.warning_rounded,
                                  color: _result!.success && !_result!.rolledBack ? const Color(0xFF10B981) : Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _result!.message,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: _result!.success && !_result!.rolledBack ? const Color(0xFF10B981) : Colors.orange,
                                    ),
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
      actions: [
        TextButton(
          onPressed: _executing ? null : () => Navigator.pop(context),
          child: Text(_result != null ? 'Close' : 'Cancel'),
        ),
        if (!_executing && _result == null && _preview != null)
          FilledButton.icon(
            icon: const Icon(Icons.bolt, size: 18),
            label: const Text('Apply Fix & Redeploy'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF97316),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: _applyRemediation,
          ),
      ],
    );
  }

  Widget _badgeChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  Widget _riskBadge(String level) {
    Color col = const Color(0xFF10B981);
    if (level == 'medium') col = Colors.orange;
    if (level == 'high') col = Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${level.toUpperCase()} RISK',
        style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 9.5),
      ),
    );
  }
}
