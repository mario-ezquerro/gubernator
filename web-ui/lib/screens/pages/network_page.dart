import 'package:flutter/material.dart';

/// Network monitoring page — embeds the Grafana Network Monitor iframe.
class NetworkPage extends StatelessWidget {
  const NetworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: HtmlElementView(viewType: 'grafana-network-iframe'),
      ),
    );
  }
}
