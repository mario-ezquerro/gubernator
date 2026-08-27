import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/yaml.dart';

import '../../models/models.dart' as models;
import '../../services/api_service.dart';
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
    image: hiyouga/llama-factory:latest
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
  };

  @override
  void initState() {
    super.initState();
    _originalYaml = _defaultTemplate;
    _codeController = CodeController(
      text: _defaultTemplate,
      language: yaml,
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
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

                // Stack Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStackId,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      items: [
                        const DropdownMenuItem(
                          value: 'new',
                          child: Row(
                            children: [
                              Icon(Icons.add_circle, color: Color(0xFF2EA043), size: 16),
                              SizedBox(width: 8),
                              Text('➕ Create New Stack', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        ...widget.state.stacks.map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Row(
                            children: [
                              const Icon(Icons.layers, size: 16, color: Color(0xFF58A6FF)),
                              const SizedBox(width: 8),
                              Text(s.name, style: const TextStyle(fontSize: 13)),
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
                const SizedBox(width: 8),

                // Import / Export
                IconButton(
                  tooltip: 'Load from file (.yml)',
                  icon: const Icon(Icons.upload_file),
                  onPressed: _importFile,
                ),
                IconButton(
                  tooltip: 'Export as YAML file',
                  icon: const Icon(Icons.download),
                  onPressed: _exportFile,
                ),
                const SizedBox(width: 8),

                // Reset Button
                OutlinedButton.icon(
                  onPressed: () => _codeController.text = _originalYaml,
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('Reset'),
                ),
                const SizedBox(width: 8),

                // Save Compose
                FilledButton.icon(
                  onPressed: _saving ? null : _saveCompose,
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 16),
                  label: const Text('Save Compose'),
                ),
                const SizedBox(width: 8),

                // Save & Deploy
                FilledButton.icon(
                  onPressed: _deploying ? null : _saveAndDeploy,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD29922)),
                  icon: _deploying
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.rocket_launch, size: 16),
                  label: Text(_selectedStackId == 'new' ? 'Deploy Stack' : 'Save & Redeploy'),
                ),
              ],
            ),
          ),

          // ─── Stack Parameters Bar ──────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  height: 38,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Stack Name',
                      prefixIcon: Icon(Icons.tag, size: 16),
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
                const Spacer(),
                Text(
                  _loadingYaml ? 'Loading YAML...' : '${_codeController.text.split('\n').length} lines',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),

          // ─── Main Editor & Copilot Split ───────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: Editor with Suggestion Bar
                Expanded(
                  child: Column(
                    children: [
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

                      // CodeField Area
                      Expanded(
                        child: _loadingYaml
                            ? const Center(child: CircularProgressIndicator())
                            : CodeTheme(
                                data: CodeThemeData(styles: isDark ? monokaiSublimeTheme : githubTheme),
                                child: Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: isDark ? const Color(0xFF272822) : const Color(0xFFF8F8F8),
                                  child: SingleChildScrollView(
                                    physics: const ClampingScrollPhysics(),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      physics: const ClampingScrollPhysics(),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(minWidth: 800),
                                        child: SelectionArea(
                                          child: CodeField(
                                            controller: _codeController,
                                            textStyle: const TextStyle(fontFamily: 'Courier New', fontSize: 13),
                                          ),
                                        ),
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
