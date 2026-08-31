import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/yaml.dart';

import 'compose_autocomplete.dart';
import '../models/models.dart';
import '../utils/clipboard_service.dart';

class ComposeEditorDialog extends StatefulWidget {
  final String stackName;
  final String composeYaml;
  final List<Node> nodes;
  final Future<bool> Function(String yaml) onSave;
  final Future<bool> Function(String yaml)? onRedeploy;

  const ComposeEditorDialog({
    super.key,
    required this.stackName,
    required this.composeYaml,
    required this.nodes,
    required this.onSave,
    this.onRedeploy,
  });

  @override
  State<ComposeEditorDialog> createState() => _ComposeEditorDialogState();
}

class _ComposeEditorDialogState extends State<ComposeEditorDialog> {
  late CodeController _controller;
  late String _originalYaml;
  bool _saving = false;
  bool _redeploying = false;
  String _activeTab = 'caddy';
  final FocusNode _editorFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _originalYaml = widget.composeYaml;
    _controller = CodeController(
      text: widget.composeYaml,
      language: yaml,
    );
  }

  void _handleCopy({bool forceAll = false}) {
    String textToCopy = '';
    final sel = _controller.selection;
    if (!forceAll && !sel.isCollapsed && sel.isValid && sel.start >= 0 && sel.end <= _controller.text.length) {
      textToCopy = _controller.text.substring(sel.start, sel.end);
    } else {
      textToCopy = _controller.text;
    }

    if (textToCopy.isEmpty) return;

    ClipboardService.copy(textToCopy);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  textToCopy == _controller.text
                      ? 'Copied entire YAML (${textToCopy.length} chars) to clipboard'
                      : 'Copied selection (${textToCopy.length} chars) to clipboard',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          width: 400,
        ),
      );
    }
  }

  void _handleCut() {
    final sel = _controller.selection;
    if (!sel.isCollapsed && sel.isValid && sel.start >= 0 && sel.end <= _controller.text.length) {
      final selected = _controller.text.substring(sel.start, sel.end);
      ClipboardService.copy(selected);
      final text = _controller.text;
      final newText = text.substring(0, sel.start) + text.substring(sel.end);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cut selection to clipboard'),
            duration: Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
            width: 280,
          ),
        );
      }
    }
  }

  Future<void> _handlePaste() async {
    final pasted = await ClipboardService.paste();
    if (pasted != null && pasted.isNotEmpty) {
      final sel = _controller.selection;
      final text = _controller.text;
      final start = (sel.isValid && sel.start >= 0) ? sel.start : text.length;
      final end = (sel.isValid && sel.end >= 0) ? sel.end : text.length;
      final newText = text.substring(0, start) + pasted + text.substring(end);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + pasted.length),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pasted ${pasted.length} characters'),
            duration: const Duration(milliseconds: 1000),
            behavior: SnackBarBehavior.floating,
            width: 260,
          ),
        );
      }
    }
  }

  void _handleSelectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _editorFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _injectLabel(String labelKey, String labelValue) {
    // Basic injection logic for demonstration
    // We append the label at the current cursor position or end of file
    final text = _controller.text;
    final pos = _controller.selection.baseOffset;
    
    final injection = '        - $labelKey=$labelValue\n';
    
    if (pos >= 0 && pos <= text.length) {
      _controller.text = text.substring(0, pos) + injection + text.substring(pos);
      _controller.selection = TextSelection.collapsed(offset: pos + injection.length);
    } else {
      _controller.text = text + '\n' + injection;
    }
  }

  void _injectVolume() {
     final injection = '      - /var/contenedores/\${STACK_NAME}/data:/data\n';
     final pos = _controller.selection.baseOffset;
     final text = _controller.text;
     if (pos >= 0 && pos <= text.length) {
      _controller.text = text.substring(0, pos) + injection + text.substring(pos);
      _controller.selection = TextSelection.collapsed(offset: pos + injection.length);
    } else {
      _controller.text = text + '\n' + injection;
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
                      _injectLabel('gbnt.caddy.port', '8080');
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
                  const Text('Enforce cryptographic signatures or block vulnerable images for this specific service.', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                        // Note: actual placement constraint is not a label, but standard compose:
                        // deploy.placement.constraints: [node.hostname == my-node]
                        final text = _controller.text;
                        final pos = _controller.selection.baseOffset;
                        final injection = '      placement:\n        constraints:\n          - "node.hostname==${n.id}"\n';
                        if (pos >= 0 && pos <= text.length) {
                          _controller.text = text.substring(0, pos) + injection + text.substring(pos);
                        } else {
                          _controller.text = text + '\n' + injection;
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
                      'Advanced Editor: ${widget.stackName}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy YAML to clipboard',
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      ClipboardService.copy(_controller.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('YAML copied to clipboard'), duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Main Editor + Copilot Panel
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Editor
                  Expanded(
                    child: Column(
                      children: [
                        // Editor Quick Toolbar
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E2228) : const Color(0xFFE2E8F0),
                            border: Border(
                              bottom: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
                            ),
                          ),
                          child: Row(
                            children: [
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Colors.cyan.withValues(alpha: 0.2),
                                  foregroundColor: Colors.cyanAccent,
                                ),
                                icon: const Icon(Icons.content_copy, size: 14),
                                label: const Text('Copy Selection (Ctrl+C)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: () => _handleCopy(forceAll: false),
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.copy_all, size: 14),
                                label: const Text('Copy All YAML', style: TextStyle(fontSize: 11)),
                                onPressed: () => _handleCopy(forceAll: true),
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.paste, size: 14),
                                label: const Text('Paste (Ctrl+V)', style: TextStyle(fontSize: 11)),
                                onPressed: _handlePaste,
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.select_all, size: 14),
                                label: const Text('Select All (Ctrl+A)', style: TextStyle(fontSize: 11)),
                                onPressed: _handleSelectAll,
                              ),
                            ],
                          ),
                        ),
                        ComposeSuggestionBar(controller: _controller),
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: <ShortcutActivator, VoidCallback>{
                              const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => _handleCopy(forceAll: false),
                              const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () => _handleCopy(forceAll: false),
                              const SingleActivator(LogicalKeyboardKey.keyV, control: true): _handlePaste,
                              const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _handlePaste,
                              const SingleActivator(LogicalKeyboardKey.keyX, control: true): _handleCut,
                              const SingleActivator(LogicalKeyboardKey.keyX, meta: true): _handleCut,
                              const SingleActivator(LogicalKeyboardKey.keyA, control: true): _handleSelectAll,
                              const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _handleSelectAll,
                            },
                            child: CodeTheme(
                              data: CodeThemeData(styles: isDark ? monokaiSublimeTheme : githubTheme),
                              child: Container(
                                width: double.infinity,
                                height: double.infinity,
                                color: isDark ? const Color(0xFF272822) : const Color(0xFFF8F8F8),
                                child: CodeField(
                                  controller: _controller,
                                  focusNode: _editorFocusNode,
                                  textStyle: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                                  expands: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Copilot Panel
                  _buildCopilotPanel(theme),
                ],
              ),
            ),

            const Divider(height: 1),
            // Actions
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              color: theme.colorScheme.surface,
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
                            final ok = await widget.onSave(_controller.text);
                            setState(() => _saving = false);
                            if (ok && context.mounted) {
                              _originalYaml = _controller.text;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Compose saved successfully')),
                              );
                            }
                          },
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Save'),
                  ),
                  if (widget.onRedeploy != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _redeploying
                          ? null
                          : () async {
                              setState(() => _redeploying = true);
                              await widget.onSave(_controller.text);
                              final ok = await widget.onRedeploy!(_controller.text);
                              setState(() => _redeploying = false);
                              if (ok && context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Stack redeployed!')),
                                );
                              }
                            },
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD29922)),
                      icon: _redeploying
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.rocket_launch, size: 18),
                      label: const Text('Save & Redeploy'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
