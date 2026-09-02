import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ImageDistributeDialog extends StatefulWidget {
  final String imageName;
  final String? signatureStatus;
  final String? signatureSigner;
  final List<String> currentHosts;
  final VoidCallback onSuccess;

  const ImageDistributeDialog({
    super.key,
    required this.imageName,
    this.signatureStatus,
    this.signatureSigner,
    this.currentHosts = const [],
    required this.onSuccess,
  });

  @override
  State<ImageDistributeDialog> createState() => _ImageDistributeDialogState();
}

class _ImageDistributeDialogState extends State<ImageDistributeDialog> {
  String _selectedTarget = 'all';
  bool _isDistributing = false;
  ImageDistributeResultModel? _result;
  String? _errorMessage;

  List<Node> _nodes = [];
  bool _loadingNodes = true;

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    try {
      final nodes = await ApiService.fetchNodes();
      if (mounted) {
        setState(() {
          _nodes = nodes;
          _loadingNodes = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingNodes = false;
        });
      }
    }
  }

  Future<void> _executeDistribution() async {
    setState(() {
      _isDistributing = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final result = await ApiService.distributeDockerImage(
        image: widget.imageName,
        targetNode: _selectedTarget,
      );

      if (mounted) {
        setState(() {
          _result = result;
          _isDistributing = false;
        });
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isDistributing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSigned = widget.signatureStatus == 'verified' || widget.signatureStatus == 'signed';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.share_location, color: Colors.blueAccent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Distribute Image Across Cluster',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Stream and synchronize container image to all Centurion worker nodes.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[400]),
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
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 12),

            // Image Name Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.layers, size: 18, color: Colors.lightBlueAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.imageName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, fontFamily: 'monospace'),
                        ),
                      ),
                      if (isSigned)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified, size: 13, color: Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Text(
                                widget.signatureSigner != null && widget.signatureSigner!.isNotEmpty
                                    ? 'SIGNED (${widget.signatureSigner})'
                                    : 'SIGNED',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (widget.currentHosts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Currently present on: ',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[400]),
                        ),
                        for (final host in widget.currentHosts)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                host,
                                style: const TextStyle(fontSize: 10.5, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Target Centurion selector
            const Text(
              'Target Centurion Destination',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedTarget,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.dns, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Row(
                    children: [
                      Icon(Icons.public, size: 16, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text('🌐 All Centurion Nodes (Cluster-Wide Mesh)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                for (final node in _nodes)
                  DropdownMenuItem(
                    value: node.id.isNotEmpty ? node.id : node.ip,
                    child: Row(
                      children: [
                        Icon(
                          node.role == 'manager' ? Icons.computer : Icons.dns_outlined,
                          size: 16,
                          color: node.role == 'manager' ? Colors.indigoAccent : Colors.tealAccent,
                        ),
                        const SizedBox(width: 8),
                        Text('${node.labels['gbnt.node.hostname'] ?? node.id} (${node.ip}) — [${node.role.toUpperCase()}]'),
                      ],
                    ),
                  ),
              ],
              onChanged: _isDistributing
                  ? null
                  : (val) {
                      if (val != null) setState(() => _selectedTarget = val);
                    },
            ),

            const SizedBox(height: 16),

            // Execution Progress / Results Box
            if (_isDistributing)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Exporting image and streaming via SSH bridge to target Centurions...',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(fontSize: 12.5, color: Colors.redAccent))),
                  ],
                ),
              ),

            if (_result != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _result!.success ? const Color(0xFF10B981).withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _result!.success ? const Color(0xFF10B981).withValues(alpha: 0.4) : Colors.orangeAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _result!.success ? Icons.check_circle : Icons.warning_amber_rounded,
                          color: _result!.success ? const Color(0xFF10B981) : Colors.orangeAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _result!.success ? 'Image Successfully Distributed & Ready on All Nodes' : 'Distribution Completed with Warnings',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _result!.success ? const Color(0xFF10B981) : Colors.orangeAccent,
                          ),
                        ),
                        const Spacer(),
                        Text('⏱️ ${_result!.duration}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final entry in _result!.nodeResults.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_right, size: 16, color: Colors.grey),
                            Text('${entry.key}: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: entry.value.contains('successfully') || entry.value.contains('present')
                                      ? const Color(0xFF10B981)
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isDistributing ? null : () => Navigator.of(context).pop(),
                  child: Text(_result != null ? 'Close' : 'Cancel'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: _isDistributing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.share_location, size: 16),
                  label: Text(_isDistributing ? 'Distributing...' : 'Distribute & Load'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onPressed: _isDistributing ? null : _executeDistribution,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
