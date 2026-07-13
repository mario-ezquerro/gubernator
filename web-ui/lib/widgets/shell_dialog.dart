import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final TerminalController _controller;
  WebSocketChannel? channel;

  @override
  void initState() {
    super.initState();
    terminal = Terminal();
    _controller = TerminalController();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final wsProtocol = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    var wsHost = Uri.base.host;
    var wsPort = Uri.base.port;
    if (wsPort == 0 || Uri.base.scheme == 'data' || wsHost == 'localhost') {
      // Data URI means it might be a weird environment, or localhost means dev.
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

  Future<void> _handleCopy() async {
    final selection = _controller.selection;
    if (selection != null) {
      var text = terminal.buffer.getText(selection);
      text = text.replaceAll('\x00', '').trim();
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
        _showSnackBar('Copied selection to clipboard!');
        return;
      }
    }
    // Fallback: Copy all text
    var text = terminal.buffer.getText();
    text = text.replaceAll('\x00', '').trim();
    await Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('Copied all terminal output!');
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      channel?.sink.add(data.text!);
      _showSnackBar('Pasted from clipboard!');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    channel?.sink.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Shell: ${widget.containerName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy text (Selection or All)',
                onPressed: _handleCopy,
              ),
              IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Paste from clipboard',
                onPressed: _handlePaste,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        color: Colors.black,
        child: Focus(
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (event is KeyDownEvent) {
              final isControlPressed = HardwareKeyboard.instance.isControlPressed;
              final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
              final isShortcutModifier = isControlPressed || isMetaPressed;

              if (isShortcutModifier && event.logicalKey == LogicalKeyboardKey.keyC) {
                final selection = _controller.selection;
                if (selection != null) {
                  var text = terminal.buffer.getText(selection);
                  text = text.replaceAll('\x00', '').trim();
                  if (text.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: text));
                    _showSnackBar('Copied to clipboard!');
                    return KeyEventResult.handled;
                  }
                }
              }

              if (isShortcutModifier && event.logicalKey == LogicalKeyboardKey.keyV) {
                _handlePaste();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: TerminalView(
            terminal,
            controller: _controller,
            textStyle: TerminalStyle(
              fontFamily: GoogleFonts.robotoMono().fontFamily ?? 'Courier New',
              fontSize: 14,
            ),
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
