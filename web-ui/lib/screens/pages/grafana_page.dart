import 'package:flutter/material.dart';

/// Grafana metrics page — embeds the Grafana iframe.
class GrafanaPage extends StatelessWidget {
  const GrafanaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: HtmlElementView(viewType: 'grafana-iframe'),
      ),
    );
  }
}
