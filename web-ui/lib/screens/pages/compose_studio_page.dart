import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/yaml.dart';

import '../../models/models.dart' as models;
import '../../services/api_service.dart';
import '../../utils/clipboard_service.dart';
import '../../widgets/compose_autocomplete.dart';

class ComposeStudioPage extends StatefulWidget {
  final models.DashboardState state;
  final VoidCallback onRefresh;

  const ComposeStudioPage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<ComposeStudioPage> createState() => _ComposeStudioPageState();
}

class _ComposeStudioPageState extends State<ComposeStudioPage> {
  late CodeController _codeController;
  final TextEditingController _nameController = TextEditingController(text: 'my-app');
  String _selectedStackId = 'new'; // 'new' or stack ID
  String _selectedNode = 'auto';
  String _activeCopilotTab = 'caddy';
  bool _saving = false;
  bool _deploying = false;
  bool _loadingYaml = false;
  String _originalYaml = '';

  String _customLimitCpu = '1.0';
  String _customLimitRam = '512M';
  String _customReserveCpu = '0.25';
  String _customReserveRam = '128M';

  static const String _defaultTemplate = '''services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    labels:
      - "ingress.host=app.gbnt.local"
      - "gbnt.caddy.port=80"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M
      placement:
        constraints:
          - "node.role == worker"
''';

