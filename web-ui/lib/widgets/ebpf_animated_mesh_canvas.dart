import 'dart:math' as math;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../../models/models.dart';

/// Interactive 2D Vector Canvas rendering Service Mesh Blocks,
/// Curved Directional Flow Vectors, Animated Travelling Data Particles,
/// and Direct Jaeger Distributed Tracing Integration.
class EbpfAnimatedMeshCanvas extends StatefulWidget {
  final EbpfTopology topology;
  final Function(EbpfTopologyEdge edge)? onSelectEdge;
  final Function(EbpfTopologyNode node)? onSelectNode;

  const EbpfAnimatedMeshCanvas({
    super.key,
    required this.topology,
    this.onSelectEdge,
    this.onSelectNode,
  });

  @override
  State<EbpfAnimatedMeshCanvas> createState() => _EbpfAnimatedMeshCanvasState();
}

class _EbpfAnimatedMeshCanvasState extends State<EbpfAnimatedMeshCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  // Node Positions for dragging & visual layout: Node ID -> Offset
  final Map<String, Offset> _nodePositions = {};

  String? _hoveredNodeId;
  String? _selectedNodeId;
  String? _hoveredEdgeId;
  String? _selectedEdgeId;

  String? _draggingNodeId;

  // Visual filter within canvas
  String _canvasProtocol = 'ALL';
  bool _particlesPaused = false;
  final double _animationSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _calculateInitialPositions(Size canvasSize) {
    final nodes = widget.topology.nodes;
    if (nodes.isEmpty) return;

    final centerX = canvasSize.width / 2;
    final centerY = canvasSize.height / 2;

    // Calculate layout in concentric rings or circle based on node count
    final count = nodes.length;
    final radius = math.min(canvasSize.width, canvasSize.height) * 0.38;

    for (int i = 0; i < count; i++) {
      final node = nodes[i];
      if (!_nodePositions.containsKey(node.id)) {
        // Special placement: Ingress/Caddy at top center, Jaeger/Loki at bottom
        if (node.type == 'ingress' || node.name.contains('caddy')) {
          _nodePositions[node.id] = Offset(centerX, centerY - radius * 0.85);
        } else if (node.name.contains('jaeger')) {
          _nodePositions[node.id] = Offset(centerX - radius * 0.75, centerY + radius * 0.65);
        } else if (node.name.contains('prometheus') || node.name.contains('grafana')) {
          _nodePositions[node.id] = Offset(centerX + radius * 0.75, centerY + radius * 0.65);
        } else if (node.type == 'dns' || node.name.contains('coredns')) {
          _nodePositions[node.id] = Offset(centerX - radius * 0.85, centerY - radius * 0.3);
        } else {
          final angle = (2 * math.pi * i) / count - (math.pi / 2);
          final px = centerX + radius * math.cos(angle);
          final py = centerY + radius * math.sin(angle);
          _nodePositions[node.id] = Offset(px, py);
        }
      }
    }
  }

  void _openJaeger(String? traceId) {
    final host = html.window.location.hostname ?? '127.0.0.1';
    final url = (traceId != null && traceId.isNotEmpty)
        ? 'http://$host:16686/trace/$traceId'
        : 'http://$host:16686/';
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final canvasSize = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 900,
          math.max(520.0, constraints.maxHeight.isFinite ? constraints.maxHeight : 560),
        );

        _calculateInitialPositions(canvasSize);

        final filteredEdges = widget.topology.edges.where((e) {
          if (_canvasProtocol == 'ALL') return true;
          return e.protocol.toUpperCase() == _canvasProtocol.toUpperCase();
        }).toList();

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A), // Premium Deep Slate Mesh Theme
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 1. Grid Background Texture & Vector / Particle Painter
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _MeshVectorPainter(
                        nodes: widget.topology.nodes,
                        edges: filteredEdges,
                        nodePositions: _nodePositions,
                        animationProgress: _particlesPaused ? 0.0 : _animController.value * _animationSpeed,
                        hoveredEdgeId: _hoveredEdgeId,
                        selectedEdgeId: _selectedEdgeId,
                        hoveredNodeId: _hoveredNodeId,
                        selectedNodeId: _selectedNodeId,
                        theme: theme,
                      ),
                    );
                  },
                ),
              ),

              // 2. Interactive Draggable Node Blocks
              ...widget.topology.nodes.map((node) {
                final pos = _nodePositions[node.id] ?? Offset(canvasSize.width / 2, canvasSize.height / 2);
                final isHovered = _hoveredNodeId == node.id;
                final isSelected = _selectedNodeId == node.id;

                return Positioned(
                  left: pos.dx - 90,
                  top: pos.dy - 38,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    onEnter: (_) => setState(() => _hoveredNodeId = node.id),
                    onExit: (_) => setState(() => _hoveredNodeId = null),
                    child: GestureDetector(
                      onPanStart: (details) {
                        setState(() {
                          _draggingNodeId = node.id;
                          _selectedNodeId = node.id;
                        });
                        widget.onSelectNode?.call(node);
                      },
                      onPanUpdate: (details) {
                        if (_draggingNodeId == node.id) {
                          setState(() {
                            final current = _nodePositions[node.id] ?? pos;
                            final newX = (current.dx + details.delta.dx).clamp(95.0, canvasSize.width - 95.0);
                            final newY = (current.dy + details.delta.dy).clamp(45.0, canvasSize.height - 45.0);
                            _nodePositions[node.id] = Offset(newX, newY);
                          });
                        }
                      },
                      onPanEnd: (_) => setState(() => _draggingNodeId = null),
                      onTap: () {
                        setState(() => _selectedNodeId = node.id);
                        widget.onSelectNode?.call(node);
                      },
                      child: _buildNodeBlockWidget(node, isHovered, isSelected, theme),
                    ),
                  ),
                );
              }),

              // 3. Top Canvas Floating Toolbar & Protocol Filter
              Positioned(
                top: 14,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    // Canvas Title Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hub, size: 16, color: Color(0xFF06B6D4)),
                          const SizedBox(width: 8),
                          const Text(
                            'eBPF LIVE VECTOR MESH',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'KERNEL ACTIVE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Protocol Filter Chips
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFilterChip('ALL', Colors.cyanAccent),
                          _buildFilterChip('HTTP', Colors.blueAccent),
                          _buildFilterChip('gRPC', Colors.purpleAccent),
                          _buildFilterChip('DNS', Colors.greenAccent),
                          _buildFilterChip('REDIS', Colors.orangeAccent),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Jaeger Direct Hub Action Button
                    Tooltip(
                      message: 'Open Jaeger Distributed Tracing (:16686)',
                      child: InkWell(
                        onTap: () => _openJaeger(null),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timeline, size: 14, color: Colors.purpleAccent),
                              SizedBox(width: 6),
                              Text(
                                'JAEGER TRACES',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purpleAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Particle Animation Pause / Resume
                    Tooltip(
                      message: _particlesPaused ? 'Resume Particle Animation' : 'Pause Particle Animation',
                      child: IconButton.filledTonal(
                        iconSize: 16,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _particlesPaused = !_particlesPaused;
                            if (_particlesPaused) {
                              _animController.stop();
                            } else {
                              _animController.repeat();
                            }
                          });
                        },
                        icon: Icon(_particlesPaused ? Icons.play_arrow : Icons.pause),
                      ),
                    ),

                    // Reset Layout
                    Tooltip(
                      message: 'Reset Node Block Positions',
                      child: IconButton.filledTonal(
                        iconSize: 16,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _nodePositions.clear();
                            _calculateInitialPositions(canvasSize);
                          });
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Edge / Node Inspection Floating Drawer (Bottom-Right overlay)
              if (_selectedNodeId != null || _selectedEdgeId != null)
                Positioned(
                  bottom: 14,
                  right: 14,
                  child: _buildInspectorCard(theme),
                ),

              // 5. Canvas Legend Footer
              Positioned(
                bottom: 14,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B132B).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendItem(color: Colors.blueAccent, label: 'HTTP'),
                      SizedBox(width: 10),
                      _LegendItem(color: Colors.purpleAccent, label: 'gRPC / Jaeger'),
                      SizedBox(width: 10),
                      _LegendItem(color: Colors.greenAccent, label: 'DNS'),
                      SizedBox(width: 10),
                      _LegendItem(color: Colors.orangeAccent, label: 'Database/Redis'),
                      SizedBox(width: 10),
                      _LegendItem(color: Colors.redAccent, label: 'Error (5xx/Drop)'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String proto, Color color) {
    final active = _canvasProtocol == proto;
    return InkWell(
      onTap: () => setState(() => _canvasProtocol = proto),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color : Colors.transparent),
        ),
        child: Text(
          proto,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? color : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildNodeBlockWidget(EbpfTopologyNode node, bool isHovered, bool isSelected, ThemeData theme) {
    final isDb = node.type == 'database';
    final isIngress = node.type == 'ingress' || node.name.contains('caddy');
    final isDns = node.type == 'dns';
    final isJaeger = node.name.contains('jaeger');

    IconData icon = Icons.apps;
    Color accentColor = const Color(0xFF06B6D4);
    if (isDb) {
      icon = Icons.storage;
      accentColor = Colors.orangeAccent;
    } else if (isIngress) {
      icon = Icons.alt_route;
      accentColor = Colors.purpleAccent;
    } else if (isDns) {
      icon = Icons.manage_search;
      accentColor = Colors.tealAccent;
    } else if (isJaeger) {
      icon = Icons.timeline;
      accentColor = Colors.purpleAccent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 180,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF1E293B)
            : (isHovered ? const Color(0xFF1E293B).withValues(alpha: 0.95) : const Color(0xFF131D33)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? accentColor
              : (isHovered ? accentColor.withValues(alpha: 0.6) : const Color(0xFF334155)),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          if (isSelected || isHovered)
            BoxShadow(
              color: accentColor.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header: Icon + Name + Type
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      node.ip.isNotEmpty ? node.ip : node.type.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),

          // Mini Metric Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${node.activeFlows} flows',
                style: const TextStyle(fontSize: 9, color: Color(0xFF06B6D4), fontWeight: FontWeight.bold),
              ),
              Text(
                _formatBytesRate(node.inboundBps + node.outboundBps),
                style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorCard(ThemeData theme) {
    if (_selectedNodeId != null) {
      final node = widget.topology.nodes.firstWhere(
        (n) => n.id == _selectedNodeId,
        orElse: () => widget.topology.nodes.first,
      );

      final isJaeger = node.name.contains('jaeger');

      return Container(
        width: 320,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.dns, size: 16, color: Color(0xFF06B6D4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14, color: Colors.white60),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selectedNodeId = null),
                ),
              ],
            ),
            const Divider(height: 14, color: Color(0xFF334155)),
            _buildInspectorRow('Type', node.type.toUpperCase()),
            _buildInspectorRow('IP Address', node.ip.isNotEmpty ? node.ip : 'Host Network'),
            _buildInspectorRow('Active Flows', '${node.activeFlows}'),
            _buildInspectorRow('Inbound Rate', _formatBytesRate(node.inboundBps)),
            _buildInspectorRow('Outbound Rate', _formatBytesRate(node.outboundBps)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: Color(0xFF06B6D4)),
                      foregroundColor: const Color(0xFF06B6D4),
                    ),
                    onPressed: () {
                      _openJaeger(null);
                    },
                    icon: const Icon(Icons.timeline, size: 14),
                    label: Text(
                      isJaeger ? 'Open Jaeger UI' : 'View Traces',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInspectorRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          Text(value, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  String _formatBytesRate(double bps) {
    if (bps >= 1024 * 1024) {
      return "${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s";
    } else if (bps >= 1024) {
      return "${(bps / 1024).toStringAsFixed(1)} KB/s";
    }
    return "${bps.toStringAsFixed(0)} B/s";
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
      ],
    );
  }
}

/// CustomPainter rendering Curved Directional Vectors with Arrows and Animated Travelling Particles
class _MeshVectorPainter extends CustomPainter {
  final List<EbpfTopologyNode> nodes;
  final List<EbpfTopologyEdge> edges;
  final Map<String, Offset> nodePositions;
  final double animationProgress;
  final String? hoveredEdgeId;
  final String? selectedEdgeId;
  final String? hoveredNodeId;
  final String? selectedNodeId;
  final ThemeData theme;

  _MeshVectorPainter({
    required this.nodes,
    required this.edges,
    required this.nodePositions,
    required this.animationProgress,
    this.hoveredEdgeId,
    this.selectedEdgeId,
    this.hoveredNodeId,
    this.selectedNodeId,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle Background Grid Points
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, gridPaint);
      }
    }

    // 2. Draw Vector Curves, Directional Arrows, and Animated Particles
    for (final edge in edges) {
      final srcPos = nodePositions[edge.sourceId];
      final dstPos = nodePositions[edge.targetId];
      if (srcPos == null || dstPos == null) continue;

      final isSelected = edge.id == selectedEdgeId;
      final isHovered = edge.id == hoveredEdgeId;
      final isRelated = edge.sourceId == selectedNodeId || edge.targetId == selectedNodeId;

      final protoColor = _getProtocolColor(edge.protocol);
      final hasErrors = edge.errorRate > 0 || edge.status == 'error';
      final strokeColor = hasErrors ? Colors.redAccent : protoColor;

      // Calculate smooth Bézier curve between nodes
      final dx = dstPos.dx - srcPos.dx;
      final dy = dstPos.dy - srcPos.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 10) continue;

      // Perpendicular control point offset for beautiful curve
      final normal = Offset(-dy / dist, dx / dist);
      // Determine curve direction consistently based on source vs target name hash
      final curveFactor = (edge.sourceId.hashCode > edge.targetId.hashCode ? 1 : -1) * 35.0;
      final midPoint = Offset((srcPos.dx + dstPos.dx) / 2, (srcPos.dy + dstPos.dy) / 2);
      final controlPoint = Offset(midPoint.dx + normal.dx * curveFactor, midPoint.dy + normal.dy * curveFactor);

      final path = Path()
        ..moveTo(srcPos.dx, srcPos.dy)
        ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, dstPos.dx, dstPos.dy);

      // Base vector curve line
      final linePaint = Paint()
        ..color = strokeColor.withValues(alpha: isSelected || isHovered || isRelated ? 0.75 : 0.25)
        ..strokeWidth = isSelected || isHovered ? 2.5 : 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, linePaint);

      // Draw Directional Vector Arrow near 60% of the trajectory
      _drawVectorArrow(canvas, srcPos, controlPoint, dstPos, 0.60, strokeColor);

      // Draw Animated Travelling Data Particles along the curve
      _drawTravellingParticles(canvas, srcPos, controlPoint, dstPos, strokeColor, edge);
    }
  }

  void _drawVectorArrow(Canvas canvas, Offset p0, Offset p1, Offset p2, double t, Color color) {
    // Point on quadratic Bézier at t
    final p = _bezierPoint(p0, p1, p2, t);
    // Tangent derivative vector at t
    final tangent = _bezierTangent(p0, p1, p2, t);
    final angle = math.atan2(tangent.dy, tangent.dx);

    const arrowLength = 9.0;
    const arrowAngle = math.pi / 6;

    final arrowPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final arrowPath = Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(
        p.dx - arrowLength * math.cos(angle - arrowAngle),
        p.dy - arrowLength * math.sin(angle - arrowAngle),
      )
      ..lineTo(
        p.dx - (arrowLength * 0.6) * math.cos(angle),
        p.dy - (arrowLength * 0.6) * math.sin(angle),
      )
      ..lineTo(
        p.dx - arrowLength * math.cos(angle + arrowAngle),
        p.dy - arrowLength * math.sin(angle + arrowAngle),
      )
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  void _drawTravellingParticles(Canvas canvas, Offset p0, Offset p1, Offset p2, Color color, EbpfTopologyEdge edge) {
    // Number of particles proportional to throughput or flows (1 to 3 particles)
    final count = edge.throughputBps > 100000 ? 3 : 2;

    for (int i = 0; i < count; i++) {
      final t = (animationProgress + (i / count)) % 1.0;
      final pos = _bezierPoint(p0, p1, p2, t);

      // Particle outer glow
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(pos, 4.5, glowPaint);

      // Particle core
      final corePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 2.0, corePaint);
    }
  }

  Offset _bezierPoint(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    final x = u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx;
    final y = u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }

  Offset _bezierTangent(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    final dx = 2 * u * (p1.dx - p0.dx) + 2 * t * (p2.dx - p1.dx);
    final dy = 2 * u * (p1.dy - p0.dy) + 2 * t * (p2.dy - p1.dy);
    return Offset(dx, dy);
  }

  Color _getProtocolColor(String proto) {
    switch (proto.toUpperCase()) {
      case 'HTTP':
        return Colors.blueAccent;
      case 'GRPC':
        return Colors.purpleAccent;
      case 'DNS':
        return Colors.greenAccent;
      case 'REDIS':
        return Colors.orangeAccent;
      case 'POSTGRES':
        return Colors.tealAccent;
      case 'TCP':
        return const Color(0xFF06B6D4);
      case 'UDP':
        return Colors.amberAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  @override
  bool shouldRepaint(covariant _MeshVectorPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.hoveredEdgeId != hoveredEdgeId ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.hoveredNodeId != hoveredNodeId ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.edges != edges;
  }
}
