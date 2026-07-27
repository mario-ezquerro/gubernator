import 'package:flutter/material.dart';

/// Jaeger traces page — embeds the Jaeger iframe.
class JaegerPage extends StatelessWidget {
  const JaegerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: HtmlElementView(viewType: 'jaeger-iframe'),
      ),
    );
  }
}
