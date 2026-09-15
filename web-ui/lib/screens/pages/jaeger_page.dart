import 'package:flutter/material.dart';

/// Jaeger traces page — embeds the Jaeger iframe with stable RepaintBoundary.
class JaegerPage extends StatelessWidget {
  const JaegerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: RepaintBoundary(
          key: ValueKey('jaeger-iframe-repaint-boundary'),
          child: HtmlElementView(
            key: ValueKey('jaeger-iframe-element-view'),
            viewType: 'jaeger-iframe',
          ),
        ),
      ),
    );
  }
}
