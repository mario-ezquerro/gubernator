import 'package:flutter/material.dart';
import 'yaml_code_editor.dart';

/// A full-screen dialog for viewing and editing a stack's compose YAML.
class ComposeEditorDialog extends StatefulWidget {
  final String stackName;
  final String composeYaml;
  final Future<bool> Function(String yaml) onSave;
  final Future<bool> Function(String yaml) onRedeploy;

  const ComposeEditorDialog({
    super.key,
    required this.stackName,
    required this.composeYaml,
    required this.onSave,
    required this.onRedeploy,
  });

  @override
  State<ComposeEditorDialog> createState() => _ComposeEditorDialogState();
}

class _ComposeEditorDialogState extends State<ComposeEditorDialog> {
  late TextEditingController _controller;
  late String _originalYaml;
  bool _saving = false;
  bool _redeploying = false;
  bool _showLineNumbers = true;

  @override
  void initState() {
    super.initState();
    _originalYaml = widget.composeYaml;
    _controller = TextEditingController(text: widget.composeYaml);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.code, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Edit Compose: ${widget.stackName}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Editor
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: YamlCodeEditor(
                  controller: _controller,
                  showLineNumbers: _showLineNumbers,
                  onToggleLineNumbers: (val) => setState(() => _showLineNumbers = val),
                  isDark: isDark,
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _controller.text = _originalYaml;
                    },
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Reset'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            final ok =
                                await widget.onSave(_controller.text);
                            setState(() => _saving = false);
                            if (ok && context.mounted) {
                              _originalYaml = _controller.text;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Compose saved successfully')),
                              );
                            }
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _redeploying
                        ? null
                        : () async {
                            setState(() => _redeploying = true);
                            await widget.onSave(_controller.text);
                            final ok =
                                await widget.onRedeploy(_controller.text);
                            setState(() => _redeploying = false);
                            if (ok && context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Stack redeployed!')),
                              );
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD29922),
                    ),
                    icon: _redeploying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.rocket_launch, size: 18),
                    label: const Text('Save & Redeploy'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
