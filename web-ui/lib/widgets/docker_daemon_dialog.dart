import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class DockerDaemonDialog extends StatefulWidget {
  final DashboardState state;
  final String? initialNodeId;
  final VoidCallback onConfigApplied;

  const DockerDaemonDialog({
    super.key,
    required this.state,
    this.initialNodeId,
    required this.onConfigApplied,
  });

  @override
  State<DockerDaemonDialog> createState() => _DockerDaemonDialogState();
}

class _DockerDaemonDialogState extends State<DockerDaemonDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  // Targeting Scope
  String _targetScope = 'all'; // all, gpu, manager, node
  String? _selectedNodeId;

  // Form Fields
  bool _liveRestore = true;
  String _logDriver = 'json-file';
  String _logMaxSize = '20m';
  String _logMaxFile = '3';

  // Network & DNS
  final TextEditingController _dnsController = TextEditingController(text: '1.1.1.1, 8.8.8.8');
  final TextEditingController _dnsSearchController = TextEditingController();
  final TextEditingController _bipController = TextEditingController();
  final TextEditingController _addrPoolBaseController = TextEditingController(text: '10.200.0.0/16');
  final TextEditingController _addrPoolSizeController = TextEditingController(text: '24');
  bool _icc = true;
  bool _ipForward = true;
  bool _iptables = true;

  // Registries
  final TextEditingController _insecureRegsController = TextEditingController();
  final TextEditingController _regMirrorsController = TextEditingController();

  // GPU & Runtimes
  bool _enableNvidia = false;
  String _defaultRuntime = 'runc';
  final TextEditingController _nvidiaPathController = TextEditingController(text: 'nvidia-container-runtime');

  // Metrics & Storage
  bool _enableMetrics = false;
  final TextEditingController _metricsAddrController = TextEditingController(text: '0.0.0.0:9323');
  bool _experimental = false;
  final TextEditingController _dataRootController = TextEditingController(text: '/var/lib/docker');
  String _storageDriver = 'overlay2';
  int _maxDownloads = 10;
  int _maxUploads = 5;

  // Raw JSON Editor
  final TextEditingController _rawJsonController = TextEditingController();
  String? _jsonSyntaxError;

  // Cluster Host Statuses
  List<dynamic> _hostStatuses = [];
  Map<String, dynamic> _presets = {};

  // Action options
  String _action = 'apply_and_reload'; // apply_and_reload, apply_and_restart, save_only
  bool _createBackup = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);

    if (widget.initialNodeId != null && widget.initialNodeId!.isNotEmpty) {
      _targetScope = 'node';
      _selectedNodeId = widget.initialNodeId;
    } else {
      _targetScope = 'all';
      if (widget.state.nodes.isNotEmpty) {
        _selectedNodeId = widget.state.nodes.first.id;
      }
    }

    _loadClusterDaemonStatus();
    _syncFormToJson();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dnsController.dispose();
    _dnsSearchController.dispose();
    _bipController.dispose();
    _addrPoolBaseController.dispose();
    _addrPoolSizeController.dispose();
    _insecureRegsController.dispose();
    _regMirrorsController.dispose();
    _nvidiaPathController.dispose();
    _metricsAddrController.dispose();
    _dataRootController.dispose();
    _rawJsonController.dispose();
    super.dispose();
  }

  Future<void> _loadClusterDaemonStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.fetchDockerDaemonConfig(
        scope: _targetScope,
        node: _targetScope == 'node' ? _selectedNodeId : null,
      );

      setState(() {
        _hostStatuses = res['hosts'] as List? ?? [];
        _presets = res['presets'] as Map<String, dynamic>? ?? {};
        _isLoading = false;

        // If we loaded a specific host that has an existing config, populate it
        if (_hostStatuses.isNotEmpty) {
          final first = _hostStatuses.first as Map<String, dynamic>;
          if (first['config_exists'] == true && first['raw_json'] != null && (first['raw_json'] as String).isNotEmpty) {
            _populateFromRawJson(first['raw_json'] as String);
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al consultar estado de Docker daemon: $e';
      });
    }
  }

  void _applyPreset(String presetKey) {
    if (!_presets.containsKey(presetKey)) {
      // Fallback local presets
      if (presetKey == 'production') {
        _liveRestore = true;
        _logDriver = 'json-file';
        _logMaxSize = '20m';
        _logMaxFile = '3';
        _dnsController.text = '1.1.1.1, 8.8.8.8';
        _maxDownloads = 10;
        _enableNvidia = false;
        _defaultRuntime = 'runc';
        _enableMetrics = false;
      } else if (presetKey == 'gpu') {
        _liveRestore = true;
        _logDriver = 'json-file';
        _logMaxSize = '20m';
        _logMaxFile = '3';
        _dnsController.text = '1.1.1.1, 8.8.8.8';
        _maxDownloads = 10;
        _enableNvidia = true;
        _defaultRuntime = 'nvidia';
      } else if (presetKey == 'sre') {
        _liveRestore = true;
        _logDriver = 'json-file';
        _logMaxSize = '20m';
        _logMaxFile = '3';
        _dnsController.text = '1.1.1.1, 8.8.8.8';
        _enableMetrics = true;
        _metricsAddrController.text = '0.0.0.0:9323';
        _experimental = true;
      } else if (presetKey == 'minimal') {
        _liveRestore = true;
        _logDriver = 'json-file';
        _logMaxSize = '10m';
        _logMaxFile = '3';
        _enableNvidia = false;
        _enableMetrics = false;
      }
    } else {
      final p = _presets[presetKey] as Map<String, dynamic>;
      _populateFromMap(p);
    }
    _syncFormToJson();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Preset "$presetKey" aplicado con éxito'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _populateFromMap(Map<String, dynamic> map) {
    if (map['live-restore'] != null) _liveRestore = map['live-restore'] == true;
    if (map['log-driver'] != null) _logDriver = map['log-driver'].toString();
    if (map['log-opts'] is Map) {
      final opts = map['log-opts'] as Map;
      if (opts['max-size'] != null) _logMaxSize = opts['max-size'].toString();
      if (opts['max-file'] != null) _logMaxFile = opts['max-file'].toString();
    }
    if (map['dns'] is List) {
      _dnsController.text = (map['dns'] as List).join(', ');
    }
    if (map['dns-search'] is List) {
      _dnsSearchController.text = (map['dns-search'] as List).join(', ');
    }
    if (map['bip'] != null) _bipController.text = map['bip'].toString();
    if (map['default-runtime'] != null) _defaultRuntime = map['default-runtime'].toString();
    if (map['runtimes'] is Map && (map['runtimes'] as Map).containsKey('nvidia')) {
      _enableNvidia = true;
      final nvd = (map['runtimes'] as Map)['nvidia'];
      if (nvd is Map && nvd['path'] != null) {
        _nvidiaPathController.text = nvd['path'].toString();
      }
    } else {
      _enableNvidia = false;
    }
    if (map['metrics-addr'] != null) {
      _enableMetrics = true;
      _metricsAddrController.text = map['metrics-addr'].toString();
    } else {
      _enableMetrics = false;
    }
    if (map['experimental'] != null) _experimental = map['experimental'] == true;
    if (map['data-root'] != null) _dataRootController.text = map['data-root'].toString();
    if (map['storage-driver'] != null) _storageDriver = map['storage-driver'].toString();
    if (map['max-concurrent-downloads'] != null) {
      _maxDownloads = int.tryParse(map['max-concurrent-downloads'].toString()) ?? 10;
    }
    if (map['max-concurrent-uploads'] != null) {
      _maxUploads = int.tryParse(map['max-concurrent-uploads'].toString()) ?? 5;
    }
    if (map['insecure-registries'] is List) {
      _insecureRegsController.text = (map['insecure-registries'] as List).join('\n');
    }
    if (map['registry-mirrors'] is List) {
      _regMirrorsController.text = (map['registry-mirrors'] as List).join('\n');
    }
  }

  void _populateFromRawJson(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        _populateFromMap(decoded);
        _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(decoded);
        _jsonSyntaxError = null;
      }
    } catch (_) {
      _rawJsonController.text = raw;
    }
  }

  Map<String, dynamic> _buildConfigMap() {
    final map = <String, dynamic>{};

    // Logging & Live-Restore
    map['log-driver'] = _logDriver;
    map['log-opts'] = {
      'max-size': _logMaxSize,
      'max-file': _logMaxFile,
    };
    map['live-restore'] = _liveRestore;

    // Storage
    if (_storageDriver.isNotEmpty) map['storage-driver'] = _storageDriver;
    if (_dataRootController.text.trim().isNotEmpty && _dataRootController.text.trim() != '/var/lib/docker') {
      map['data-root'] = _dataRootController.text.trim();
    }

    // DNS
    final dnsList = _dnsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (dnsList.isNotEmpty) map['dns'] = dnsList;

    final dnsSearchList = _dnsSearchController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (dnsSearchList.isNotEmpty) map['dns-search'] = dnsSearchList;

    if (_bipController.text.trim().isNotEmpty) {
      map['bip'] = _bipController.text.trim();
    }

    if (_addrPoolBaseController.text.trim().isNotEmpty) {
      final size = int.tryParse(_addrPoolSizeController.text.trim()) ?? 24;
      map['default-address-pools'] = [
        {'base': _addrPoolBaseController.text.trim(), 'size': size}
      ];
    }

    map['icc'] = _icc;
    map['ip-forward'] = _ipForward;
    map['iptables'] = _iptables;

    // Registries
    final insecList = _insecureRegsController.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (insecList.isNotEmpty) map['insecure-registries'] = insecList;

    final mirrorList = _regMirrorsController.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (mirrorList.isNotEmpty) map['registry-mirrors'] = mirrorList;

    // GPU / Runtimes
    if (_enableNvidia) {
      map['default-runtime'] = _defaultRuntime;
      map['runtimes'] = {
        'nvidia': {
          'path': _nvidiaPathController.text.trim().isEmpty ? 'nvidia-container-runtime' : _nvidiaPathController.text.trim(),
          'runtimeArgs': <String>[],
        }
      };
    } else if (_defaultRuntime != 'runc') {
      map['default-runtime'] = _defaultRuntime;
    }

    // Metrics & Performance
    if (_enableMetrics) {
      map['metrics-addr'] = _metricsAddrController.text.trim().isEmpty ? '0.0.0.0:9323' : _metricsAddrController.text.trim();
      map['experimental'] = true;
    } else if (_experimental) {
      map['experimental'] = true;
    }

    if (_maxDownloads != 3) map['max-concurrent-downloads'] = _maxDownloads;
    if (_maxUploads != 5) map['max-concurrent-uploads'] = _maxUploads;

    return map;
  }

  void _syncFormToJson() {
    final map = _buildConfigMap();
    _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(map);
    setState(() {
      _jsonSyntaxError = null;
    });
  }

  void _validateRawJson(String val) {
    try {
      final decoded = json.decode(val);
      if (decoded is! Map) {
        setState(() => _jsonSyntaxError = 'El JSON debe ser un objeto {}');
        return;
      }
      setState(() => _jsonSyntaxError = null);
    } catch (e) {
      setState(() => _jsonSyntaxError = 'Sintaxis inválida: $e');
    }
  }

  Future<void> _executeSaveAndApply() async {
    // Validate current JSON
    final raw = _rawJsonController.text.trim();
    try {
      json.decode(raw);
    } catch (e) {
      setState(() => _errorMessage = 'Corrige los errores de sintaxis JSON antes de aplicar: $e');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final res = await ApiService.saveDockerDaemonConfig(
        targetScope: _targetScope,
        nodeId: _targetScope == 'node' ? _selectedNodeId : null,
        rawJson: raw,
        action: _action,
        backup: _createBackup,
      );

      final results = res['results'] as List? ?? [];
      final hasFailures = results.any((r) => r['success'] != true);

      setState(() {
        _isSaving = false;
        if (hasFailures) {
          _errorMessage = 'Se completó con advertencias. Revisa los resultados por nodo.';
        } else {
          _successMessage = '¡Configuración de Docker aplicada exitosamente en ${results.length} nodo(s)!';
        }
      });

      widget.onConfigApplied();
      _loadClusterDaemonStatus();
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Error al aplicar configuración: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
                color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2496ED).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune, color: Color(0xFF2496ED), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Docker Engine Daemon (/etc/docker/daemon.json)',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: const Text(
                                'MULTI-HOST ENGINE',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Configura rotación de logs, cero caídas (live-restore), GPU NVIDIA, DNS y métricas en todos o nodos seleccionados.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.65)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scope & Target Selector Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
              child: Row(
                children: [
                  const Text('Ámbito de Aplicación:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('Todos'), icon: Icon(Icons.language, size: 16)),
                      ButtonSegment(value: 'gpu', label: Text('Nodos GPU'), icon: Icon(Icons.bolt, size: 16)),
                      ButtonSegment(value: 'manager', label: Text('Manager'), icon: Icon(Icons.shield, size: 16)),
                      ButtonSegment(value: 'node', label: Text('Específico'), icon: Icon(Icons.dns, size: 16)),
                    ],
                    selected: {_targetScope},
                    onSelectionChanged: (val) {
                      setState(() {
                        _targetScope = val.first;
                      });
                      _loadClusterDaemonStatus();
                    },
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                  if (_targetScope == 'node') ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedNodeId,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: widget.state.nodes.map((n) {
                          final isMgr = n.role == 'manager';
                          return DropdownMenuItem(
                            value: n.id,
                            child: Text('${n.id} (${n.ip}) - ${isMgr ? "👑 Manager" : "Centurion"}'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedNodeId = val;
                          });
                          _loadClusterDaemonStatus();
                        },
                      ),
                    ),
                  ] else ...[
                    const Spacer(),
                    // Preset Quick Chips
                    const Text('Presets Rápidos:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                      label: const Text('Producción', style: TextStyle(fontSize: 11)),
                      onPressed: () => _applyPreset('production'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.bolt, size: 14, color: Colors.green),
                      label: const Text('GPU NVIDIA', style: TextStyle(fontSize: 11)),
                      onPressed: () => _applyPreset('gpu'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.query_stats, size: 14, color: Colors.purpleAccent),
                      label: const Text('SRE Prometheus', style: TextStyle(fontSize: 11)),
                      onPressed: () => _applyPreset('sre'),
                    ),
                  ],
                ],
              ),
            ),

            // Tab Navigation Bar
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: theme.colorScheme.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Logs & Cero Paradas'),
                  Tab(icon: Icon(Icons.language, size: 18), text: 'Redes & DNS'),
                  Tab(icon: Icon(Icons.lock_outline, size: 18), text: 'Registros'),
                  Tab(icon: Icon(Icons.memory, size: 18), text: 'GPU & Runtimes'),
                  Tab(icon: Icon(Icons.bar_chart, size: 18), text: 'Métricas & Almacenamiento'),
                  Tab(icon: Icon(Icons.code, size: 18), text: 'Editor JSON Raw'),
                  Tab(icon: Icon(Icons.dvr, size: 18), text: 'Estado en Clúster'),
                ],
              ),
            ),

            // Messages & Banners
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                ),
              ),

            if (_successMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_successMessage!, style: const TextStyle(color: Colors.green, fontSize: 13))),
                  ],
                ),
              ),

            // Tab Content Body
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLogsTab(theme),
                        _buildNetworkTab(theme),
                        _buildRegistriesTab(theme),
                        _buildGpuTab(theme),
                        _buildMetricsStorageTab(theme),
                        _buildJsonEditorTab(theme),
                        _buildClusterStatusTab(theme),
                      ],
                    ),
            ),

            const Divider(height: 1),

            // Footer Actions & Reload Options
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _createBackup,
                    onChanged: (v) => setState(() => _createBackup = v ?? true),
                  ),
                  const Text('Crear copia de respaldo (.bak) automática', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  // Action selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _action,
                        items: const [
                          DropdownMenuItem(
                            value: 'apply_and_reload',
                            child: Row(
                              children: [
                                Icon(Icons.bolt, color: Colors.amber, size: 16),
                                SizedBox(width: 8),
                                Text('Aplicar y Recargar (SIGHUP - Sin caídas)'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'apply_and_restart',
                            child: Row(
                              children: [
                                Icon(Icons.restart_alt, color: Colors.orange, size: 16),
                                SizedBox(width: 8),
                                Text('Aplicar y Reiniciar servicio Docker'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'save_only',
                            child: Row(
                              children: [
                                Icon(Icons.save, color: Colors.blue, size: 16),
                                SizedBox(width: 8),
                                Text('Solo Guardar fichero daemon.json'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _action = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _executeSaveAndApply,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.rocket_launch, size: 18),
                    label: Text(_isSaving ? 'Aplicando...' : 'Aplicar en Clúster'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TAB 1: Logs & Cero Paradas ─────────────────────────────────────────────
  Widget _buildLogsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Restore Card
          Card(
            color: _liveRestore ? Colors.green.withOpacity(0.08) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SwitchListTile(
                title: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.green, size: 22),
                    SizedBox(width: 10),
                    Text('Zero-Downtime Daemon Restart (live-restore)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Permite reiniciar o recargar el servicio de Docker sin apagar ni reiniciar los contenedores en ejecución. '
                    'Recomendado para entornos de producción y clústeres de alta disponibilidad.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                value: _liveRestore,
                onChanged: (val) {
                  setState(() => _liveRestore = val);
                  _syncFormToJson();
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Log Driver & Rotation Options
          Text('Rotación de Logs de Contenedores', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Evita que los archivos de logs de los contenedores crezcan indefinidamente y llenen el disco de los Centurions.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _logDriver,
                  decoration: const InputDecoration(
                    labelText: 'Controlador de Logs (log-driver)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'json-file', child: Text('json-file (Recomendado)')),
                    DropdownMenuItem(value: 'local', child: Text('local (Binario eficiente)')),
                    DropdownMenuItem(value: 'syslog', child: Text('syslog (Integración SO)')),
                    DropdownMenuItem(value: 'journald', child: Text('journald (systemd)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _logDriver = val);
                      _syncFormToJson();
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _logMaxSize,
                  decoration: const InputDecoration(
                    labelText: 'Tamaño Máximo por Archivo (max-size)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: '10m', child: Text('10 MB')),
                    DropdownMenuItem(value: '20m', child: Text('20 MB (Recomendado)')),
                    DropdownMenuItem(value: '50m', child: Text('50 MB')),
                    DropdownMenuItem(value: '100m', child: Text('100 MB')),
                    DropdownMenuItem(value: '200m', child: Text('200 MB')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _logMaxSize = val);
                      _syncFormToJson();
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _logMaxFile,
                  decoration: const InputDecoration(
                    labelText: 'Archivos a Conservar (max-file)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: '2', child: Text('2 archivos')),
                    DropdownMenuItem(value: '3', child: Text('3 archivos (Recomendado)')),
                    DropdownMenuItem(value: '5', child: Text('5 archivos')),
                    DropdownMenuItem(value: '10', child: Text('10 archivos')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _logMaxFile = val);
                      _syncFormToJson();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TAB 2: Redes & DNS ─────────────────────────────────────────────────────
  Widget _buildNetworkTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Servidores DNS Globales del Motor', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Direcciones IP de resolución DNS por defecto para todos los contenedores creados.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _dnsController,
            decoration: const InputDecoration(
              labelText: 'Servidores DNS (separados por coma)',
              hintText: '1.1.1.1, 8.8.8.8',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
            onChanged: (_) => _syncFormToJson(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _dnsSearchController,
            decoration: const InputDecoration(
              labelText: 'Dominios de Búsqueda DNS (dns-search)',
              hintText: 'corp.internal, gbnt.local',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => _syncFormToJson(),
          ),
          const SizedBox(height: 24),

          Text('Rangos de Red y Subredes de Puente', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _bipController,
                  decoration: const InputDecoration(
                    labelText: 'IP Puente docker0 (bip)',
                    hintText: '172.26.0.1/16',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _syncFormToJson(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _addrPoolBaseController,
                  decoration: const InputDecoration(
                    labelText: 'Piscina Automática (base)',
                    hintText: '10.200.0.0/16',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _syncFormToJson(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _addrPoolSizeController,
                  decoration: const InputDecoration(
                    labelText: 'Tamaño Subred (size)',
                    hintText: '24',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _syncFormToJson(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Network Toggles
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Comunicación Entre Contenedores (icc)'),
                  subtitle: const Text('Permite el tráfico directo entre contenedores en la misma red bridge.'),
                  value: _icc,
                  onChanged: (v) {
                    setState(() => _icc = v);
                    _syncFormToJson();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Reenvío IP del Kernel (ip-forward)'),
                  subtitle: const Text('Habilita net.ipv4.ip_forward para permitir que los contenedores enruten a internet.'),
                  value: _ipForward,
                  onChanged: (v) {
                    setState(() => _ipForward = v);
                    _syncFormToJson();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Gestión de Reglas iptables (iptables)'),
                  subtitle: const Text('Permite a Docker manipular tablas de iptables para exponer puertos mapeados.'),
                  value: _iptables,
                  onChanged: (v) {
                    setState(() => _iptables = v);
                    _syncFormToJson();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 3: Registros & Espejos ─────────────────────────────────────────────
  Widget _buildRegistriesTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Registros Privados Inseguros (HTTP / Certs Autofirmados)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Permite hacer pull y push a registros Docker locales sin SSL obligatorio.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _insecureRegsController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'registry.local:5000\n192.168.1.100:5000',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _syncFormToJson(),
          ),
          const SizedBox(height: 24),

          Text('Espejos de Registro (Registry Mirrors)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Acelera descargas de Docker Hub utilizando espejos de caché locales o de proveedores cloud.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regMirrorsController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'https://mirror.gcr.io\nhttps://hub-mirror.c.163.com',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _syncFormToJson(),
          ),
        ],
      ),
    );
  }

  // ── TAB 4: GPU & Runtimes ──────────────────────────────────────────────────
  Widget _buildGpuTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: _enableNvidia ? Colors.green.withOpacity(0.08) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SwitchListTile(
                title: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.green, size: 24),
                    SizedBox(width: 10),
                    Text('Activar NVIDIA Container Runtime', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Permite el paso de tarjetas gráficas NVIDIA hacia contenedores para tareas de inferencia de IA, '
                    'DeepSeek, Ollama, vLLM, PyTorch y CUDA.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                value: _enableNvidia,
                onChanged: (val) {
                  setState(() {
                    _enableNvidia = val;
                    if (val && _defaultRuntime == 'runc') {
                      _defaultRuntime = 'nvidia';
                    } else if (!val && _defaultRuntime == 'nvidia') {
                      _defaultRuntime = 'runc';
                    }
                  });
                  _syncFormToJson();
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (_enableNvidia) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _defaultRuntime,
                    decoration: const InputDecoration(
                      labelText: 'Runtime por Defecto (default-runtime)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'runc', child: Text('runc (Estándar Linux)')),
                      DropdownMenuItem(value: 'nvidia', child: Text('nvidia (Aceleración GPU por defecto)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _defaultRuntime = val);
                        _syncFormToJson();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _nvidiaPathController,
                    decoration: const InputDecoration(
                      labelText: 'Ruta del Ejecutable NVIDIA Runtime',
                      hintText: 'nvidia-container-runtime',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _syncFormToJson(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Al aplicar este runtime, cualquier servicio con deploy.resources.reservations.devices '
                      'o runtime: nvidia podrá comunicarse directamente con la GPU del Centurion.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── TAB 5: Métricas & Almacenamiento ───────────────────────────────────────
  Widget _buildMetricsStorageTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metrics Prometheus
          Card(
            color: _enableMetrics ? Colors.purple.withOpacity(0.08) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Row(
                      children: [
                        Icon(Icons.query_stats, color: Colors.purpleAccent, size: 22),
                        SizedBox(width: 10),
                        Text('Exponer Métricas Prometheus Nativas', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Expone el endpoint de telemetría de Docker Engine en formato Prometheus para monitorización con Sloth / Grafana.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    value: _enableMetrics,
                    onChanged: (val) {
                      setState(() {
                        _enableMetrics = val;
                        if (val) _experimental = true;
                      });
                      _syncFormToJson();
                    },
                  ),
                  if (_enableMetrics) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _metricsAddrController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección de Métricas (metrics-addr)',
                        hintText: '0.0.0.0:9323',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _syncFormToJson(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text('Rutas de Almacenamiento y Concurrencia', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _dataRootController,
                  decoration: const InputDecoration(
                    labelText: 'Directorio Raíz de Datos (data-root)',
                    hintText: '/var/lib/docker',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _syncFormToJson(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _storageDriver,
                  decoration: const InputDecoration(
                    labelText: 'Controlador (storage-driver)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'overlay2', child: Text('overlay2 (Recomendado)')),
                    DropdownMenuItem(value: 'btrfs', child: Text('btrfs')),
                    DropdownMenuItem(value: 'zfs', child: Text('zfs')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _storageDriver = val);
                      _syncFormToJson();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _maxDownloads.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Descargas Simultáneas (max-concurrent-downloads)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    _maxDownloads = int.tryParse(val) ?? 10;
                    _syncFormToJson();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  initialValue: _maxUploads.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Subidas Simultáneas (max-concurrent-uploads)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    _maxUploads = int.tryParse(val) ?? 5;
                    _syncFormToJson();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TAB 6: Editor JSON Raw ─────────────────────────────────────────────────
  Widget _buildJsonEditorTab(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Editor Directo de /etc/docker/daemon.json', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    final dec = json.decode(_rawJsonController.text);
                    _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(dec);
                    setState(() => _jsonSyntaxError = null);
                  } catch (e) {
                    setState(() => _jsonSyntaxError = 'Error al formatear: $e');
                  }
                },
                icon: const Icon(Icons.format_align_left, size: 16),
                label: const Text('Formatear JSON'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _syncFormToJson,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Sincronizar desde Formulario'),
              ),
            ],
          ),
          if (_jsonSyntaxError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Text(_jsonSyntaxError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _jsonSyntaxError != null ? Colors.red : theme.dividerColor),
              ),
              child: TextFormField(
                controller: _rawJsonController,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  _validateRawJson(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 7: Estado en Clúster ───────────────────────────────────────────────
  Widget _buildClusterStatusTab(ThemeData theme) {
    if (_hostStatuses.isEmpty) {
      return const Center(child: Text('No hay información disponible para los nodos seleccionados.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _hostStatuses.length,
      itemBuilder: (ctx, i) {
        final h = _hostStatuses[i] as Map<String, dynamic>;
        final nodeID = h['node_id'] ?? '';
        final nodeIP = h['node_ip'] ?? '';
        final role = h['role'] ?? 'worker';
        final hasGPU = h['has_gpu'] == true;
        final gpuInfo = h['gpu_info'] ?? '';
        final configExists = h['config_exists'] == true;
        final daemonRunning = h['daemon_running'] == true;
        final lastMod = h['last_modified'] ?? '';
        final raw = h['raw_json'] ?? '';
        final error = h['error'];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(role == 'manager' ? Icons.shield : Icons.dns, color: role == 'manager' ? Colors.amber : Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      '$nodeID ($nodeIP)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(role.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    if (hasGPU) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bolt, size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(gpuInfo.isNotEmpty ? gpuInfo : 'NVIDIA GPU', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (daemonRunning ? Colors.green : Colors.red).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: (daemonRunning ? Colors.green : Colors.red).withOpacity(0.4)),
                      ),
                      child: Text(
                        daemonRunning ? 'DOCKER ACTIVE' : 'DOCKER INACTIVE',
                        style: TextStyle(color: daemonRunning ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (error != null && error.isNotEmpty) ...[
                  Text('Error de comunicación: $error', style: const TextStyle(color: Colors.red, fontSize: 12)),
                ] else ...[
                  Row(
                    children: [
                      Text('Archivo /etc/docker/daemon.json: ', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 12)),
                      Text(configExists ? 'Presente' : 'No configurado (valores por defecto)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: configExists ? Colors.blue : Colors.grey)),
                      if (lastMod.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Text('Modificado: $lastMod', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 11)),
                      ],
                      const Spacer(),
                      if (raw.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.download, size: 14),
                          label: const Text('Cargar a Editor', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            _populateFromRawJson(raw);
                            _tabController.animateTo(5); // Switch to Raw JSON tab
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Configuración de $nodeID cargada al editor')),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
