import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/yaml.dart';
import 'compose_autocomplete.dart';
import 'server_stack_picker_dialog.dart';
import 'poc_examples_dialog.dart';
import '../models/models.dart' as models;
import '../utils/clipboard_service.dart';

/// A dialog to define and deploy a new Docker Compose stack, featuring the Gubernator Copilot.
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
  late final CodeController _yamlController;
  bool _deploying = false;
  String _selectedNode = 'auto';
  String _activeTab = 'caddy';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _yamlController = CodeController(
      text: widget.initialYaml ??
          '''services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
    deploy:
      replicas: 1
''',
      language: yaml,
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

  void _showServerStackPicker() {
    showDialog(
      context: context,
      builder: (ctx) => ServerStackPickerDialog(
        onSelect: (name, yaml) {
          setState(() {
            _yamlController.text = yaml;
            if (_nameController.text.trim().isEmpty) {
              _nameController.text = name;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded "$name" from Master server')),
          );
        },
      ),
    );
  }

  void _showPOCExamples() {
    showDialog(
      context: context,
      builder: (ctx) => POCExamplesDialog(
        nodes: widget.nodes,
        onOpenInStudio: (name, yaml) {
          setState(() {
            _yamlController.text = yaml;
            if (_nameController.text.trim().isEmpty) {
              _nameController.text = name;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded POC Blueprint "$name"')),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yamlController.dispose();
    super.dispose();
  }

  void _injectLabel(String labelKey, String labelValue) {
    final text = _yamlController.text;
    final pos = _yamlController.selection.baseOffset;
    final injection = '        - $labelKey=$labelValue\n';
    if (pos >= 0 && pos <= text.length) {
      _yamlController.text = text.substring(0, pos) + injection + text.substring(pos);
      _yamlController.selection = TextSelection.collapsed(offset: pos + injection.length);
    } else {
      _yamlController.text = text + '\n' + injection;
    }
  }

  void _injectVolume() {
     final pos = _yamlController.selection.baseOffset;
     final text = _yamlController.text;
     final injection = '      - /var/contenedores/\${STACK_NAME}/data:/data\n';
     if (pos >= 0 && pos <= text.length) {
      _yamlController.text = text.substring(0, pos) + injection + text.substring(pos);
      _yamlController.selection = TextSelection.collapsed(offset: pos + injection.length);
    } else {
      _yamlController.text = text + '\n' + injection;
    }
  }

  Widget _buildCopilotPanel(ThemeData theme) {
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Gubernator Copilot',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tabBtn('Caddy', 'caddy', Icons.public),
                _tabBtn('SLO', 'slo', Icons.show_chart),
                _tabBtn('Security', 'security', Icons.security),
                _tabBtn('Nodes', 'nodes', Icons.memory),
                _tabBtn('Storage', 'storage', Icons.storage),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_activeTab == 'caddy') ...[
                  const Text('Caddy Ingress', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Inject routing labels to expose your service via Caddy reverse proxy.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      _injectLabel('ingress.host', 'app.gbnt.local');
                      _injectLabel('gbnt.caddy.port', '80');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Caddy Routing Labels'),
                  ),
                ],
                if (_activeTab == 'slo') ...[
                  const Text('SLO Engine (Sloth)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Inject Service Level Objective alerting rules.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      _injectLabel('gbnt.slo.enable', 'true');
                      _injectLabel('gbnt.slo.target', '99.9');
                      _injectLabel('gbnt.slo.window', '30d');
                      _injectLabel('gbnt.slo.indicator', 'latency');
                      _injectLabel('gbnt.slo.latency.threshold', '200ms');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add 99.9% Latency SLO'),
                  ),
                ],
                if (_activeTab == 'security') ...[
                  const Text('Security Gatekeeper', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Enforce cryptographic signatures or block vulnerable images.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      _injectLabel('gbnt.security.require-signature', 'true');
                      _injectLabel('gbnt.security.max-cve-severity', 'critical');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Enforce Signatures & Block CVEs'),
                  ),
                ],
                if (_activeTab == 'nodes') ...[
                  const Text('Node Placement Constraints', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Pin this service to specific hardware or node roles.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ...widget.nodes.map((n) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${n.id} [${n.role}]', style: const TextStyle(fontSize: 13)),
                    subtitle: Text(n.ip, style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        final text = _yamlController.text;
                        final pos = _yamlController.selection.baseOffset;
                        final injection = '      placement:\n        constraints:\n          - "node.hostname==${n.id}"\n';
                        if (pos >= 0 && pos <= text.length) {
                          _yamlController.text = text.substring(0, pos) + injection + text.substring(pos);
                        } else {
                          _yamlController.text = text + '\n' + injection;
                        }
                      },
                    ),
                  )).toList(),
                ],
                if (_activeTab == 'storage') ...[
                  const Text('Storage Granaries', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Inject shared volume mounts for mobility.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _injectVolume,
                    icon: const Icon(Icons.add),
                    label: const Text('Add /var/contenedores/ Mount'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String title, String id, IconData icon) {
    final active = _activeTab == id;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _activeTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? theme.colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: active ? theme.colorScheme.primary : Colors.grey),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? theme.colorScheme.primary : Colors.grey,
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 800),
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

              // Content area (Top metadata + Editor/Copilot split)
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                    if (value == null || value.trim().isEmpty) return 'Please enter a stack name';
                                    if (!RegExp(r'^[a-z0-9\-]+$').hasMatch(value.trim())) return 'Only lowercase letters, numbers, and hyphens allowed';
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                    const DropdownMenuItem(value: 'auto', child: Text('Automatic Scheduler (Load Balanced)')),
                                    ...widget.nodes.where((n) => n.status == 'active').map((n) => DropdownMenuItem(
                                          value: n.id,
                                          child: Text('${n.id} (${n.ip} - ${n.role.toUpperCase()})'),
                                        )),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedNode = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Docker Compose YAML', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                      Row(
                                        children: [
                                          IconButton(
                                            tooltip: 'Copy YAML to clipboard',
                                            icon: const Icon(Icons.copy, size: 16),
                                            onPressed: () {
                                              ClipboardService.copy(_yamlController.text);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('YAML copied to clipboard'), duration: Duration(seconds: 2)),
                                              );
                                            },
                                          ),
                                          Tooltip(
                                            message: 'Upload Compose file from your workstation',
                                            child: TextButton.icon(
                                              onPressed: _pickFile,
                                              icon: const Icon(Icons.laptop, size: 15),
                                              label: const Text('My PC'),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Tooltip(
                                            message: 'Load Compose file from Master server filesystem (~/.gbnt/stacks/)',
                                            child: TextButton.icon(
                                              onPressed: _showServerStackPicker,
                                              icon: const Icon(Icons.dns, size: 15, color: Color(0xFF58A6FF)),
                                              label: const Text('Master Server', style: TextStyle(color: Color(0xFF58A6FF))),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Tooltip(
                                            message: 'Browse and load built-in production POC templates',
                                            child: TextButton.icon(
                                              onPressed: _showPOCExamples,
                                              icon: const Icon(Icons.rocket_launch, size: 15, color: Color(0xFFE3B341)),
                                              label: const Text('POC Blueprints', style: TextStyle(color: Color(0xFFE3B341))),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                ComposeSuggestionBar(controller: _yamlController),
                                Expanded(
                                  child: CodeTheme(
                                    data: CodeThemeData(styles: isDark ? monokaiSublimeTheme : githubTheme),
                                    child: Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      color: isDark ? const Color(0xFF272822) : const Color(0xFFF8F8F8),
                                      child: CodeField(
                                        controller: _yamlController,
                                        textStyle: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                                        expands: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildCopilotPanel(theme),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),
              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.surface,
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
                                      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
                                    ),
                                  );
                                }
                              }
                            },
                      icon: _deploying
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
