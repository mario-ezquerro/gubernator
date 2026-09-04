import 'package:flutter/material.dart';
import '../models/models.dart' as models;
import '../services/api_service.dart';

/// Modal dialog to browse, inspect, and select Compose files residing on the Master server filesystem.
class ServerStackPickerDialog extends StatefulWidget {
  final Function(String name, String yaml) onSelect;
  final Function(String path, String? name)? onDirectDeploy;

  const ServerStackPickerDialog({
    super.key,
    required this.onSelect,
    this.onDirectDeploy,
  });

  @override
  State<ServerStackPickerDialog> createState() => _ServerStackPickerDialogState();
}

class _ServerStackPickerDialogState extends State<ServerStackPickerDialog> {
  bool _loading = true;
  String? _error;
  List<models.ServerStackFileModel> _files = [];
  String _currentDir = '';
  String _parentDir = '';
  List<Map<String, String>> _subdirectories = [];
  String _stacksDir = '';
  String _examplesDir = '';
  final TextEditingController _customDirController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  models.ServerStackFileModel? _selectedFile;
  String _previewContent = '';
  bool _loadingPreview = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _customDirController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles({String? customDir}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiService.fetchServerStackFiles(dir: customDir);
      final files = res['files'] as List<models.ServerStackFileModel>;
      final currentDir = res['current_dir'] as String? ?? customDir ?? '';
      final parentDir = res['parent_dir'] as String? ?? '';
      final subdirs = (res['subdirectories'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(e as Map))
              .toList() ??
          [];

      setState(() {
        _files = files;
        _currentDir = currentDir;
        _parentDir = parentDir;
        _subdirectories = subdirs;
        _customDirController.text = currentDir;
        _stacksDir = res['stacks_dir'] ?? '';
        _examplesDir = res['examples_dir'] ?? '';
        _loading = false;
        if (files.isNotEmpty) {
          _loadFilePreview(files.first);
        } else {
          _selectedFile = null;
          _previewContent = '';
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadFilePreview(models.ServerStackFileModel file) async {
    setState(() {
      _selectedFile = file;
      _loadingPreview = true;
    });

    try {
      final res = await ApiService.fetchServerStackFile(file.path);
      setState(() {
        _previewContent = res['content'] ?? '';
        _loadingPreview = false;
      });
    } catch (e) {
      setState(() {
        _previewContent = '# Failed to load preview: $e';
        _loadingPreview = false;
      });
    }
  }

  void _navigateToParent() {
    if (_parentDir.isNotEmpty) {
      _loadFiles(customDir: _parentDir);
    }
  }

  Widget _buildQuickLocationChip({
    required String label,
    required String path,
    required IconData icon,
    required Color color,
  }) {
    final isCurrent = _currentDir == path || (_currentDir.endsWith('/examples') && path.contains('examples'));
    return InkWell(
      onTap: () => _loadFiles(customDir: path),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isCurrent ? color.withOpacity(0.2) : const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isCurrent ? color : const Color(0xFF30363D),
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent ? Colors.white : const Color(0xFFC9D1D9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    if (_currentDir.isEmpty) return const SizedBox.shrink();

    final parts = _currentDir.split('/').where((p) => p.isNotEmpty).toList();
    List<Widget> crumbs = [];

    // Root button
    crumbs.add(
      InkWell(
        onTap: () => _loadFiles(customDir: '/'),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text('/', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ),
    );

    String accumulatedPath = '';
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      accumulatedPath += '/$part';
      final isLast = i == parts.length - 1;
      final target = accumulatedPath;

      crumbs.add(const Text('/', style: TextStyle(color: Colors.grey, fontSize: 12)));
      crumbs.add(
        InkWell(
          onTap: isLast ? null : () => _loadFiles(customDir: target),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              part,
              style: TextStyle(
                color: isLast ? Colors.white : const Color(0xFF58A6FF),
                fontSize: 12,
                fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            color: _parentDir.isNotEmpty ? const Color(0xFF58A6FF) : Colors.grey,
            tooltip: _parentDir.isNotEmpty ? 'Subir a $_parentDir' : 'En la raíz',
            onPressed: _parentDir.isNotEmpty ? _navigateToParent : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.folder_open, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredFiles = _files.where((f) {
      if (query.isEmpty) return true;
      return f.filename.toLowerCase().contains(query) ||
          f.inferredName.toLowerCase().contains(query) ||
          f.path.toLowerCase().contains(query);
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF30363D)),
      ),
      child: Container(
        width: 1050,
        height: 720,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.dns, color: Color(0xFF58A6FF), size: 24),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explorador de Stacks en Disco del Servidor Master',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Navega por carpetas del servidor y selecciona archivos Compose (.yml / .yaml) para desplegar',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.grey),
                  tooltip: 'Refrescar directorio actual',
                  onPressed: () => _loadFiles(customDir: _currentDir),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick Access Locations
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text('Accesos directos: ', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                _buildQuickLocationChip(
                  label: 'POC Examples (~/.gbnt/examples)',
                  path: _examplesDir.isNotEmpty ? _examplesDir : '~/.gbnt/examples',
                  icon: Icons.rocket_launch,
                  color: const Color(0xFF2EA043),
                ),
                _buildQuickLocationChip(
                  label: 'User Stacks (~/.gbnt/stacks)',
                  path: _stacksDir.isNotEmpty ? _stacksDir : '~/.gbnt/stacks',
                  icon: Icons.layers,
                  color: const Color(0xFF8B5CF6),
                ),
                _buildQuickLocationChip(
                  label: 'Granaries (/var/contenedores)',
                  path: '/var/contenedores',
                  icon: Icons.storage,
                  color: Colors.teal,
                ),
                _buildQuickLocationChip(
                  label: 'System (/etc/gubernator/stacks)',
                  path: '/etc/gubernator/stacks',
                  icon: Icons.settings_system_daydream,
                  color: Colors.lightBlue,
                ),
                _buildQuickLocationChip(
                  label: 'Home (~)',
                  path: '~',
                  icon: Icons.home,
                  color: Colors.amber,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Directory / search filters + Breadcrumbs
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Filtrar archivos por nombre...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _customDirController,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ruta absoluta o relativa (ej: /opt/stacks)...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.folder_open, size: 18, color: Colors.grey),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 18, color: Color(0xFF58A6FF)),
                        tooltip: 'Ir a esta carpeta',
                        onPressed: () => _loadFiles(customDir: _customDirController.text.trim()),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                    ),
                    onSubmitted: (val) => _loadFiles(customDir: val.trim()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Interactive Breadcrumb Navigation
            _buildBreadcrumbs(),
            const SizedBox(height: 12),

            // Content Area (Split View: Folders + Files list vs YAML preview)
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                              const SizedBox(height: 8),
                              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => _loadFiles(customDir: _stacksDir),
                                child: const Text('Volver a stacks por defecto'),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            // Left list (Subdirectories + Files)
                            Expanded(
                              flex: 5,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1117),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF30363D)),
                                ),
                                child: ListView(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  children: [
                                    // Subdirectories section
                                    if (_subdirectories.isNotEmpty) ...[
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.folder, size: 14, color: Colors.amber),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Carpetas en este directorio (${_subdirectories.length})',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ..._subdirectories.map((sub) {
                                        final subName = sub['name'] ?? '';
                                        final subPath = sub['path'] ?? '';
                                        return ListTile(
                                          dense: true,
                                          visualDensity: VisualDensity.compact,
                                          leading: const Icon(Icons.folder, color: Colors.amber, size: 18),
                                          title: Text(
                                            subName,
                                            style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13, fontWeight: FontWeight.w500),
                                          ),
                                          trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                                          onTap: () => _loadFiles(customDir: subPath),
                                        );
                                      }),
                                      const Divider(height: 16, color: Color(0xFF21262D)),
                                    ],

                                    // Files section
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.description, size: 14, color: Color(0xFF58A6FF)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Archivos Compose (.yml / .yaml) (${filteredFiles.length})',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (filteredFiles.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                          _subdirectories.isNotEmpty
                                              ? 'No hay archivos Compose en esta carpeta.\nHaz clic en las carpetas de arriba para explorar su contenido.'
                                              : 'No se encontraron archivos .yml ni subcarpetas aquí.',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                                        ),
                                      )
                                    else
                                      ...filteredFiles.map((f) {
                                        final isSelected = _selectedFile?.path == f.path;
                                        return ListTile(
                                          dense: true,
                                          selected: isSelected,
                                          selectedTileColor: const Color(0xFF1F6FEB).withOpacity(0.15),
                                          leading: Icon(
                                            f.isExample ? Icons.rocket_launch : Icons.description,
                                            color: f.isExample ? const Color(0xFF2EA043) : const Color(0xFF58A6FF),
                                            size: 18,
                                          ),
                                          title: Text(
                                            f.filename,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'Stack: ${f.inferredName} • ${f.services} svc • ${(f.size / 1024).toStringAsFixed(1)} KB',
                                            style: const TextStyle(color: Colors.grey, fontSize: 11),
                                          ),
                                          trailing: f.isExample
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF2EA043).withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFF2EA043)),
                                                  ),
                                                  child: const Text('POC', style: TextStyle(color: Color(0xFF2EA043), fontSize: 10, fontWeight: FontWeight.bold)),
                                                )
                                              : null,
                                          onTap: () => _loadFilePreview(f),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Right Preview
                            Expanded(
                              flex: 6,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1117),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF30363D)),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_selectedFile != null) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.code, size: 16, color: Colors.grey),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _selectedFile!.path,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 16, color: Color(0xFF30363D)),
                                    ],
                                    Expanded(
                                      child: _loadingPreview
                                          ? const Center(child: CircularProgressIndicator())
                                          : SingleChildScrollView(
                                              child: SelectableText(
                                                _previewContent.isEmpty ? '# Selecciona un archivo Compose para previsualizarlo' : _previewContent,
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 12,
                                                  color: Color(0xFF7EE787),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
            const SizedBox(height: 16),

            // Actions footer
            Row(
              children: [
                if (_selectedFile != null)
                  Text(
                    'Seleccionado: ${_selectedFile!.filename} (${_selectedFile!.inferredName})',
                    style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.file_download, size: 18),
                  label: const Text('Cargar en Editor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _selectedFile == null || _loadingPreview
                      ? null
                      : () {
                          widget.onSelect(_selectedFile!.inferredName, _previewContent);
                          Navigator.pop(context);
                        },
                ),
                if (widget.onDirectDeploy != null && _selectedFile != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.rocket_launch, size: 18),
                    label: const Text('Desplegar Inmediatamente'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F6FEB),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      widget.onDirectDeploy!(_selectedFile!.path, _selectedFile!.inferredName);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
