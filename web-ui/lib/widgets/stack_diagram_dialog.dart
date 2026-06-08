import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/models.dart';
import '../theme/theme.dart';

class DiagramNode {
  final Service service;
  final Task? task; // null if service has no tasks (e.g. Caddy or inactive service)
  final String displayName;
  final int column; // 0 for Caddy, 1 for Web/Sources, 2 for Sinks/DBs
  final int index;  // vertical index in the column
  final double x;
  final double y;

  DiagramNode({
    required this.service,
    this.task,
    required this.displayName,
    required this.column,
    required this.index,
    required this.x,
    required this.y,
  });
}

class StackDiagramDialog extends StatefulWidget {
  final StackModel stack;
  final List<Service> services;
  final List<Task> tasks;
  final List<Node> nodes;

  const StackDiagramDialog({
    super.key,
    required this.stack,
    required this.services,
    required this.tasks,
    required this.nodes,
  });

  @override
  State<StackDiagramDialog> createState() => _StackDiagramDialogState();
}

class _StackDiagramDialogState extends State<StackDiagramDialog> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  
  late final List<Service> _stackServices;
  late final Map<String, List<String>> _adjList;
  late final Map<String, DiagramNode> _nodes;
  late final Map<String, String> _ingressHosts;
  
  late final List<Map<String, dynamic>> _column0Items;
  late final List<Map<String, dynamic>> _column1Items;
  late final List<Map<String, dynamic>> _column2Items;

  double _containerHeight = 250;
  final double _canvasWidth = 700;
  final double _cardWidth = 180;
  final double _cardHeight = 100;
  final double _verticalSpacing = 30;
  
  final double _col0X = 30;
  final double _col1X = 260;
  final double _col2X = 490;

  // Yellow/Amber connection color
  final Color _connectionColor = const Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _initDiagram();
  }

  void _initDiagram() {
    _stackServices = widget.services.where((s) => s.stackId == widget.stack.id).toList();
    _adjList = {};
    _nodes = {};
    _ingressHosts = {};
    
    _column0Items = [];
    _column1Items = [];
    _column2Items = [];

    if (_stackServices.isEmpty) return;

    final serviceNames = _stackServices.map((s) => s.name).toList();
    final blocks = _extractServiceBlocks(widget.stack.rawComposeFile, serviceNames);

    // Parse ingress host for each service
    for (final s in _stackServices) {
      final block = blocks[s.name] ?? '';
      final host = _getIngressHost(block);
      if (host != null) {
        _ingressHosts[s.name] = host;
      }
    }

    final hasIngress = _ingressHosts.isNotEmpty;

    // List of visual items representing containers (Tasks or Service placeholders)
    final List<Map<String, dynamic>> visualItems = [];

    // Create virtual Caddy Ingress if present
    if (hasIngress) {
      visualItems.add({
        'id': 'virtual-caddy-ingress',
        'name': 'Caddy Ingress',
        'service': Service(
          id: 'virtual-caddy-ingress',
          stackId: widget.stack.id,
          name: 'Caddy Ingress',
          image: 'caddy:latest',
          ports: ['80', '443'],
        ),
        'task': null,
        'displayName': 'Caddy Ingress',
        'column': 0,
      });
    }

    // Map each service to its containers (tasks)
    for (final s in _stackServices) {
      final serviceTasks = widget.tasks.where((t) => t.serviceId == s.id).toList();
      final isWebService = _ingressHosts.containsKey(s.name);
      
      // Determine column: 1 for web/sources, 2 for sinks/DBs
      int col = 2;
      if (isWebService) {
        col = 1;
      } else {
        // If connected by any web service, put in Column 2.
        bool connectedByWebService = false;
        for (final ws in _stackServices) {
          if (_ingressHosts.containsKey(ws.name) && _hasConnection(blocks[ws.name] ?? '', s.name)) {
            connectedByWebService = true;
            break;
          }
        }
        if (connectedByWebService) {
          col = 2;
        } else {
          final inDeg = _getInDegree(s.name, _stackServices, blocks);
          final outDeg = _getOutDegree(s.name, _stackServices, blocks);
          col = (inDeg <= outDeg) ? 1 : 2;
        }
      }

      if (serviceTasks.isEmpty) {
        // Service placeholder if no active containers
        visualItems.add({
          'id': 'service-${s.id}',
          'name': s.name,
          'service': s,
          'task': null,
          'displayName': s.name,
          'column': col,
        });
      } else {
        // Create one node card per active container instance!
        for (int i = 0; i < serviceTasks.length; i++) {
          final task = serviceTasks[i];
          final containerSuffix = serviceTasks.length > 1 ? ' (${i + 1})' : '';
          visualItems.add({
            'id': 'task-${task.id}',
            'name': s.name,
            'service': s,
            'task': task,
            'displayName': '${s.name}$containerSuffix',
            'column': col,
          });
        }
      }
    }

    // Split by columns
    _column0Items.addAll(visualItems.where((item) => item['column'] == 0));
    _column1Items.addAll(visualItems.where((item) => item['column'] == 1));
    _column2Items.addAll(visualItems.where((item) => item['column'] == 2));

    final count0 = _column0Items.length;
    final count1 = _column1Items.length;
    final count2 = _column2Items.length;

    final double h0 = count0 * _cardHeight + (count0 - 1).clamp(0, 99) * _verticalSpacing;
    final double h1 = count1 * _cardHeight + (count1 - 1).clamp(0, 99) * _verticalSpacing;
    final double h2 = count2 * _cardHeight + (count2 - 1).clamp(0, 99) * _verticalSpacing;

    double maxColumnHeight = h1 > h2 ? h1 : h2;
    if (h0 > maxColumnHeight) maxColumnHeight = h0;

    _containerHeight = maxColumnHeight + 120;

    final double startTop0 = (_containerHeight - h0) / 2;
    final double startTop1 = (_containerHeight - h1) / 2;
    final double startTop2 = (_containerHeight - h2) / 2;

    // Position nodes in Column 0
    for (int i = 0; i < _column0Items.length; i++) {
      final item = _column0Items[i];
      final id = item['id'] as String;
      _nodes[id] = DiagramNode(
        service: item['service'] as Service,
        task: item['task'] as Task?,
        displayName: item['displayName'] as String,
        column: 0,
        index: i,
        x: _col0X,
        y: startTop0 + i * (_cardHeight + _verticalSpacing),
      );
    }

    // Position nodes in Column 1
    for (int i = 0; i < _column1Items.length; i++) {
      final item = _column1Items[i];
      final id = item['id'] as String;
      _nodes[id] = DiagramNode(
        service: item['service'] as Service,
        task: item['task'] as Task?,
        displayName: item['displayName'] as String,
        column: 1,
        index: i,
        x: _col1X,
        y: startTop1 + i * (_cardHeight + _verticalSpacing),
      );
    }

    // Position nodes in Column 2
    for (int i = 0; i < _column2Items.length; i++) {
      final item = _column2Items[i];
      final id = item['id'] as String;
      _nodes[id] = DiagramNode(
        service: item['service'] as Service,
        task: item['task'] as Task?,
        displayName: item['displayName'] as String,
        column: 2,
        index: i,
        x: _col2X,
        y: startTop2 + i * (_cardHeight + _verticalSpacing),
      );
    }

    // Initialize adjacency list at node container level
    _adjList = {for (var id in _nodes.keys) id: []};

    // Draw network connection arrows between container nodes
    _nodes.forEach((sourceId, sourceNode) {
      if (sourceNode.service.name == 'Caddy Ingress') {
        // Connect Caddy Ingress to all Column 1 web container nodes
        _nodes.forEach((targetId, targetNode) {
          if (targetNode.column == 1 && _ingressHosts.containsKey(targetNode.service.name)) {
            _adjList[sourceId]!.add(targetId);
          }
        });
      } else {
        // Connect to target containers if the compose defines a relationship
        final blockText = blocks[sourceNode.service.name] ?? '';
        _nodes.forEach((targetId, targetNode) {
          if (sourceNode.service.name == targetNode.service.name) return;

          if (_hasConnection(blockText, targetNode.service.name)) {
            _adjList[sourceId]!.add(targetId);
          }
        });
      }
    });
  }

  int _getInDegree(String serviceName, List<Service> allServices, Map<String, String> blocks) {
    int count = 0;
    for (final s in allServices) {
      if (s.name == serviceName) continue;
      if (_hasConnection(blocks[s.name] ?? '', serviceName)) {
        count++;
      }
    }
    return count;
  }

  int _getOutDegree(String serviceName, List<Service> allServices, Map<String, String> blocks) {
    int count = 0;
    final block = blocks[serviceName] ?? '';
    for (final s in allServices) {
      if (s.name == serviceName) continue;
      if (_hasConnection(block, s.name)) {
        count++;
      }
    }
    return count;
  }

  Map<String, String> _extractServiceBlocks(String yamlContent, List<String> serviceNames) {
    final Map<String, String> blocks = {};
    if (yamlContent.isEmpty) return blocks;

    final lines = yamlContent.split('\n');

    String extractBlock(int startIdx, int baseIndent) {
      final blockLines = <String>[];
      for (int i = startIdx + 1; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        final indent = line.length - line.trimLeft().length;
        if (indent <= baseIndent) {
          break;
        }
        blockLines.add(line);
      }
      return blockLines.join('\n');
    }

    // 1. Extract raw blocks
    for (final name in serviceNames) {
      int startIdx = -1;
      int nameIndent = -1;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        if (trimmed == '$name:') {
          startIdx = i;
          nameIndent = line.length - line.trimLeft().length;
          break;
        }
      }

      if (startIdx != -1) {
        blocks[name] = extractBlock(startIdx, nameIndent);
      }
    }

    // 2. Resolve anchors (e.g. *service-n8n)
    for (final name in serviceNames) {
      final blockText = blocks[name] ?? '';
      final anchorRegExp = RegExp(r'\*[\w\-]+');
      final match = anchorRegExp.firstMatch(blockText);
      if (match != null) {
        final anchorName = match.group(0)!.substring(1);
        int anchorIdx = -1;
        int anchorIndent = -1;
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('&$anchorName')) {
            anchorIdx = i;
            anchorIndent = line.length - line.trimLeft().length;
            break;
          }
        }
        if (anchorIdx != -1) {
          final anchorBlock = extractBlock(anchorIdx, anchorIndent);
          blocks[name] = blockText + '\n' + anchorBlock;
        }
      }
    }

    return blocks;
  }

  bool _hasConnection(String serviceBlockText, String targetServiceName) {
    final regex = RegExp('\\b${RegExp.escape(targetServiceName)}\\b');
    return regex.hasMatch(serviceBlockText);
  }

  String? _getIngressHost(String serviceBlockText) {
    final regex = RegExp(r'ingress\.host\s*==\s*([a-zA-Z0-9\.\-_]+)');
    final match = regex.firstMatch(serviceBlockText);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  String _getServiceStatus(Service service) {
    if (service.name == 'Caddy Ingress') return 'running';
    final serviceTasks = widget.tasks.where((t) => t.serviceId == service.id).toList();
    if (serviceTasks.isEmpty) {
      return 'unknown';
    }
    if (serviceTasks.any((t) => t.status.toLowerCase() == 'running')) {
      return 'running';
    }
    if (serviceTasks.any((t) => t.status.toLowerCase() == 'starting' || t.status.toLowerCase() == 'pending')) {
      return 'starting';
    }
    return 'down';
  }

  String _getStatusDotColor(String status) {
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
        return '#10b981';
      case 'pending':
      case 'starting':
        return '#f59e0b';
      case 'dead':
      case 'down':
        return '#ef4444';
      default:
        return '#6b7280';
    }
  }

  String _truncateImage(String img) {
    if (img.length > 25) {
      return img.substring(0, 22) + '...';
    }
    return img;
  }

  String _getNodeIp(String nodeId) {
    final node = widget.nodes.firstWhere((n) => n.id == nodeId, orElse: () => Node(id: '', ip: '', role: '', status: ''));
    return node.ip.isNotEmpty ? node.ip : 'localhost';
  }

  String _getTaskPublicEndpoint(Service service, Task task) {
    if (service.ports.isEmpty) return 'Internal';
    final ip = _getNodeIp(task.nodeId);
    final host = (ip == '127.0.0.1') ? 'localhost' : ip;
    
    final endpoints = <String>[];
    for (final portMapping in service.ports) {
      final parts = portMapping.split(':');
      if (parts.isEmpty) continue;
      String? hostPort;
      if (parts.length >= 2) {
        hostPort = parts[parts.length - 2];
      } else {
        hostPort = parts.first;
      }
      if (hostPort.isNotEmpty) {
        endpoints.add('$host:$hostPort');
      }
    }
    return endpoints.isNotEmpty ? endpoints.join(', ') : 'Internal';
  }

  // ─── Export Functions ─────────────────────────────────────────────

  void _downloadFile(List<int> bytes, String filename, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<Uint8List?> _capturePngBytes() async {
    try {
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return byteData.buffer.asUint8List();
    } catch (e) {
      print('Capture PNG error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture PNG: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<void> _exportPng() async {
    final bytes = await _capturePngBytes();
    if (bytes != null) {
      _downloadFile(bytes, '${widget.stack.name}.png', 'image/png');
    }
  }

  Future<void> _exportJpg() async {
    final pngBytes = await _capturePngBytes();
    if (pngBytes == null) return;

    try {
      final completer = Completer<Uint8List>();
      final img = html.ImageElement();
      final blob = html.Blob([pngBytes], 'image/png');
      final url = html.Url.createObjectUrlFromBlob(blob);
      img.src = url;

      img.onLoad.listen((_) async {
        try {
          final canvas = html.CanvasElement(width: img.naturalWidth, height: img.naturalHeight);
          final ctx = canvas.context2D;

          // Draw solid white background for JPEG
          ctx.fillStyle = '#FFFFFF';
          ctx.fillRect(0, 0, img.naturalWidth, img.naturalHeight);
          ctx.drawImage(img, 0, 0);

          html.Url.revokeObjectUrl(url);

          final jpegBlob = await canvas.toBlob('image/jpeg', 0.9);
          final reader = html.FileReader();
          reader.onLoadEnd.listen((_) {
            final buffer = reader.result as ByteBuffer;
            completer.complete(buffer.asUint8List());
          });
          reader.readAsArrayBuffer(jpegBlob);
        } catch (e) {
          completer.completeError(e);
        }
      });

      img.onError.listen((err) {
        html.Url.revokeObjectUrl(url);
        completer.completeError('Failed to load image element');
      });

      final jpgBytes = await completer.future;
      _downloadFile(jpgBytes, '${widget.stack.name}.jpg', 'image/jpeg');
    } catch (e) {
      print('Export JPEG error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export JPEG: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportPdf() async {
    final pngBytes = await _capturePngBytes();
    if (pngBytes == null) return;

    try {
      final pdf = pw.Document();
      final image = pw.MemoryImage(pngBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      _downloadFile(pdfBytes, '${widget.stack.name}.pdf', 'application/pdf');
    } catch (e) {
      print('Export PDF error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _exportSvg() {
    try {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final bgColor = isDark ? '#1E293B' : '#FFFFFF';
      final cardBgColor = isDark ? '#0F172A' : '#F8FAFC';
      final cardStrokeColor = isDark ? '#334155' : '#CBD5E1';
      final textColor = isDark ? '#FFFFFF' : '#0F172A';
      final imageTextColor = isDark ? '#94A3B8' : '#64748B';
      final primaryBlue = '#3B82F6';
      
      final connectionColorHex = '#F59E0B';

      final buffer = StringBuffer();
      buffer.writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$_canvasWidth" height="$_containerHeight" viewBox="0 0 $_canvasWidth $_containerHeight">');
      
      // Background
      buffer.writeln('  <rect width="100%" height="100%" fill="$bgColor" rx="12" />');
      
      // Title
      buffer.writeln('  <text x="24" y="32" font-family="system-ui, -apple-system, sans-serif" font-size="16" font-weight="bold" fill="$textColor">${widget.stack.name} Stack Diagram</text>');

      // Connections
      _adjList.forEach((sourceId, targets) {
        final nodeA = _nodes[sourceId];
        if (nodeA == null) return;

        for (final targetId in targets) {
          final nodeB = _nodes[targetId];
          if (nodeB == null) return;

          double outX, outY, inX, inY;
          int arrowDir;

          if (nodeA.column < nodeB.column) {
            outX = nodeA.x + _cardWidth;
            outY = nodeA.y + _cardHeight / 2;
            inX = nodeB.x;
            inY = nodeB.y + _cardHeight / 2;
            arrowDir = 1;
          } else if (nodeA.column > nodeB.column) {
            outX = nodeA.x;
            outY = nodeA.y + _cardHeight / 2;
            inX = nodeB.x + _cardWidth;
            inY = nodeB.y + _cardHeight / 2;
            arrowDir = -1;
          } else { // nodeA.column == nodeB.column
            outX = nodeA.x + _cardWidth;
            outY = nodeA.y + _cardHeight / 2;
            inX = nodeB.x + _cardWidth;
            inY = nodeB.y + _cardHeight / 2;
            arrowDir = -1;
          }

          String pathData;
          if (nodeA.column < nodeB.column) {
            pathData = 'M $outX $outY C ${outX + 40} $outY ${inX - 40} $inY $inX $inY';
          } else if (nodeA.column > nodeB.column) {
            pathData = 'M $outX $outY C ${outX - 40} $outY ${inX + 40} $inY $inX $inY';
          } else {
            pathData = 'M $outX $outY C ${outX + 40} $outY ${inX + 40} $inY $inX $inY';
          }

          buffer.writeln('  <path d="$pathData" stroke="$connectionColorHex" stroke-width="2.5" fill="none" />');

          // Arrow
          String points;
          if (arrowDir == 1) {
            points = '${inX},${inY} ${inX - 8},${inY - 5} ${inX - 8},${inY + 5}';
          } else {
            points = '${inX},${inY} ${inX + 8},${inY - 5} ${inX + 8},${inY + 5}';
          }
          buffer.writeln('  <polygon points="$points" fill="$connectionColorHex" />');
        }
      });

      // Node cards
      _nodes.forEach((id, node) {
        final service = node.service;
        final status = _getServiceStatus(service);
        final statusColor = _getStatusDotColor(status);
        
        final ingressHost = _ingressHosts[service.name];

        buffer.writeln('  <rect x="${node.x}" y="${node.y}" width="$_cardWidth" height="$_cardHeight" rx="10" fill="$cardBgColor" stroke="$cardStrokeColor" stroke-width="1.5" />');
        
        // Title row
        buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 20}" font-family="system-ui, -apple-system, sans-serif" font-size="12" font-weight="700" fill="$textColor">${node.displayName}</text>');
        buffer.writeln('  <circle cx="${node.x + _cardWidth - 14}" cy="${node.y + 16}" r="3.5" fill="$statusColor" />');
        
        // Image row
        buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 35}" font-family="system-ui, -apple-system, sans-serif" font-size="8.5" fill="$imageTextColor">${_truncateImage(service.image)}</text>');
        
        // Network/Ports/Ingress row
        if (service.name == 'Caddy Ingress') {
          buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 52}" font-family="system-ui, -apple-system, sans-serif" font-size="8" font-weight="600" fill="$primaryBlue">Ports: 80, 443</text>');
          final domainsString = _ingressHosts.values.join(', ');
          buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 68}" font-family="system-ui, -apple-system, sans-serif" font-size="8" font-weight="600" fill="$primaryBlue">${_truncateImage(domainsString)}</text>');
          buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 84}" font-family="system-ui, -apple-system, sans-serif" font-size="8" fill="$imageTextColor">Load Balancer</text>');
        } else {
          final ipText = node.task != null ? node.task!.containerIp : 'No active container';
          final pubPortsText = node.task != null ? _getTaskPublicEndpoint(service, node.task!) : 'Internal';
          
          buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 52}" font-family="system-ui, -apple-system, sans-serif" font-size="8" fill="$textColor">Int IP: $ipText</text>');
          buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 68}" font-family="system-ui, -apple-system, sans-serif" font-size="8" font-weight="600" fill="$primaryBlue">Pub: $pubPortsText</text>');
          
          if (ingressHost != null) {
            buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 84}" font-family="system-ui, -apple-system, sans-serif" font-size="8" font-weight="600" fill="$primaryBlue">🌐 $ingressHost</text>');
          } else {
            buffer.writeln('  <text x="${node.x + 12}" y="${node.y + 84}" font-family="system-ui, -apple-system, sans-serif" font-size="8" fill="$imageTextColor">Active container</text>');
          }
        }
      });

      buffer.writeln('</svg>');
      
      final svgString = buffer.toString();
      final svgBytes = utf8.encode(svgString);
      _downloadFile(svgBytes, '${widget.stack.name}.svg', 'image/svg+xml');
    } catch (e) {
      print('Export SVG error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export SVG: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ─── Widget Builders ──────────────────────────────────────────────

  Widget _buildCard(DiagramNode node, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final service = node.service;
    final status = _getServiceStatus(service);
    final statusColor = GubernatorTheme.statusColor(status);
    final ingressHost = _ingressHosts[service.name];

    return Container(
      width: _cardWidth,
      height: _cardHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          Text(
            _truncateImage(service.image),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 9.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          if (service.name == 'Caddy Ingress') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ports: 80, 443',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Text(
              'Domains: ${_ingressHosts.values.join(", ")}',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Load Balancer',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 8.5),
            ),
          ] else ...[
            Row(
              children: [
                Text(
                  'Int IP: ',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                Expanded(
                  child: Text(
                    node.task != null ? node.task!.containerIp : 'No container',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.5, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Pub: ',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                Expanded(
                  child: Text(
                    node.task != null ? _getTaskPublicEndpoint(service, node.task!) : 'Internal',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (ingressHost != null) ...[
              Row(
                children: [
                  Icon(Icons.language, size: 11, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      ingressHost,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            ] else ...[
              Text(
                'Active container',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ]
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _canvasWidth + 60, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.schema_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.stack.name} - Schema',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.download),
                    tooltip: 'Export Diagram',
                    onSelected: (val) {
                      if (val == 'png') _exportPng();
                      if (val == 'jpg') _exportJpg();
                      if (val == 'pdf') _exportPdf();
                      if (val == 'svg') _exportSvg();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'png', child: Text('Export as PNG')),
                      PopupMenuItem(value: 'jpg', child: Text('Export as JPEG')),
                      PopupMenuItem(value: 'pdf', child: Text('Export as PDF')),
                      PopupMenuItem(value: 'svg', child: Text('Export as SVG')),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content Area
            Expanded(
              child: _stackServices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.layers_clear, size: 48, color: theme.disabledColor),
                          const SizedBox(height: 16),
                          Text('No services found in this stack', style: theme.textTheme.titleMedium),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: RepaintBoundary(
                          key: _repaintBoundaryKey,
                          child: Container(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            width: _canvasWidth,
                            height: _containerHeight,
                            child: Stack(
                              children: [
                                // Connection lines layer
                                CustomPaint(
                                  size: Size(_canvasWidth, _containerHeight),
                                  painter: DiagramPainter(
                                    nodes: _nodes,
                                    adjList: _adjList,
                                    connectionColor: _connectionColor,
                                  ),
                                ),
                                // Node cards layer
                                ..._nodes.values.map((node) {
                                  return Positioned(
                                    left: node.x,
                                    top: node.y,
                                    child: _buildCard(node, theme),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiagramPainter extends CustomPainter {
  final Map<String, DiagramNode> nodes;
  final Map<String, List<String>> adjList;
  final Color connectionColor;

  DiagramPainter({
    required this.nodes,
    required this.adjList,
    required this.connectionColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = connectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final arrowPaint = Paint()
      ..color = connectionColor
      ..style = PaintingStyle.fill;

    const double cardWidth = 180;
    const double cardHeight = 100;

    adjList.forEach((sourceId, targets) {
      final nodeA = nodes[sourceId];
      if (nodeA == null) return;

      for (final targetId in targets) {
        final nodeB = nodes[targetId];
        if (nodeB == null) return;

        double outX, outY, inX, inY;
        int arrowDir;

        if (nodeA.column < nodeB.column) {
          outX = nodeA.x + cardWidth;
          outY = nodeA.y + cardHeight / 2;
          inX = nodeB.x;
          inY = nodeB.y + cardHeight / 2;
          arrowDir = 1;
        } else if (nodeA.column > nodeB.column) {
          outX = nodeA.x;
          outY = nodeA.y + cardHeight / 2;
          inX = nodeB.x + cardWidth;
          inY = nodeB.y + cardHeight / 2;
          arrowDir = -1;
        } else { // nodeA.column == nodeB.column
          outX = nodeA.x + cardWidth;
          outY = nodeA.y + cardHeight / 2;
          inX = nodeB.x + cardWidth;
          inY = nodeB.y + cardHeight / 2;
          arrowDir = -1;
        }

        final path = Path();
        path.moveTo(outX, outY);
        
        if (nodeA.column < nodeB.column) {
          path.cubicTo(outX + 40, outY, inX - 40, inY, inX, inY);
        } else if (nodeA.column > nodeB.column) {
          path.cubicTo(outX - 40, outY, inX + 40, inY, inX, inY);
        } else {
          path.cubicTo(outX + 40, outY, inX + 40, inY, inX, inY);
        }
        
        canvas.drawPath(path, paint);

        final arrowPath = Path();
        if (arrowDir == 1) {
          arrowPath.moveTo(inX, inY);
          arrowPath.lineTo(inX - 8, inY - 5);
          arrowPath.lineTo(inX - 8, inY + 5);
        } else {
          arrowPath.moveTo(inX, inY);
          arrowPath.lineTo(inX + 8, inY - 5);
          arrowPath.lineTo(inX + 8, inY + 5);
        }
        arrowPath.close();
        canvas.drawPath(arrowPath, arrowPaint);
      }
    });
  }

  @override
  bool shouldRepaint(covariant DiagramPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.adjList != adjList || oldDelegate.connectionColor != connectionColor;
  }
}