  static const Map<String, String> _starterTemplates = {
    'Web Ingress': '''services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    labels:
      - "ingress.host=web.gbnt.local"
      - "gbnt.caddy.port=80"
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M
''',
    'Postgres Storage': '''services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: gubernator
      POSTGRES_PASSWORD: secretpassword
    volumes:
      - /var/contenedores/\${STACK_NAME}/pgdata:/var/lib/postgresql/data
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "2.0"
          memory: 2G
        reservations:
          cpus: "0.5"
          memory: 512M
''',
    'SRE Monitored Microservice': '''services:
  api:
    image: python:3.11-slim
    command: python -m http.server 8080
    ports:
      - "8080:8080"
    labels:
      - "ingress.host=api.gbnt.local"
      - "gbnt.caddy.port=8080"
      - "gbnt.slo.enable=true"
      - "gbnt.slo.target=99.9"
      - "gbnt.slo.window=30d"
      - "gbnt.slo.indicator=latency"
      - "gbnt.slo.latency.threshold=200ms"
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M
''',
    'Gatekeeper Signed App': '''services:
  secure-app:
    image: redis:alpine
    labels:
      - "gbnt.security.require-signature=true"
      - "gbnt.security.max-cve-severity=critical"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M
''',
    'GPU / AI Task': '''services:
  llm-worker:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - /var/contenedores/\${STACK_NAME}/models:/root/.ollama
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "4.0"
          memory: 8G
        reservations:
          cpus: "2.0"
          memory: 2G
      placement:
        constraints:
          - "gbnt.node.gpu == nvidia"
''',
    'JupyterLab PyTorch LLM': '''services:
  jupyter-llm:
    image: quay.io/jupyter/pytorch-notebook:latest
    container_name: jupyter_llm_lab
    restart: unless-stopped
    ports:
      - "127.0.0.1::8888"
    environment:
      - JUPYTER_TOKEN=gubernator-secret
      - JUPYTER_ENABLE_LAB=yes
    volumes:
      - /var/contenedores/jupyter-llm/work:/home/jovyan/work
      - /var/contenedores/jupyter-llm/hf_cache:/home/jovyan/.cache/huggingface
    labels:
      - "ingress.host=jupyter-llm.gbnt.local"
      - "gbnt.caddy.port=8888"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "4.0"
          memory: 8G
        reservations:
          cpus: "1.0"
          memory: 2G
''',
    'LLaMA-Factory Studio': '''services:
  llama-factory:
    image: hiyouga/llamafactory:latest
    container_name: llama_factory_studio
    restart: unless-stopped
    ports:
      - "127.0.0.1::7860"
    environment:
      - GRADIO_SERVER_NAME=0.0.0.0
      - GRADIO_SERVER_PORT=7860
    volumes:
      - /var/contenedores/llama-factory/data:/app/data
      - /var/contenedores/llama-factory/saves:/app/saves
      - /var/contenedores/llama-factory/output:/app/output
      - /var/contenedores/llama-factory/hf_cache:/root/.cache/huggingface
    labels:
      - "ingress.host=llama-factory.gbnt.local"
      - "gbnt.caddy.port=7860"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "4.0"
          memory: 12G
        reservations:
          cpus: "1.0"
          memory: 4G
''',
    'Kubeflow MLOps Platform': '''services:
  minio:
    image: minio/minio:latest
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=kubeflow
      - MINIO_ROOT_PASSWORD=gubernator123
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - /var/contenedores/kubeflow/minio_data:/data
    labels:
      - "ingress.host=minio.kubeflow.gbnt.local"
      - "gbnt.caddy.port=9001"
      - "gbnt.service.name=minio-s3"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "1.0"
          memory: 2G
        reservations:
          cpus: "0.25"
          memory: 512M

  mlflow:
    image: ghcr.io/mlflow/mlflow:latest
    restart: unless-stopped
    command: mlflow server --host 0.0.0.0 --port 5000 --workers 1 --allowed-hosts "*" --backend-store-uri sqlite:////data/mlflow.db --default-artifact-root s3://mlflow-artifacts/
    environment:
      - AWS_ACCESS_KEY_ID=kubeflow
      - AWS_SECRET_ACCESS_KEY=gubernator123
      - MLFLOW_S3_ENDPOINT_URL=http://minio.kubeflow.gbnt.local
      - MLFLOW_S3_IGNORE_TLS=true
      - MLFLOW_ALLOWED_HOSTS=*
    ports:
      - "5000:5000"
    volumes:
      - /var/contenedores/kubeflow/mlflow_data:/data
    labels:
      - "ingress.host=mlflow.kubeflow.gbnt.local"
      - "gbnt.caddy.port=5000"
      - "gbnt.service.name=mlflow-tracking"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "2.0"
          memory: 2G
        reservations:
          cpus: "0.5"
          memory: 512M

  jupyter-workspace:
    image: quay.io/jupyter/pytorch-notebook:latest
    restart: unless-stopped
    environment:
      - JUPYTER_TOKEN=gubernator-secret
      - JUPYTER_ENABLE_LAB=yes
      - AWS_ACCESS_KEY_ID=kubeflow
      - AWS_SECRET_ACCESS_KEY=gubernator123
      - MLFLOW_TRACKING_URI=http://mlflow.kubeflow.gbnt.local
      - MLFLOW_S3_ENDPOINT_URL=http://minio.kubeflow.gbnt.local
    ports:
      - "8888:8888"
    volumes:
      - /var/contenedores/kubeflow/workspaces:/home/jovyan/work
      - /var/contenedores/kubeflow/cache:/home/jovyan/.cache
    labels:
      - "ingress.host=notebooks.kubeflow.gbnt.local"
      - "gbnt.caddy.port=8888"
      - "gbnt.service.name=jupyterlab"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "2.0"
          memory: 4G
        reservations:
          cpus: "0.5"
          memory: 1G

  inference-engine:
    image: ollama/ollama:latest
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - /var/contenedores/kubeflow/models:/root/.ollama
    labels:
      - "ingress.host=inference.kubeflow.gbnt.local"
      - "gbnt.caddy.port=11434"
      - "gbnt.service.name=model-serving"
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: "2.0"
          memory: 4G
        reservations:
          cpus: "0.5"
          memory: 1G
''',
  };

  final FocusNode _editorFocusNode = FocusNode();
  String _lastSelectedText = '';
  TextSelection _lastSelection = const TextSelection.collapsed(offset: -1);

  // Native browser clipboard event handlers — most reliable approach for HTTP
  html.EventListener? _copyHandler;
  html.EventListener? _cutHandler;
  html.EventListener? _pasteHandler;
  html.EventListener? _keyDownHandler;
  StreamSubscription<html.Event>? _contextMenuSub;

