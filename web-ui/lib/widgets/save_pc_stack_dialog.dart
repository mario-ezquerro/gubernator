import 'package:flutter/material.dart';
import '../utils/clipboard_service.dart';
import '../utils/download_service.dart';

/// Modal dialog to save a Compose YAML file on the user's local PC/computer,
/// allowing the user to customize the filename, browse OS folders (via File System Access API
/// or browser download picker), or copy YAML directly.
class SavePcStackDialog extends StatefulWidget {
  final String initialName;
  final String yamlContent;
  final String? initialFilename;

  const SavePcStackDialog({
    super.key,
    required this.initialName,
    required this.yamlContent,
    this.initialFilename,
  });

  @override
  State<SavePcStackDialog> createState() => _SavePcStackDialogState();
}

class _SavePcStackDialogState extends State<SavePcStackDialog> {
  late TextEditingController _nameController;
  late TextEditingController _filenameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final name = widget.initialName.trim().isEmpty ? 'my-stack' : widget.initialName.trim();
    _nameController = TextEditingController(text: name);

    var initFn = widget.initialFilename;
    if (initFn == null || initFn.isEmpty) {
      initFn = name == 'my-stack' ? 'docker-compose.yml' : '$name.yml';
    }
    _filenameController = TextEditingController(text: initFn);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  void _setPreset(String filename) {
    setState(() {
      _filenameController.text = filename;
    });
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    var filename = _filenameController.text.trim();

    if (filename.isEmpty) {
      filename = name.isEmpty ? 'docker-compose.yml' : '$name.yml';
    }
    if (!filename.endsWith('.yml') && !filename.endsWith('.yaml')) {
      filename = '$filename.yml';
    }

    setState(() => _saving = true);

    try {
      final success = await DownloadService.saveYamlFile(
        content: widget.yamlContent,
        filename: filename,
      );

      if (!mounted) return;
      setState(() => _saving = false);

      if (success) {
        Navigator.of(context).pop(filename);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Archivo "$filename" guardado correctamente en tu ordenador.')),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleCopyYaml() {
    ClipboardService.copy(widget.yamlContent);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.copy_all, color: Colors.greenAccent, size: 18),
            SizedBox(width: 8),
            Text('Compose YAML copiado al portapapeles.'),
          ],
        ),
        backgroundColor: Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stackName = _nameController.text.trim().isEmpty ? 'stack' : _nameController.text.trim();
    final hasNativePicker = DownloadService.isFileSystemAccessSupported;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF388BFD).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.laptop_chromebook, color: Color(0xFF388BFD), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Guardar en tu PC (Ordenador)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personaliza el nombre del archivo Compose y elije la carpeta de tu equipo donde deseas guardarlo.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              // Filename
              const Text('Nombre del archivo (.yml / .yaml)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _filenameController,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.description_outlined, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => _filenameController.clear(),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  hintText: 'e.g. docker-compose.yml o $stackName.yml',
                ),
              ),
              const SizedBox(height: 10),

              // Quick Filename Presets
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Nombres sugeridos: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ActionChip(
                    label: const Text('docker-compose.yml', style: TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setPreset('docker-compose.yml'),
                  ),
                  ActionChip(
                    label: Text('$stackName.yml', style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setPreset('$stackName.yml'),
                  ),
                  ActionChip(
                    label: const Text('compose.yml', style: TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setPreset('compose.yml'),
                  ),
                  ActionChip(
                    label: Text('$stackName-compose.yml', style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setPreset('$stackName-compose.yml'),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Browser Capabilities & Folder Navigation Guidance
              if (hasNativePicker)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.folder_open, color: Colors.greenAccent, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tu navegador soporta el explorador de archivos nativo. Al pulsar "Examinar y Guardar", se abrirá la ventana de tu sistema operativo (Finder / Explorador de Windows) para navegar por tus carpetas y elegir la ubicación exacta.',
                          style: TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF388BFD).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF388BFD).withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, color: Color(0xFF58A6FF), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'El archivo se guardará con el nombre que elijas arriba.',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.35),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '💡 Consejo: Para que el navegador siempre te pregunte en qué carpeta de tu ordenador guardarlo en cada descarga y puedas navegar por tus directorios, activa en tu navegador:\nConfiguración ➔ Descargas ➔ "Preguntar dónde se guardará cada archivo antes de descargarlo".',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _handleCopyYaml,
          icon: const Icon(Icons.copy, size: 15),
          label: const Text('Copiar YAML'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _handleSave,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(hasNativePicker ? Icons.folder_open : Icons.save_alt, size: 16),
          label: Text(hasNativePicker ? 'Examinar y Guardar...' : 'Guardar en PC'),
        ),
      ],
    );
  }
}

/// Helper function to open the SavePcStackDialog from any page or widget.
Future<String?> showSavePcStackDialog({
  required BuildContext context,
  required String initialName,
  required String yamlContent,
  String? initialFilename,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SavePcStackDialog(
      initialName: initialName,
      yamlContent: yamlContent,
      initialFilename: initialFilename,
    ),
  );
}
