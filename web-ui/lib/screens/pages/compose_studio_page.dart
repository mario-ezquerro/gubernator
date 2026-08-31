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
''',
    'Gatekeeper Signed App': '''services:
  secure-app:
    image: redis:alpine
    labels:
      - "gbnt.security.require-signature=true"
      - "gbnt.security.max-cve-severity=critical"
    deploy:
      replicas: 1
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
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M
      replicas: 1

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
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G
      replicas: 1

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
      resources:
        limits:
          memory: 6G
        reservations:
          memory: 1G
      replicas: 1

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
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G
      replicas: 1
''',
  };

  final FocusNode _editorFocusNode = FocusNode();
  String _lastSelectedText = '';
  TextSelection _lastSelection = const TextSelection.collapsed(offset: -1);

  @override
  void initState() {
    super.initState();
    _originalYaml = _defaultTemplate;
    _codeController = CodeController(
      text: _defaultTemplate,
      language: yaml,
    );
    _codeController.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() {
    final sel = _codeController.selection;
    if (!sel.isCollapsed && sel.start >= 0 && sel.end <= _codeController.text.length) {
      final text = _codeController.text.substring(sel.start, sel.end);
      if (text.isNotEmpty) {
        _lastSelection = sel;
        _lastSelectedText = text;
        if (mounted) setState(() {});
      }
    }
  }

  void _handleCopy({bool forceAll = false}) {
    String textToCopy = '';
    final sel = _codeController.selection;
    if (!forceAll && !sel.isCollapsed && sel.start >= 0 && sel.end <= _codeController.text.length) {
      textToCopy = _codeController.text.substring(sel.start, sel.end);
    } else if (!forceAll && _lastSelectedText.isNotEmpty) {
      textToCopy = _lastSelectedText;
    } else {
      textToCopy = _codeController.text;
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
                  textToCopy == _codeController.text
                      ? 'Copied entire YAML (${textToCopy.length} chars) to clipboard'
                      : 'Copied selection (${textToCopy.length} chars) to clipboard',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 420,
        ),
      );
    }
  }

  void _handleCut() {
    final sel = (!_codeController.selection.isCollapsed && _codeController.selection.isValid)
        ? _codeController.selection
        : (_lastSelection.isValid && !_lastSelection.isCollapsed ? _lastSelection : null);

    if (sel != null && sel.start >= 0 && sel.end <= _codeController.text.length) {
      final selected = _codeController.text.substring(sel.start, sel.end);
      ClipboardService.copy(selected);
      final text = _codeController.text;
      final newText = text.substring(0, sel.start) + text.substring(sel.end);
      _codeController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start),
      );
      _lastSelectedText = '';
      _lastSelection = const TextSelection.collapsed(offset: -1);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cut selection to clipboard'),
            duration: Duration(seconds: 1),
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
      final sel = _codeController.selection;
      final text = _codeController.text;
      final start = sel.start >= 0 ? sel.start : text.length;
      final end = sel.end >= 0 ? sel.end : text.length;
      final newText = text.substring(0, start) + pasted + text.substring(end);
      _codeController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + pasted.length),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pasted ${pasted.length} characters'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            width: 260,
          ),
        );
      }
    }
  }

  void _handleSelectAll() {
    _codeController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _codeController.text.length,
    );
    _lastSelection = _codeController.selection;
    _lastSelectedText = _codeController.text;
    _editorFocusNode.requestFocus();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _codeController.removeListener(_onSelectionChanged);
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
    final hasSelection = (!_codeController.selection.isCollapsed && _codeController.selection.isValid) || _lastSelectedText.isNotEmpty;
    final linesCount = '\n'.allMatches(_codeController.text).length + 1;
    final charsCount = _codeController.text.length;
    final selLength = !_codeController.selection.isCollapsed
        ? (_codeController.selection.end - _codeController.selection.start)
        : _lastSelectedText.length;

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
          // Metrics chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDark ? Colors.black38 : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, size: 13, color: Colors.cyanAccent),
                const SizedBox(width: 6),
                Text(
                  'YAML: $linesCount lines | $charsCount chars',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
                if (hasSelection) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'Selected: $selLength chars',
                      style: const TextStyle(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),

          // Copy Selection button (highlighted when text is selected)
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.tonalIcon(
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
            ),

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

                      // CodeField Area with Shortcuts
                      Expanded(
                        child: _loadingYaml
                            ? const Center(child: CircularProgressIndicator())
                            : CallbackShortcuts(
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
                                child: Focus(
                                  focusNode: _editorFocusNode,
                                  child: CodeTheme(
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