  @override
  void initState() {
    super.initState();
    _originalYaml = _defaultTemplate;
    _codeController = CodeController(
      text: _defaultTemplate,
      language: yaml,
    );
    _codeController.addListener(_onCodeChanged);

    // Intercept native browser 'copy' event — fires when Cmd+C/Ctrl+C is pressed
    // clipboardData.setData() works on HTTP without any permissions
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

    // Intercept native browser 'cut' event
    _cutHandler = (html.Event e) {
      if (e.target is html.TextAreaElement || e.target is html.InputElement) return;
      if (!mounted || !_editorFocusNode.hasFocus) return;
      e.preventDefault();
      _handleCut(fromEvent: e as html.ClipboardEvent);
    };
    html.document.addEventListener('cut', _cutHandler!, true);

    // Intercept native browser 'paste' event — fires when Cmd+V (Mac) or Ctrl+V (Windows/Linux) is pressed
    // clipboardData.getData('text/plain') works directly on plain HTTP without permissions
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

    // Keep keydown for Ctrl+A / Cmd+A (copy/cut/paste are handled by native clipboard events)
    _keyDownHandler = (html.Event e) => _onBrowserKeyDown(e as html.KeyboardEvent);
    html.document.addEventListener('keydown', _keyDownHandler!, true);

    // Intercept right-click context menu
    _contextMenuSub = html.document.onContextMenu.listen(_onBrowserContextMenu);
  }

  /// Captures selection changes into memory WITHOUT calling setState.
  void _onCodeChanged() {
    final sel = _codeController.selection;
    if (sel.isValid && !sel.isCollapsed && sel.start >= 0 && sel.end <= _codeController.text.length && sel.start < sel.end) {
      _lastSelection = sel;
      _lastSelectedText = _codeController.text.substring(sel.start, sel.end);
    }
  }

  /// Returns the text to copy — current selection or last remembered selection.
  String _getTextToCopy({bool forceAll = false}) {
    if (forceAll) return _codeController.text;
    final sel = _codeController.selection;
    if (sel.isValid && !sel.isCollapsed && sel.start >= 0 && sel.end <= _codeController.text.length && sel.start < sel.end) {
      return _codeController.text.substring(sel.start, sel.end);
    }
    if (_lastSelectedText.isNotEmpty) return _lastSelectedText;
    return _codeController.text;
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
            text == _codeController.text
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

  /// Keydown handler — only handles Ctrl+A / Cmd+A (copy/cut/paste are handled by native clipboard events).
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

  /// Browser right-click: prevent native context menu and show custom Flutter popup.
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
        (_codeController.selection.isValid && !_codeController.selection.isCollapsed);

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
    // Toolbar button copy — use DOM execCommand fallback since no clipboard event available
    ClipboardService.copySync(textToCopy);
    ClipboardService.copy(textToCopy);
    _showCopySnackbar(textToCopy);
  }

