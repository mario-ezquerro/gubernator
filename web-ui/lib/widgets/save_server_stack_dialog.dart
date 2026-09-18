import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Modal dialog to save or update a Compose YAML file on the Master server filesystem.
class SaveServerStackDialog extends StatefulWidget {
  final String initialName;
  final String yamlContent;
  final String? initialDir;
  final String? initialFilename;

  const SaveServerStackDialog({
    super.key,
    required this.initialName,
    required this.yamlContent,
    this.initialDir,
    this.initialFilename,
  });

  @override
  State<SaveServerStackDialog> createState() => _SaveServerStackDialogState();
}

class _SaveServerStackDialogState extends State<SaveServerStackDialog> {
  late TextEditingController _nameController;
  late TextEditingController _filenameController;
  late TextEditingController _dirController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final name = widget.initialName.trim().isEmpty ? 'my-stack' : widget.initialName.trim();
    _nameController = TextEditingController(text: name);
    _filenameController = TextEditingController(
      text: widget.initialFilename ?? '$name.yml',
    );
    _dirController = TextEditingController(
      text: widget.initialDir ?? '~/.gbnt/stacks',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _filenameController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    var filename = _filenameController.text.trim();
    final dir = _dirController.text.trim();

    if (filename.isEmpty) {
      filename = name.isEmpty ? 'docker-compose.yml' : '$name.yml';
    }
    if (!filename.endsWith('.yml') && !filename.endsWith('.yaml')) {
      filename = '$filename.yml';
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final res = await ApiService.saveServerStackFile(
        content: widget.yamlContent,
        name: name,
        filename: filename,
        dir: dir,
      );

      if (!mounted) return;
      Navigator.of(context).pop(res['path'] ?? filename);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.dns, color: Color(0xFF58A6FF), size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Save to Master Server',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save this Compose YAML directly onto the Master server filesystem for cluster discovery and zero-touch persistence.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Stack Name
              const Text('Stack Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  hintText: 'e.g. wordpress, scada-app, backend-api',
                ),
                onChanged: (val) {
                  final cleaned = val.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '-');
                  if (cleaned.isNotEmpty && !_filenameController.text.endsWith('.yaml')) {
                    _filenameController.text = '$cleaned.yml';
                  }
                },
              ),
              const SizedBox(height: 14),

              // Filename
              const Text('Filename (.yml / .yaml)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _filenameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  hintText: 'e.g. docker-compose.yml or my-stack.yml',
                ),
              ),
              const SizedBox(height: 14),

              // Server Directory
              const Text('Master Server Directory', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _dirController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  hintText: '~/.gbnt/stacks',
                ),
              ),
              const SizedBox(height: 8),

              // Directory Presets
              Row(
                children: [
                  const Text('Quick paths: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ActionChip(
                    label: const Text('~/.gbnt/stacks', style: TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _dirController.text = '~/.gbnt/stacks'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('/var/contenedores/stacks', style: TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _dirController.text = '/var/contenedores/stacks'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _handleSave,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save, size: 16),
          label: const Text('Save on Server'),
        ),
      ],
    );
  }
}

/// Helper function to open the SaveServerStackDialog from any page or widget.
Future<String?> showSaveServerStackDialog({
  required BuildContext context,
  required String initialName,
  required String yamlContent,
  String? initialDir,
  String? initialFilename,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SaveServerStackDialog(
      initialName: initialName,
      yamlContent: yamlContent,
      initialDir: initialDir,
      initialFilename: initialFilename,
    ),
  );
}
