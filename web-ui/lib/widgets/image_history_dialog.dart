import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Modal dialog for deep container image layer inspection and reconstructed Dockerfile viewing
class ImageHistoryDialog extends StatefulWidget {
  final String imageName;
  final String node;
  final Function(String dockerfile, String tag)? onOpenInForge;

  const ImageHistoryDialog({
    super.key,
    required this.imageName,
    this.node = 'manager',
    this.onOpenInForge,
  });

  @override
  State<ImageHistoryDialog> createState() => _ImageHistoryDialogState();
}

class _ImageHistoryDialogState extends State<ImageHistoryDialog> with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _errorMessage;
  ImageHistoryModel? _history;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.fetchImageHistory(widget.imageName, node: widget.node);
      if (mounted) {
        setState(() {
          _history = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
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
              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.history_edu, color: Color(0xFF3B82F6), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Image Construction & Layer History',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.imageName,
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_history != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${_history!.layers.length} LAYERS  •  ${_history!.totalSize}',
                style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 780,
        height: 520,
        child: _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Inspecting image layers and reconstructing Dockerfile...'),
                  ],
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                        const SizedBox(height: 12),
                        Text('Failed to inspect history: $_errorMessage'),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _fetchHistory, child: const Text('Retry')),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        labelColor: isDark ? Colors.white : Colors.blueAccent,
                        indicatorColor: const Color(0xFF3B82F6),
                        tabs: const [
                          Tab(icon: Icon(Icons.view_timeline_outlined, size: 16), text: 'Layer Timeline'),
                          Tab(icon: Icon(Icons.code, size: 16), text: 'Reconstructed Dockerfile'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // 1. Layer Timeline
                            _buildLayerTimeline(isDark),
                            // 2. Reconstructed Dockerfile
                            _buildDockerfileView(isDark),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        if (_history != null) ...[
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Dockerfile'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _history!.reconstructedDockerfile));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Reconstructed Dockerfile copied to clipboard!')),
              );
            },
          ),
          if (widget.onOpenInForge != null)
            FilledButton.icon(
              icon: const Icon(Icons.build_circle_outlined, size: 16),
              label: const Text('Edit & Rebuild in Forge'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
              onPressed: () {
                Navigator.pop(context);
                widget.onOpenInForge!(_history!.reconstructedDockerfile, widget.imageName);
              },
            ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildLayerTimeline(bool isDark) {
    if (_history == null || _history!.layers.isEmpty) {
      return const Center(child: Text('No layer history found.'));
    }

    return ListView.builder(
      itemCount: _history!.layers.length,
      itemBuilder: (ctx, idx) {
        final layer = _history!.layers[idx];
        final isTopLayer = idx == _history!.layers.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline line & badge
            Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _instructionColor(layer.instruction).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: _instructionColor(layer.instruction)),
                  ),
                  child: Center(
                    child: Text(
                      '${layer.order}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: _instructionColor(layer.instruction),
                      ),
                    ),
                  ),
                ),
                if (!isTopLayer)
                  Container(
                    width: 2,
                    height: 48,
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.3),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Layer Card
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _instructionColor(layer.instruction).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            layer.instruction.isNotEmpty ? layer.instruction : 'COMMAND',
                            style: TextStyle(
                              color: _instructionColor(layer.instruction),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (layer.size.isNotEmpty && layer.size != '0B')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${layer.size}',
                              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 10.5),
                            ),
                          )
                        else
                          Text('0 B (metadata layer)', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[600])),
                        const Spacer(),
                        if (layer.id.isNotEmpty && layer.id != '<missing>')
                          Text(
                            'ID: ${layer.id.length > 12 ? layer.id.substring(0, 12) : layer.id}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: Colors.grey),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      layer.args.isNotEmpty ? layer.args : layer.createdBy,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDockerfileView(bool isDark) {
    if (_history == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _history!.reconstructedDockerfile,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            color: Color(0xFFE2E8F0),
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Color _instructionColor(String instr) {
    switch (instr.toUpperCase()) {
      case 'FROM':
        return Colors.purpleAccent;
      case 'RUN':
        return Colors.blueAccent;
      case 'COPY':
      case 'ADD':
        return Colors.tealAccent;
      case 'ENV':
      case 'ARG':
        return Colors.orangeAccent;
      case 'EXPOSE':
        return Colors.amberAccent;
      case 'ENTRYPOINT':
      case 'CMD':
        return const Color(0xFF10B981);
      case 'WORKDIR':
        return Colors.indigoAccent;
      default:
        return Colors.grey;
    }
  }
}