  void _handleCut({html.ClipboardEvent? fromEvent}) {
    final sel = _codeController.selection;
    TextSelection? targetSel;
    if (sel.isValid && !sel.isCollapsed && sel.start >= 0 && sel.end <= _codeController.text.length && sel.start < sel.end) {
      targetSel = sel;
    } else if (_lastSelection.isValid && !_lastSelection.isCollapsed && _lastSelection.start >= 0 && _lastSelection.end <= _codeController.text.length) {
      targetSel = _lastSelection;
    }

    if (targetSel != null) {
      final selected = _codeController.text.substring(targetSel.start, targetSel.end);
      // If triggered from native cut event, inject into event's clipboardData (works on HTTP)
      if (fromEvent != null) {
        fromEvent.clipboardData?.setData('text/plain', selected);
      } else {
        ClipboardService.copySync(selected);
        ClipboardService.copy(selected);
      }
      final text = _codeController.text;
      final start = targetSel.start <= targetSel.end ? targetSel.start : targetSel.end;
      final end = targetSel.start <= targetSel.end ? targetSel.end : targetSel.start;
      final newText = text.substring(0, start) + text.substring(end);
      _codeController.value = TextEditingValue(
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
    final sel = _codeController.selection;
    final text = _codeController.text;
    final rawStart = (sel.isValid && sel.start >= 0) ? sel.start : ((_lastSelection.isValid && _lastSelection.start >= 0) ? _lastSelection.start : text.length);
    final rawEnd = (sel.isValid && sel.end >= 0) ? sel.end : ((_lastSelection.isValid && _lastSelection.end >= 0) ? _lastSelection.end : text.length);
    final start = rawStart <= rawEnd ? rawStart : rawEnd;
    final end = rawStart <= rawEnd ? rawEnd : rawStart;
    final newText = text.substring(0, start) + pasted + text.substring(end);
    _codeController.value = TextEditingValue(
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

    // Fallback when browser blocks silent reading on plain HTTP
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
    _codeController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _codeController.text.length,
    );
    _lastSelection = _codeController.selection;
    _lastSelectedText = _codeController.text;
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
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _nameController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadStackYaml(String stackId) async {
    if (stackId == 'new') {
      setState(() {
        _selectedStackId = 'new';
        _nameController.text = 'my-app';
        _codeController.text = _defaultTemplate;
        _originalYaml = _defaultTemplate;
      });
      return;
    }

    final stack = widget.state.stacks.firstWhere((s) => s.id == stackId, orElse: () => widget.state.stacks.first);
    setState(() {
      _selectedStackId = stackId;
      _nameController.text = stack.name;
      _loadingYaml = true;
    });

    try {
      final yamlContent = await ApiService.getStackCompose(stack.id);
      if (mounted) {
        setState(() {
          _codeController.text = yamlContent;
          _originalYaml = yamlContent;
          _loadingYaml = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingYaml = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load stack compose: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyTemplate(String templateKey) {
    final snippet = _starterTemplates[templateKey];
    if (snippet != null) {
      setState(() {
        _codeController.text = snippet;
        _originalYaml = snippet;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied template: $templateKey')),
      );
    }
  }

  void _exportFile() {
    final name = _nameController.text.trim().isEmpty ? 'docker-compose' : _nameController.text.trim();
    final bytes = html.Blob([_codeController.text], 'text/yaml');
    final url = html.Url.createObjectUrlFromBlob(bytes);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', '$name.yml')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _importFile() {
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
            _codeController.text = text;
            if (_selectedStackId == 'new') {
              _nameController.text = sanitizedName;
            }
          });
        });

        reader.readAsText(file);
      }
    });
  }

  Future<void> _saveCompose() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Stack Name'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_selectedStackId == 'new') {
        // Deploy as new stack
        final error = await ApiService.deployStack(name, _codeController.text, targetNode: _selectedNode);
        if (error != null) {
          throw Exception(error);
        }
        widget.onRefresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stack "$name" deployed successfully!'), backgroundColor: Colors.green),
          );
        }
      } else {
        final ok = await ApiService.updateStackCompose(_selectedStackId, _codeController.text);
        if (!ok) throw Exception('Failed to update stack compose');
        _originalYaml = _codeController.text;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stack "$name" saved successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndDeploy() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Stack Name'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _deploying = true);
    try {
      if (_selectedStackId == 'new') {
        final error = await ApiService.deployStack(name, _codeController.text, targetNode: _selectedNode);
        if (error != null) throw Exception(error);
      } else {
        await ApiService.updateStackCompose(_selectedStackId, _codeController.text);
        final ok = await ApiService.redeployStack(_selectedStackId);
        if (!ok) throw Exception('Failed to redeploy stack');
      }
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stack "$name" deployed & started!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deployment error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  Widget _buildCopilotPanel(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Copilot Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Gubernator Copilot',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'SMART WIZARD',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tabBtn('Docker', 'docker', Icons.view_in_ar),
                _tabBtn('Resources', 'resources', Icons.speed),
                _tabBtn('Caddy', 'caddy', Icons.public),
                _tabBtn('SLO', 'slo', Icons.show_chart),
                _tabBtn('Security', 'security', Icons.security),
                _tabBtn('Nodes', 'nodes', Icons.memory),
                _tabBtn('Storage', 'storage', Icons.storage),
                _tabBtn('Templates', 'templates', Icons.dashboard_customize),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_activeCopilotTab == 'resources') ...[
                  const Text('CPU & RAM Resources', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Configure hard upper limits (limits) to prevent host starvation and minimum guaranteed reservations (reservations) for priority placement.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  
                  const Text('1-Click Production Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildSnippetCard(
                    title: '⚡ Micro Service',
                    subtitle: 'Limit: 0.25 CPU / 128MB • Reserve: 0.05 CPU / 32MB',
                    icon: Icons.bolt,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      resources:\n        limits:\n          cpus: "0.25"\n          memory: 128M\n        reservations:\n          cpus: "0.05"\n          memory: 32M\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: '🌐 Standard Web / API App',
                    subtitle: 'Limit: 1.0 CPU / 512MB • Reserve: 0.25 CPU / 128MB',
                    icon: Icons.web,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      resources:\n        limits:\n          cpus: "1.0"\n          memory: 512M\n        reservations:\n          cpus: "0.25"\n          memory: 128M\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: '🗄️ Database & Cache',
                    subtitle: 'Limit: 2.0 CPU / 2GB • Reserve: 0.5 CPU / 512MB',
                    icon: Icons.storage,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      resources:\n        limits:\n          cpus: "2.0"\n          memory: 2G\n        reservations:\n          cpus: "0.5"\n          memory: 512M\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: '🧠 Data Science & ML',
                    subtitle: 'Limit: 4.0 CPU / 4GB • Reserve: 1.0 CPU / 1GB',
                    icon: Icons.science,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      resources:\n        limits:\n          cpus: "4.0"\n          memory: 4G\n        reservations:\n          cpus: "1.0"\n          memory: 1G\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: '🤖 AI / LLM Model Serving (GPU)',
                    subtitle: 'Limit: 4.0 CPU / 8GB • Reserve: 2.0 CPU / 2GB',
                    icon: Icons.smart_toy,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      resources:\n        limits:\n          cpus: "4.0"\n          memory: 8G\n        reservations:\n          cpus: "2.0"\n          memory: 2G\n');
                    },
                  ),

                  const Divider(height: 24),
                  const Text('Custom Resources Builder:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('MAX LIMITS (Hard Caps)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Max CPU:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  DropdownButtonFormField<String>(
                                    value: _customLimitCpu,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: ['0.25', '0.5', '1.0', '1.5', '2.0', '4.0', '8.0'].map((v) => DropdownMenuItem(value: v, child: Text('$v Core', style: const TextStyle(fontSize: 11)))).toList(),
                                    onChanged: (val) => setState(() => _customLimitCpu = val ?? '1.0'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Max RAM:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  DropdownButtonFormField<String>(
                                    value: _customLimitRam,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: ['128M', '256M', '512M', '1G', '2G', '4G', '8G', '16G', '32G'].map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 11)))).toList(),
                                    onChanged: (val) => setState(() => _customLimitRam = val ?? '512M'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('MIN RESERVATIONS (Guaranteed)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Min CPU:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  DropdownButtonFormField<String>(
                                    value: _customReserveCpu,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: ['0.05', '0.1', '0.25', '0.5', '1.0', '2.0'].map((v) => DropdownMenuItem(value: v, child: Text('$v Core', style: const TextStyle(fontSize: 11)))).toList(),
                                    onChanged: (val) => setState(() => _customReserveCpu = val ?? '0.25'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Min RAM:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  DropdownButtonFormField<String>(
                                    value: _customReserveRam,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: ['32M', '64M', '128M', '256M', '512M', '1G', '2G', '4G'].map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 11)))).toList(),
                                    onChanged: (val) => setState(() => _customReserveRam = val ?? '128M'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.add_task, size: 16),
                            label: const Text('Insert Custom Resources Block', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final snippet = '    deploy:\n      resources:\n        limits:\n          cpus: "$_customLimitCpu"\n          memory: $_customLimitRam\n        reservations:\n          cpus: "$_customReserveCpu"\n          memory: $_customReserveRam\n';
                              ComposeAutocomplete.insertSnippet(_codeController, snippet);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_activeCopilotTab == 'docker') ...[
                  const Text('Docker Copilot Options', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Inject essential Docker Compose blocks: ports, volumes, resource limits, restart policies, and environment overrides.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  _buildSnippetCard(
                    title: 'HTTP & HTTPS Ports (80, 443)',
                    subtitle: 'Standard web ingress port bindings',
                    icon: Icons.input,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    ports:\n      - "80:80"\n      - "443:443"\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Database Port 5432 (Postgres)',
                    subtitle: 'Expose PostgreSQL database port',
                    icon: Icons.storage,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    ports:\n      - "5432:5432"\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Persistent Volume Mount',
                    subtitle: '/var/contenedores/\${STACK_NAME}/data:/data',
                    icon: Icons.folder_special,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    volumes:\n      - /var/contenedores/\${STACK_NAME}/data:/data\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Read-Only Config Mount',
                    subtitle: './config.yml:/etc/app/config.yml:ro',
                    icon: Icons.insert_drive_file,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    volumes:\n      - ./config.yml:/etc/app/config.yml:ro\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Resource Limits (RAM 1GB / CPU 1.5)',
                    subtitle: 'Prevent container from starving host resources',
                    icon: Icons.speed,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      resources:\n        limits:\n          cpus: "1.5"\n          memory: 1G\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Restart Policy: unless-stopped',
                    subtitle: 'Auto-restart container on host reboot',
                    icon: Icons.autorenew,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    restart: unless-stopped\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Environment Variables Block',
                    subtitle: 'Define NODE_ENV, LOG_LEVEL, and credentials',
                    icon: Icons.tune,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    environment:\n      - NODE_ENV=production\n      - LOG_LEVEL=info\n      - DB_HOST=db\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Container Healthcheck Probe',
                    subtitle: 'HTTP healthcheck every 10 seconds',
                    icon: Icons.favorite,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    healthcheck:\n      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]\n      interval: 10s\n      timeout: 5s\n      retries: 3\n');
                    },
                  ),
                ],

                if (_activeCopilotTab == 'caddy') ...[
                  const Text('Caddy Ingress Suite', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Expose your service via Caddy proxy with CoreDNS automatic resolution.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  _buildSnippetCard(
                    title: 'Standard HTTP Ingress',
                    subtitle: 'ingress.host=app.gbnt.local & port=80',
                    icon: Icons.public,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    labels:\n      - "ingress.host=app.gbnt.local"\n      - "gbnt.caddy.port=80"\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Internal TLS Ingress',
                    subtitle: 'Automatic Caddy internal certificate',
                    icon: Icons.lock,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    labels:\n      - "ingress.host=secure.gbnt.local"\n      - "gbnt.caddy.port=443"\n      - "gbnt.caddy.tls=internal"\n');
                    },
                  ),
                ],

                if (_activeCopilotTab == 'slo') ...[
                  const Text('SLO Engine (Sloth Alerts)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Inject Google SRE Multi-Burn-Rate alerting rules and error budgets.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  _buildSnippetCard(
                    title: '99.9% High Availability SLO',
                    subtitle: '30-day window availability budget',
                    icon: Icons.speed,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    labels:\n      - "gbnt.slo.enable=true"\n      - "gbnt.slo.target=99.9"\n      - "gbnt.slo.window=30d"\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Latency < 200ms Threshold',
                    subtitle: 'Triggers multi-burn alerts on slow requests',
                    icon: Icons.timer,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    labels:\n      - "gbnt.slo.enable=true"\n      - "gbnt.slo.target=99.0"\n      - "gbnt.slo.indicator=latency"\n      - "gbnt.slo.latency.threshold=200ms"\n');
                    },
                  ),
                ],

                if (_activeCopilotTab == 'security') ...[
                  const Text('Security Gatekeeper & Cosign', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Enforce cryptographic signatures and CVE vulnerability policies.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  _buildSnippetCard(
                    title: 'Enforce Cryptographic Signatures',
                    subtitle: 'Blocks deployment if image is not Cosign-signed',
                    icon: Icons.verified_user,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    labels:\n      - "gbnt.security.require-signature=true"\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Block Critical CVE Vulnerabilities',
                    subtitle: 'Rejects images with unpatched critical CVEs',
                    icon: Icons.security,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    labels:\n      - "gbnt.security.max-cve-severity=critical"\n');
                    },
                  ),
                ],

                if (_activeCopilotTab == 'nodes') ...[
                  const Text('Node Placement & Centurions', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Pin service containers to specific hardware or active nodes.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  _buildSnippetCard(
                    title: 'Worker Nodes Only',
                    subtitle: 'node.role == worker constraint',
                    icon: Icons.alt_route,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      placement:\n        constraints:\n          - "node.role == worker"\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'NVIDIA GPU Accelerated Node',
                    subtitle: 'gbnt.node.gpu == nvidia constraint',
                    icon: Icons.developer_board,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      placement:\n        constraints:\n          - "gbnt.node.gpu == nvidia"\n');
                    },
                  ),
                  const Divider(height: 24),
                  const Text('Active Cluster Nodes:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...widget.state.nodes.map((node) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        node.role == 'manager' ? Icons.star : Icons.dns,
                        color: node.status == 'active' ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      title: Text(node.id, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      subtitle: Text('${node.ip} • ${node.role.toUpperCase()}', style: const TextStyle(fontSize: 10)),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        tooltip: 'Pin to ${node.id}',
                        onPressed: () {
                          ComposeAutocomplete.insertSnippet(_codeController, '    deploy:\n      placement:\n        constraints:\n          - "node.hostname == ${node.id}"\n');
                        },
                      ),
                    ),
                  )),
                ],

                if (_activeCopilotTab == 'storage') ...[
                  const Text('Storage Granaries (/var/contenedores)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Deploy shared storage mounts compatible with cluster-wide backups.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  _buildSnippetCard(
                    title: 'App Data Shared Mount',
                    subtitle: '/var/contenedores/\${STACK_NAME}/data:/data',
                    icon: Icons.storage,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    volumes:\n      - /var/contenedores/\${STACK_NAME}/data:/data\n');
                    },
                  ),
                  _buildSnippetCard(
                    title: 'Database Storage Pool',
                    subtitle: '/var/contenedores/\${STACK_NAME}/db:/var/lib/db',
                    icon: Icons.inventory_2,
                    onTap: () {
                      ComposeAutocomplete.insertSnippet(_codeController, '    volumes:\n      - /var/contenedores/\${STACK_NAME}/db:/var/lib/db\n');
                    },
                  ),
                ],

                if (_activeCopilotTab == 'templates') ...[
                  const Text('Starter Templates', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Click a template to load a production-ready Docker Compose blueprint.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ..._starterTemplates.keys.map((tName) => _buildSnippetCard(
                    title: tName,
                    subtitle: 'Load complete $tName compose file',
                    icon: Icons.layers,
                    onTap: () => _applyTemplate(tName),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnippetCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(String title, String id, IconData icon) {
    final active = _activeCopilotTab == id;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _activeCopilotTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            Icon(icon, size: 15, color: active ? theme.colorScheme.primary : Colors.grey),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? theme.colorScheme.primary : Colors.grey,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorActionBar(ThemeData theme, bool isDark) {
    return Container(
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDark ? Colors.black38 : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: const Row(
              children: [
                Icon(Icons.code, size: 13, color: Colors.cyanAccent),
                SizedBox(width: 6),
                Text(
                  'YAML Editor',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Spacer(),

          // Copy Selection button
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
              backgroundColor: Colors.cyan.withValues(alpha: 0.2),
              foregroundColor: Colors.cyanAccent,
            ),
            icon: const Icon(Icons.content_copy, size: 14),
            label: const Text('Copy Selection (Ctrl+C)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () => _handleCopy(forceAll: false),
          ),
          const SizedBox(width: 6),

          // Copy All YAML
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

          // Paste
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

          // Select All
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Header & Toolbar ──────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.code, color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Compose Studio',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'IDE & COPILOT',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Author, edit, validate, and deploy Docker Compose stacks with smart suggestions.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const Spacer(),

                // Stack Selector Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStackId,
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      items: [
                        const DropdownMenuItem(
                          value: 'new',
                          child: Row(
                            children: [
                              Icon(Icons.add_box, size: 16, color: Colors.blueAccent),
                              SizedBox(width: 8),
                              Text('✨ Create New Stack'),
                            ],
                          ),
                        ),
                        ...widget.state.stacks.map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Row(
                            children: [
                              const Icon(Icons.layers, size: 16, color: Colors.orangeAccent),
                              const SizedBox(width: 8),
                              Text('Stack: ${s.name}'),
                            ],
                          ),
                        )),
                      ],
                      onChanged: (val) {
                        if (val != null) _loadStackYaml(val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Starters Templates Menu
                PopupMenuButton<String>(
                  tooltip: 'Load Blueprint Template',
                  onSelected: _applyTemplate,
                  itemBuilder: (context) => _starterTemplates.keys.map((title) => PopupMenuItem(
                    value: title,
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 16, color: Colors.cyanAccent),
                        const SizedBox(width: 8),
                        Text(title),
                      ],
                    ),
                  )).toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.widgets_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('Blueprints', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Reset YAML Button
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset'),
                  onPressed: () {
                    setState(() {
                      _codeController.text = _originalYaml;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('YAML reset to original'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                const SizedBox(width: 10),

                // Save Stack Button
                OutlinedButton.icon(
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save, size: 16),
                  label: const Text('Save Stack'),
                  onPressed: _saving ? null : _saveCompose,
                ),
                const SizedBox(width: 10),

                // Save & Deploy Button
                FilledButton.icon(
                  icon: _deploying
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.rocket_launch, size: 16),
                  label: Text(_selectedStackId == 'new' ? 'Deploy Stack' : 'Save & Redeploy'),
                  onPressed: _deploying ? null : _saveAndDeploy,
                ),
              ],
            ),
          ),

          // Secondary Bar: Stack Name & Node Placement
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  height: 38,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Stack Name',
                      prefixIcon: Icon(Icons.label_outline, size: 16),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 320,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    value: _selectedNode,
                    decoration: const InputDecoration(
                      labelText: 'Target Placement Node',
                      prefixIcon: Icon(Icons.memory, size: 16),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    style: const TextStyle(fontSize: 13),
                    items: [
                      const DropdownMenuItem(value: 'auto', child: Text('Automatic Scheduler (Spread / Least Loaded)')),
                      ...widget.state.nodes.where((n) => n.status == 'active').map((n) => DropdownMenuItem(
                        value: n.id,
                        child: Text('${n.id} (${n.ip} - ${n.role.toUpperCase()})'),
                      )),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedNode = val);
                    },
                  ),
                ),
              ],
            ),
          ),

          // ─── Main Editor & Copilot Split ───────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: Editor with Action Bar & Suggestion Bar
                Expanded(
                  child: Column(
                    children: [
                      // Editor Action Bar
                      _buildEditorActionBar(theme, isDark),

                      // Suggestion Bar
                      ComposeSuggestionBar(
                        controller: _codeController,
                        onSnippetInserted: (label) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Inserted $label snippet'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      ),

                      // CodeField Area — keyboard shortcuts handled via raw browser DOM listeners
                      Expanded(
                        child: _loadingYaml
                            ? const Center(child: CircularProgressIndicator())
                            : CodeTheme(
                                data: CodeThemeData(styles: isDark ? monokaiSublimeTheme : githubTheme),
                                child: Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: isDark ? const Color(0xFF272822) : const Color(0xFFF8F8F8),
                                  child: CodeField(
                                    controller: _codeController,
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

                // Right: Copilot Panel
                _buildCopilotPanel(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
