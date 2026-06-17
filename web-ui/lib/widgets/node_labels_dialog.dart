import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class NodeLabelsDialog extends StatefulWidget {
  final Node node;
  final VoidCallback onLabelsSaved;

  const NodeLabelsDialog({
    super.key,
    required this.node,
    required this.onLabelsSaved,
  });

  @override
  State<NodeLabelsDialog> createState() => _NodeLabelsDialogState();
}

class _NodeLabelsDialogState extends State<NodeLabelsDialog> {
  final List<TextEditingController> _keyControllers = [];
  final List<TextEditingController> _valueControllers = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Track the fixed labels separately
  late final String _roleVal;
  late final String _archVal;

  @override
  void initState() {
    super.initState();
    _roleVal = widget.node.labels['gbnt.node.role'] ?? widget.node.role;
    _archVal = widget.node.labels['gbnt.node.arch'] ?? 'unknown';

    // Populate custom labels
    widget.node.labels.forEach((key, value) {
      if (key != 'gbnt.node.role' && key != 'gbnt.node.arch') {
        _keyControllers.add(TextEditingController(text: key));
        _valueControllers.add(TextEditingController(text: value.toString()));
      }
    });
  }

  @override
  void dispose() {
    for (var ctrl in _keyControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _valueControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addLabelField() {
    setState(() {
      _keyControllers.add(TextEditingController());
      _valueControllers.add(TextEditingController());
      _errorMessage = null;
    });
  }

  void _removeLabelField(int index) {
    setState(() {
      _keyControllers[index].dispose();
      _valueControllers[index].dispose();
      _keyControllers.removeAt(index);
      _valueControllers.removeAt(index);
      _errorMessage = null;
    });
  }

  Future<void> _saveLabels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final Map<String, String> finalLabels = {
      'gbnt.node.role': _roleVal,
      'gbnt.node.arch': _archVal,
    };

    final Set<String> keysSeen = {'gbnt.node.role', 'gbnt.node.arch'};

    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text.trim();
      final val = _valueControllers[i].text.trim();

      if (key.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Label keys cannot be empty.';
        });
        return;
      }

      if (key == 'gbnt.node.role' || key == 'gbnt.node.arch') {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Key "$key" is a reserved system label.';
        });
        return;
      }

      if (keysSeen.contains(key)) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Duplicate label key: "$key"';
        });
        return;
      }

      keysSeen.add(key);
      finalLabels[key] = val;
    }

    try {
      final success = await ApiService.updateNodeLabels(widget.node.id, finalLabels);
      if (success) {
        widget.onLabelsSaved();
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to save labels to server.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Header ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 16),
              child: Row(
                children: [
                  Icon(Icons.label, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Edit Node Labels',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ─── Body ───────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System Labels (Read-only)',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 12),

                    // Role Card
                    _buildFixedLabelRow('gbnt.node.role', _roleVal, theme, isDark),
                    const SizedBox(height: 8),

                    // Arch Card
                    _buildFixedLabelRow('gbnt.node.arch', _archVal, theme, isDark),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Custom Labels',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        TextButton.icon(
                          onPressed: _isLoading ? null : _addLabelField,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Label'),
                        ),
                      ],
                    ),
                    const Divider(height: 16),

                    if (_keyControllers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No custom labels defined for this node.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _keyControllers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Key TextField
                              Expanded(
                                flex: 4,
                                child: TextField(
                                  controller: _keyControllers[index],
                                  enabled: !_isLoading,
                                  decoration: const InputDecoration(
                                    labelText: 'Key',
                                    hintText: 'e.g. zone',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('='),
                              const SizedBox(width: 8),
                              // Value TextField
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  controller: _valueControllers[index],
                                  enabled: !_isLoading,
                                  decoration: const InputDecoration(
                                    labelText: 'Value',
                                    hintText: 'e.g. europe-west1',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Delete Button
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Remove label',
                                onPressed: _isLoading ? null : () => _removeLabelField(index),
                              ),
                            ],
                          );
                        },
                      ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                          border: Border.all(color: theme.colorScheme.error),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                            const SizedBox(width: 12),
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
            const Divider(height: 1),

            // ─── Actions ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _saveLabels,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedLabelRow(String key, String value, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(
                  '$key = ',
                  style: const TextStyle(fontFamily: 'Courier New', fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'System',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
