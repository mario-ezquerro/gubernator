import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../models/models.dart' as models;
import 'yaml_code_editor.dart';

/// A dialog to define and deploy a new Docker Compose stack.
class NewStackDialog extends StatefulWidget {
  final Future<String?> Function(String name, String yaml, String targetNode) onDeploy;
  final List<models.Node> nodes;
  final String? initialName;
  final String? initialYaml;

  const NewStackDialog({
    super.key,
    required this.onDeploy,
    required this.nodes,
    this.initialName,
    this.initialYaml,
  });

  @override
  State<NewStackDialog> createState() => _NewStackDialogState();
}

class _NewStackDialogState extends State<NewStackDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _yamlController;
  bool _deploying = false;
  bool _showLineNumbers = true;
  String _selectedNode = 'auto';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _yamlController = TextEditingController(
      text: widget.initialYaml ??
          '''services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
    deploy:
      replicas: 1
''',
    );
  }

  void _pickFile() {
    final uploadInput = html.FileUploadInputElement();
    uploadInput.accept = '.yml,.yaml';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();

        final filename = file.name;
        final dotIdx = filename.indexOf('.');
        final name = dotIdx != -1 ? filename.substring(0, dotIdx) : filename;
        final sanitizedName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '-');

        reader.onLoadEnd.listen((e) {
          final text = reader.result as String;
          setState(() {
            _yamlController.text = text;
            if (_nameController.text.trim().isEmpty) {
              _nameController.text = sanitizedName;
            }
          });
        });

        reader.readAsText(file);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yamlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 8, 16),
                child: Row(
                  children: [
                    Icon(Icons.add_box, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.initialName != null ? 'Duplicate Stack: ${widget.initialName}' : 'Deploy New Stack',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
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

              // Content area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stack Name Input
                      Text(
                        'Stack Name',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. my-web-app',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a stack name';
                          }
                          // Valid stack names should be lowercase alphanumeric + hyphens
                          final regex = RegExp(r'^[a-z0-9\-]+$');
                          if (!regex.hasMatch(value.trim())) {
                            return 'Only lowercase letters, numbers, and hyphens allowed';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Target Node Selection
                      Text(
                        'Target Placement Node',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedNode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'auto',
                            child: Text('Automatic Scheduler (Load Balanced)'),
                          ),
                          ...widget.nodes
                              .where((n) => n.status == 'active')
                              .map((n) => DropdownMenuItem(
                                    value: n.id,
                                    child: Text('${n.id} (${n.ip} - ${n.role.toUpperCase()})'),
                                  )),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedNode = val);
                          }
                        },
                      ),
                      const SizedBox(height: 24),

                      // Compose YAML Input Header with Load file button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Docker Compose YAML',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('Load from file'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 320,
                        child: YamlCodeEditor(
                          controller: _yamlController,
                          showLineNumbers: _showLineNumbers,
                          onToggleLineNumbers: (val) => setState(() => _showLineNumbers = val),
                          isDark: isDark,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a Docker Compose YAML definition';
                            }
                            if (!value.contains('services:')) {
                              return 'YAML must contain a top-level "services:" key';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),

              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _deploying ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _deploying
                          ? null
                          : () async {
                              if (_formKey.currentState!.validate()) {
                                setState(() => _deploying = true);
                                final name = _nameController.text.trim();
                                final yaml = _yamlController.text;
                                final errorMsg = await widget.onDeploy(name, yaml, _selectedNode);
                                setState(() => _deploying = false);
                                if (errorMsg == null && context.mounted) {
                                  Navigator.of(context).pop();
                                } else if (errorMsg != null && context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Deployment Failed'),
                                      content: Text(errorMsg),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              }
                            },
                      icon: _deploying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.rocket_launch, size: 18),
                      label: Text(widget.initialName != null ? 'Duplicate Stack' : 'Deploy Stack'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
