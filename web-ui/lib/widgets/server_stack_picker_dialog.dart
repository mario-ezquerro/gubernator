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
      setState(() {
        _files = files;
        _stacksDir = res['stacks_dir'] ?? '';
        _examplesDir = res['examples_dir'] ?? '';
        _loading = false;
        if (files.isNotEmpty && _selectedFile == null) {
          _loadFilePreview(files.first);
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
        width: 950,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.dns, color: Color(0xFF58A6FF), size: 24),
                const SizedBox(width: 10),
                const Text(
                  'Load Stack from Master Server Filesystem',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.grey),
                  tooltip: 'Refresh file list',
                  onPressed: () => _loadFiles(customDir: _customDirController.text),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Select any Docker Compose (.yml) file residing on the Gubernator Master host. Default directory: $_stacksDir',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            // Directory / search filters
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Filter files by name or path...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      isDense: true,
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
                      hintText: 'Custom server path (e.g. /opt/stacks)...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.folder_open, size: 18, color: Colors.grey),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 18, color: Color(0xFF58A6FF)),
                        onPressed: () => _loadFiles(customDir: _customDirController.text.trim()),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      isDense: true,
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
            const SizedBox(height: 12),

            // Content Area (Split View: Files list vs YAML preview)
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
                                onPressed: () => _loadFiles(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            // Left list
                            Expanded(
                              flex: 5,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1117),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF30363D)),
                                ),
                                child: filteredFiles.isEmpty
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Text(
                                            'No Compose files found.\nDrop .yml files into $_stacksDir on the server.',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: filteredFiles.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF21262D)),
                                        itemBuilder: (context, idx) {
                                          final f = filteredFiles[idx];
                                          final isSelected = _selectedFile?.path == f.path;
                                          return ListTile(
                                            dense: true,
                                            selected: isSelected,
                                            selectedTileColor: const Color(0xFF1F6FEB).withOpacity(0.15),
                                            leading: Icon(
                                              f.isExample ? Icons.rocket_launch : Icons.description,
                                              color: f.isExample ? const Color(0xFF2EA043) : const Color(0xFF58A6FF),
                                              size: 20,
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
                                        },
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
                                                _previewContent,
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
                    'Selected: ${_selectedFile!.filename} (${_selectedFile!.inferredName})',
                    style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.file_download, size: 18),
                  label: const Text('Load into Editor'),
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
                    label: const Text('Deploy Immediately'),
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
