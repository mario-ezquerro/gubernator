import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:google_fonts/google_fonts.dart';

class ShellDialog extends StatefulWidget {
  final String taskId;
  final String containerName;
  final bool isNode;

  const ShellDialog({
    super.key,
    required this.taskId,
    required this.containerName,
    this.isNode = false,
  });

  @override
  State<ShellDialog> createState() => _ShellDialogState();
}

class _ShellDialogState extends State<ShellDialog> {
  late final Terminal terminal;
  WebSocketChannel? channel;

  @override
  void initState() {
    super.initState();
    terminal = Terminal();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final wsProtocol = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    // If running in debug mode (flutter run -d chrome), hardcode the local backend port 4001
    // Otherwise use the same host/port the web app was served from.
    var wsHost = Uri.base.host;
    var wsPort = Uri.base.port;
    if (wsPort == 0 || Uri.base.scheme == 'data' || wsHost == 'localhost') {
      // Data URI means it might be a weird environment, or localhost means dev.
      // Usually in prod wsPort is the right one.
      // Let's fallback to the same URL logic we might use elsewhere, but Uri.base is standard.
    }
    
    // For local dev, hardcode backend port if we are on a flutter dev server port (like 50000+)
    if (wsPort > 10000) {
      wsPort = 4001;
    }

    final pathPrefix = widget.isNode ? '/api/node' : '/api/task';
    final wsUri = Uri(
      scheme: wsProtocol,
      host: wsHost.isEmpty ? 'localhost' : wsHost,
      port: wsPort,
      path: '$pathPrefix/${widget.taskId}/shell',
    );

    try {
      channel = WebSocketChannel.connect(wsUri);
      
      channel!.stream.listen(
        (message) {
          if (message is String) {
            terminal.write(message);
          } else if (message is List<int>) {
            terminal.write(utf8.decode(message, allowMalformed: true));
          }
        },
        onError: (error) {
          terminal.write('\r\n\x1b[31mConnection error: $error\x1b[0m\r\n');
        },
        onDone: () {
          terminal.write('\r\n\x1b[33mConnection closed.\x1b[0m\r\n');
        },
      );

      terminal.onOutput = (String data) {
        channel?.sink.add(data);
      };
      
    } catch (e) {
      terminal.write('\r\n\x1b[31mFailed to connect: $e\x1b[0m\r\n');
    }
  }

  @override
  void dispose() {
    channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Shell: ${widget.containerName}'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        color: Colors.black,
        child: TerminalView(
          terminal,
          textStyle: TerminalStyle(
            fontFamily: GoogleFonts.robotoMono().fontFamily ?? 'Courier New',
            fontSize: 14,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
