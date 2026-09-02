import 'dart:async';
import 'dart:html' as html;
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
  String _lastSelectedText = '';
  TextSelection _lastSelection = const TextSelection.collapsed(offset: -1);

  // Native browser clipboard event handlers
  html.EventListener? _copyHandler;
  html.EventListener? _cutHandler;
  html.EventListener? _pasteHandler;
  html.EventListener? _keyDownHandler;
  StreamSubscription<html.Event>? _contextMenuSub;

  @override
  void initState() {
    super.initState();
    _originalYaml = widget.composeYaml;
    _controller = CodeController(
      text: widget.composeYaml,
      language: yaml,
    );
    _controller.addListener(_onCodeChanged);

    // Intercept native 'copy' event — clipboardData.setData() works on HTTP
    _copyHandler = (html.Event e) {
      if (e.target is html.TextAreaElement || e.target is html.InputElement) return;
      if (!mounted || !_editorFocusNode.hasFocus) return;
      e.preventDefault();
      final text = _getTextToCopy(forceAll: false);
      if (text.isNotEmpty) {
        (e as html.ClipboardEvent).clipboardData?.setData('text/plain', text);
        _showCopySnackbar(text);
      }
    };
    html.document.addEventListener('copy', _copyHandler!, true);

    // Intercept native 'cut' event
    _cutHandler = (html.Event e) {
      if (e.target is html.TextAreaElement || e.target is html.InputElement) return;
      if (!mounted || !_editorFocusNode.hasFocus) return;
      e.preventDefault();
      _handleCut(fromEvent: e as html.ClipboardEvent);
    };
    html.document.addEventListener('cut', _cutHandler!, true);

    // Intercept native 'paste' event — fires on Cmd+V (Mac) / Ctrl+V (Windows/Linux)
    _pasteHandler = (html.Event e) {
      if (e.target is html.TextAreaElement || e.target is html.InputElement) return;
      if (!mounted || !_editorFocusNode.hasFocus) return;
      final clipboardEvent = e as html.ClipboardEvent;
      final text = clipboardEvent.clipboardData?.getData('text/plain');
      if (text != null && text.isNotEmpty) {
        e.preventDefault();
        e.stopImmediatePropagation();
        _insertPastedText(text);
      }
    };
    html.document.addEventListener('paste', _pasteHandler!, true);

    // Keep keydown for Ctrl+A / Cmd+A
    _keyDownHandler = (html.Event e) => _onBrowserKeyDown(e as html.KeyboardEvent);
    html.document.addEventListener('keydown', _keyDownHandler!, true);
    _contextMenuSub = html.document.onContextMenu.listen(_onBrowserContextMenu);
  }

  void _onCodeChanged() {
    final sel = _controller.selection;
    if (sel.isValid && !sel.isCollapsed && sel.start >= 0 && sel.end <= _controller.text.length && sel.start < sel.end) {
      _lastSelection = sel;
      _lastSelectedText = _controller.text.substring(sel.start, sel.end);
    }
  }

  String _getTextToCopy({bool forceAll = false}) {
    if (forceAll) return _controller.text;
    final sel = _controller.selection;
    if (sel.isValid && !sel.isCollapsed && sel.start >= 0 && sel.end <= _controller.text.length && sel.start < sel.end) {
      return _controller.text.substring(sel.start, sel.end);
    }
    if (_lastSelectedText.isNotEmpty) return _lastSelectedText;
    return _controller.text;
  }

  void _showCopySnackbar(String text) {
    if (!mounted) return;
    final preview = text.length > 25 ? '${text.substring(0, 25)}...' : text;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            text == _controller.text
                ? '✓ Copied entire YAML (${text.length} chars)'
                : '✓ Copied (${text.length} chars): "$preview"',
            overflow: TextOverflow.ellipsis,
          )),
        ]),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        width: 440,
      ),
    );
  }

  // Keydown handler — only handles Ctrl+A / Cmd+A
  void _onBrowserKeyDown(html.KeyboardEvent event) {
    if (!mounted || !_editorFocusNode.hasFocus) return;
    final isCtrlOrMeta = event.ctrlKey || event.metaKey;
    if (!isCtrlOrMeta) return;
    final key = event.key?.toLowerCase() ?? '';
    switch (key) {
      case 'a':
        event.preventDefault();
        event.stopImmediatePropagation();
        _handleSelectAll();
        break;
    }
  }

  void _onBrowserContextMenu(html.Event event) {
    if (!mounted || !_editorFocusNode.hasFocus) return;
    event.preventDefault();
    final mouseEvent = event as html.MouseEvent;
    _showEditorContextMenu(Offset(
      mouseEvent.client.x.toDouble(),
      mouseEvent.client.y.toDouble(),
    ));
  }

  void _showEditorContextMenu(Offset position) {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final hasSelection = _lastSelectedText.isNotEmpty ||
        (_controller.selection.isValid && !_controller.selection.isCollapsed);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          enabled: hasSelection,
          child: const Row(children: [
            Icon(Icons.content_copy, size: 16),
            SizedBox(width: 8),
            Text('Copy Selection'),
            Spacer(),
            Text('Ctrl+C', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'copy_all',
          child: const Row(children: [
            Icon(Icons.copy_all, size: 16),
            SizedBox(width: 8),
            Text('Copy All YAML'),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'paste',
          child: const Row(children: [
            Icon(Icons.paste, size: 16),
            SizedBox(width: 8),
            Text('Paste'),
            Spacer(),
            Text('Ctrl+V', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'select_all',
          child: const Row(children: [
            Icon(Icons.select_all, size: 16),
            SizedBox(width: 8),
            Text('Select All'),
            Spacer(),
            Text('Ctrl+A', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy':
          _handleCopy(forceAll: false);
          break;
        case 'copy_all':
          _handleCopy(forceAll: true);
          break;
        case 'paste':
          _handlePaste();
          break;
        case 'select_all':
          _handleSelectAll();
          break;
      }
    });
  }

  void _handleCopy({bool forceAll = false}) {
    final textToCopy = _getTextToCopy(forceAll: forceAll);
    if (textToCopy.isEmpty) return;
    ClipboardService.copySync(textToCopy);
    ClipboardService.copy(textToCopy);
    _showCopySnackbar(textToCopy);
  }

  void _handleCut({html.ClipboardEvent? fromEvent}) {
    final sel = _controller.selection;
    TextSelection? targetSel;
    if (sel.isValid && !sel.isCollapsed && sel.start >= 0 && sel.end <= _controller.text.length && sel.start < sel.end) {
      targetSel = sel;
    } else if (_lastSelection.isValid && !_lastSelection.isCollapsed && _lastSelection.start >= 0 && _lastSelection.end <= _controller.text.length) {
      targetSel = _lastSelection;
    }
    if (targetSel != null) {
      final selected = _controller.text.substring(targetSel.start, targetSel.end);
      if (fromEvent != null) {
        fromEvent.clipboardData?.setData('text/plain', selected);
      } else {
        ClipboardService.copySync(selected);
        ClipboardService.copy(selected);
      }
      final text = _controller.text;
      final start = targetSel.start <= targetSel.end ? targetSel.start : targetSel.end;
      final end = targetSel.start <= targetSel.end ? targetSel.end : targetSel.start;
      final newText = text.substring(0, start) + text.substring(end);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
      _lastSelectedText = '';
      _lastSelection = const TextSelection.collapsed(offset: -1);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Cut selection to clipboard'),
            duration: Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
            width: 280,
          ),
        );
      }
    }
  }

  void _insertPastedText(String pasted) {
    if (pasted.isEmpty) return;
    final sel = _controller.selection;
    final text = _controller.text;
    final rawStart = (sel.isValid && sel.start >= 0) ? sel.start : ((_lastSelection.isValid && _lastSelection.start >= 0) ? _lastSelection.start : text.length);
    final rawEnd = (sel.isValid && sel.end >= 0) ? sel.end : ((_lastSelection.isValid && _lastSelection.end >= 0) ? _lastSelection.end : text.length);
    final start = rawStart <= rawEnd ? rawStart : rawEnd;
    final end = rawStart <= rawEnd ? rawEnd : rawStart;
    final newText = text.substring(0, start) + pasted + text.substring(end);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + pasted.length),
    );
    _lastSelectedText = '';
    _lastSelection = const TextSelection.collapsed(offset: -1);
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
                  '✓ Pasted ${pasted.length} characters into editor',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          width: 320,
        ),
      );
    }
  }

  Future<void> _handlePaste() async {
    final pasted = await ClipboardService.paste();
    if (pasted != null && pasted.isNotEmpty) {
      _insertPastedText(pasted);
      return;
    }

    if (mounted) {
      _showPasteModal();
    }
  }

  void _showPasteModal() {
    final pasteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2228),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.paste, color: Colors.cyanAccent, size: 20),
            SizedBox(width: 8),
            Text('Paste Content', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Direct clipboard reading via button is restricted on HTTP by browser security.\nPress Cmd+V (Mac) / Ctrl+V (Windows) in the box below:',
                style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pasteController,
                autofocus: true,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Press Cmd+V or Ctrl+V here...',
                  hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0D1117),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF30363D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyanAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.cyan),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Insert into Editor'),
            onPressed: () {
              final text = pasteController.text;
              Navigator.of(ctx).pop();
              if (text.isNotEmpty) {
                _insertPastedText(text);
              }
            },
          ),
        ],
      ),
    );
  }

  void _handleSelectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _lastSelection = _controller.selection;
    _lastSelectedText = _controller.text;
    _editorFocusNode.requestFocus();
  }

  @override
  void dispose() {
    if (_copyHandler != null) {
      html.document.removeEventListener('copy', _copyHandler!, true);
      _copyHandler = null;
    }
    if (_cutHandler != null) {
      html.document.removeEventListener('cut', _cutHandler!, true);
      _cutHandler = null;
    }
    if (_pasteHandler != null) {
      html.document.removeEventListener('paste', _pasteHandler!, true);
      _pasteHandler = null;
    }
    if (_keyDownHandler != null) {
      html.document.removeEventListener('keydown', _keyDownHandler!, true);
      _keyDownHandler = null;
    }
    _contextMenuSub?.cancel();
    _controller.removeListener(_onCodeChanged);
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
                _tabBtn('Resources', 'resources', Icons.speed),
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
                if (_activeTab == 'resources') ...[
                  const Text('CPU & RAM Resources', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Set CPU & RAM upper limits (limits) and guaranteed minimum reservations (reservations).', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      ComposeAutocomplete.insertSnippet(_controller, '    deploy:\n      resources:\n        limits:\n          cpus: "0.25"\n          memory: 128M\n        reservations:\n          cpus: "0.05"\n          memory: 32M\n');
                    },
                    icon: const Icon(Icons.bolt, color: Colors.amber),
                    label: const Text('⚡ Micro Service (0.25 CPU / 128M)'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      ComposeAutocomplete.insertSnippet(_controller, '    deploy:\n      resources:\n        limits:\n          cpus: "1.0"\n          memory: 512M\n        reservations:\n          cpus: "0.25"\n          memory: 128M\n');
                    },
                    icon: const Icon(Icons.web, color: Colors.blueAccent),
                    label: const Text('🌐 Standard Web App (1.0 CPU / 512M)'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      ComposeAutocomplete.insertSnippet(_controller, '    deploy:\n      resources:\n        limits:\n          cpus: "2.0"\n          memory: 2G\n        reservations:\n          cpus: "0.5"\n          memory: 512M\n');
                    },
                    icon: const Icon(Icons.storage, color: Colors.teal),
                    label: const Text('🗄️ Database / Cache (2.0 CPU / 2GB)'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      ComposeAutocomplete.insertSnippet(_controller, '    deploy:\n      resources:\n        limits:\n          cpus: "4.0"\n          memory: 8G\n        reservations:\n          cpus: "2.0"\n          memory: 2G\n');
                    },
                    icon: const Icon(Icons.smart_toy, color: Colors.purpleAccent),
                    label: const Text('🤖 AI / LLM Model (4.0 CPU / 8GB)'),
                  ),
                ],
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
