import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Modal dialog for authoring Dockerfiles and building Docker images in The Imperial Forge
class ImageBuildDialog extends StatefulWidget {
  final String? initialDockerfile;
  final String? initialTag;
  final String? initialNodeId;
  final VoidCallback? onBuildSuccess;
  final Function(String tag)? onOpenInComposeStudio;

  const ImageBuildDialog({
    super.key,
    this.initialDockerfile,
    this.initialTag,
    this.initialNodeId,
    this.onBuildSuccess,
    this.onOpenInComposeStudio,
  });

  @override
  State<ImageBuildDialog> createState() => _ImageBuildDialogState();
}

class _ImageBuildDialogState extends State<ImageBuildDialog> {
  final _tagCtrl = TextEditingController();
  final _dockerfileCtrl = TextEditingController();
  String _selectedNode = 'manager';
  bool _noCache = false;

  // Build Arguments
  final List<MapEntry<TextEditingController, TextEditingController>> _buildArgs = [];

  // Execution state
  bool _building = false;
  ImageBuildResultModel? _buildResult;
  List<String> _liveLogs = [];

  // Available cluster nodes
  List<Node> _nodes = [];
  bool _loadingNodes = true;

  @override
  void initState() {
    super.initState();
    _tagCtrl.text = widget.initialTag ?? 'my-custom-app:v1.0';
    _dockerfileCtrl.text = widget.initialDockerfile ?? _defaultAlpineTemplate;
    if (widget.initialNodeId != null && widget.initialNodeId!.isNotEmpty) {
      _selectedNode = widget.initialNodeId!;
    }
    _fetchNodes();
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _dockerfileCtrl.dispose();
    for (final pair in _buildArgs) {
      pair.key.dispose();
      pair.value.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchNodes() async {
    try {
      final state = await ApiService.fetchState();
      if (mounted) {
        setState(() {
          _nodes = state.nodes;
          _loadingNodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNodes = false);
    }
  }

  void _applyTemplate(String template, String defaultTag) {
    setState(() {
      _dockerfileCtrl.text = template;
      if (_tagCtrl.text.isEmpty || _tagCtrl.text == 'my-custom-app:v1.0') {
        _tagCtrl.text = defaultTag;
      }
    });
  }

  void _addBuildArg() {
    setState(() {
      _buildArgs.add(MapEntry(TextEditingController(), TextEditingController()));
    });
  }

  void _removeBuildArg(int idx) {
    setState(() {
      final pair = _buildArgs.removeAt(idx);
      pair.key.dispose();
      pair.value.dispose();
    });
  }

  Future<void> _executeBuild() async {
    final tag = _tagCtrl.text.trim();
    final dockerfile = _dockerfileCtrl.text.trim();

    if (tag.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify a target image tag')),
      );
      return;
    }
    if (dockerfile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dockerfile content cannot be empty')),
      );
      return;
    }

    final buildArgsMap = <String, String>{};
    for (final pair in _buildArgs) {
      final k = pair.key.text.trim();
      final v = pair.value.text.trim();
      if (k.isNotEmpty) {
        buildArgsMap[k] = v;
      }
    }

    setState(() {
      _building = true;
      _buildResult = null;
      _liveLogs = [
        '🚀 [The Imperial Forge] Dispatching build task for $tag to node $_selectedNode...',
        '📦 Packaging Dockerfile context...',
      ];
    });

    try {
      final res = await ApiService.buildDockerImage(
        tag: tag,
        dockerfile: dockerfile,
        node: _selectedNode,
        buildArgs: buildArgsMap,
        noCache: _noCache,
      );

      if (mounted) {
        setState(() {
          _building = false;
          _buildResult = res;
          _liveLogs = res.logs;
        });

        if (res.success) {
          // Trigger security scan in background
          ApiService.triggerImageScan(tag).catchError((_) => null);
          if (widget.onBuildSuccess != null) {
            widget.onBuildSuccess!();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _building = false;
          _liveLogs.add('❌ Build execution encountered error: $e');
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
            child: const Icon(Icons.build_circle_outlined, color: Color(0xFFF97316), size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The Imperial Forge — Dockerfile Image Builder',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Author, customize, and compile container images across Centurion cluster nodes',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 12),

              // Target Node & Tag Row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Target Centurion Node:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedNode,
                              items: [
                                const DropdownMenuItem(value: 'manager', child: Text('👑 Manager (Local Host)')),
                                for (final n in _nodes.where((n) => n.role != 'manager'))
                                  DropdownMenuItem(value: n.id, child: Text('💻 Centurion ${n.id} (${n.ip})')),
                              ],
                              onChanged: _building ? null : (val) => setState(() => _selectedNode = val ?? 'manager'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Target Image Tag:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _tagCtrl,
                          enabled: !_building,
                          decoration: InputDecoration(
                            hintText: 'e.g. my-app:v1.0 or postgres:16-custom',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Starter Blueprints
              Row(
                children: [
                  const Text('Starter Blueprints:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 8),
                  _templateChip('Alpine Minimal', () => _applyTemplate(_defaultAlpineTemplate, 'alpine-custom:latest')),
                  const SizedBox(width: 6),
                  _templateChip('Go Microservice', () => _applyTemplate(_defaultGoTemplate, 'go-service:v1.0')),
                  const SizedBox(width: 6),
                  _templateChip('Node.js API', () => _applyTemplate(_defaultNodeTemplate, 'node-app:v1.0')),
                  const SizedBox(width: 6),
                  _templateChip('Python FastAPI', () => _applyTemplate(_defaultPythonTemplate, 'python-fastapi:v1.0')),
                ],
              ),
              const SizedBox(height: 10),

              // Dockerfile Editor
              const Text('Dockerfile Source:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 4),
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF090D16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: TextField(
                  controller: _dockerfileCtrl,
                  enabled: !_building,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: Color(0xFFE2E8F0),
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(12),
                    border: InputBorder.none,
                    hintText: 'FROM ...\nRUN ...',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Options & Build Args
              Row(
                children: [
                  Checkbox(
                    value: _noCache,
                    onChanged: _building ? null : (val) => setState(() => _noCache = val ?? false),
                  ),
                  const Text('Force Clean Build (--no-cache)', style: TextStyle(fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Build Arg', style: TextStyle(fontSize: 12)),
                    onPressed: _building ? null : _addBuildArg,
                  ),
                ],
              ),

              if (_buildArgs.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (int i = 0; i < _buildArgs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buildArgs[i].key,
                            enabled: !_building,
                            decoration: const InputDecoration(
                              labelText: 'Arg Name (e.g. VERSION)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _buildArgs[i].value,
                            enabled: !_building,
                            decoration: const InputDecoration(
                              labelText: 'Arg Value (e.g. 1.2.3)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                          onPressed: _building ? null : () => _removeBuildArg(i),
                        ),
                      ],
                    ),
                  ),
              ],

              // Live Build Console
              if (_liveLogs.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.terminal, size: 16, color: Colors.blueAccent),
                    SizedBox(width: 6),
                    Text('Compilation Terminal Logs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 140,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _buildResult != null
                          ? (_buildResult!.success ? const Color(0xFF10B981) : Colors.redAccent)
                          : Colors.blueAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListView.builder(
                    itemCount: _liveLogs.length,
                    itemBuilder: (ctx, idx) {
                      final line = _liveLogs[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: line.contains('Successfully built') || line.contains('writing image')
                                ? const Color(0xFF10B981)
                                : line.contains('error') || line.contains('Error') || line.contains('FAILED')
                                    ? Colors.redAccent
                                    : Colors.white70,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_buildResult != null && _buildResult!.success && widget.onOpenInComposeStudio != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.layers_outlined, size: 16),
            label: const Text('Deploy in Compose Studio'),
            onPressed: () {
              Navigator.pop(context);
              widget.onOpenInComposeStudio!(_tagCtrl.text.trim());
            },
          ),
        TextButton(
          onPressed: _building ? null : () => Navigator.pop(context),
          child: Text(_buildResult != null ? 'Close' : 'Cancel'),
        ),
        FilledButton.icon(
          icon: _building
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.flash_on, size: 16),
          label: Text(_building ? 'Compiling Image...' : 'Build Image in Forge'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF97316),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: _building ? null : _executeBuild,
        ),
      ],
    );
  }

  Widget _templateChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: _building ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
      ),
    );
  }

  static const String _defaultAlpineTemplate = '''# Alpine Hardened Base Image
FROM alpine:3.20

# Install dependencies and security patches
RUN apk update && \\
    apk add --no-cache ca-certificates curl tzdata && \\
    rm -rf /var/cache/apk/*

# Create non-root user for container security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

WORKDIR /app

CMD ["sh"]
''';

  static const String _defaultGoTemplate = '''# Multi-stage Go Binary Build
FROM golang:1.22-alpine AS builder

WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app-binary .

# Final minimal scratch runtime
FROM alpine:3.20
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app-binary .

EXPOSE 8080
ENTRYPOINT ["./app-binary"]
''';

  static const String _defaultNodeTemplate = '''# Production Node.js Runtime
FROM node:20-alpine

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

USER node
EXPOSE 3000
CMD ["node", "index.js"]
''';

  static const String _defaultPythonTemplate = '''# FastAPI Python Application
FROM python:3.11-alpine

WORKDIR /code

COPY requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

COPY . /code

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
''';
}
