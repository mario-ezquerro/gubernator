import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/clipboard_service.dart';

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
  late final FocusNode _focusNode;
  final TextEditingController _inputController = TextEditingController();
  WebSocketChannel? channel;

  @override
  void initState() {
    super.initState();
    terminal = Terminal();
    _controller = TerminalController();
    _focusNode = FocusNode();
    _connectWebSocket();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
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

  String _getTerminalText() {
    final selection = _controller.selection;
    if (selection != null) {
      try {
        final selected = terminal.buffer.getText(selection);
        final clean = selected.replaceAll('\x00', '').trim();
        if (clean.isNotEmpty) return clean;
      } catch (_) {}
    }

    final sb = StringBuffer();
    try {
      for (var i = 0; i < terminal.buffer.lines.length; i++) {
        final lineText = terminal.buffer.lines[i].toString();
        final cleanLine = lineText.replaceAll('\x00', '').trimRight();
        if (cleanLine.isNotEmpty) {
          sb.writeln(cleanLine);
        }
      }
    } catch (_) {}
    return sb.toString().trim();
  }

  void _handleCopy() {
    final text = _getTerminalText();
    if (text.isEmpty) {
      _showSnackBar('No hay texto en la terminal para copiar', isError: true);
      return;
    }

    // Try synchronous execCommand FIRST
    final ok = ClipboardService.copySync(text);
    if (ok) {
      _showSnackBar('¡Texto copiado al portapapeles!');
    } else {
      ClipboardService.copy(text).then((success) {
        if (success) {
          _showSnackBar('¡Texto copiado al portapapeles!');
        } else {
          _showSnackBar('Error al copiar texto', isError: true);
        }
      });
    }
  }

  Future<void> _handlePaste() async {
    final text = await ClipboardService.paste();
    if (text != null && text.isNotEmpty) {
      channel?.sink.add(text);
      _showSnackBar('¡Pegado desde el portapapeles!');
      return;
    }
    // Fallback for HTTP contexts or browser restrictions
    _showPasteDialog();
  }

  void _showPasteDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.content_paste, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Pegar Texto / Comandos'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pega el texto aquí (Ctrl+V / Cmd+V o botón derecho -> Pegar) y pulsa Enviar:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Pega aquí tus comandos o scripts...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Enviar a Terminal'),
            onPressed: () {
              final text = textController.text;
              if (text.isNotEmpty) {
                channel?.sink.add(text);
                _showSnackBar('Comando enviado a la terminal');
              }
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  void _sendQuickCommand() {
    final text = _inputController.text;
    if (text.isNotEmpty) {
      channel?.sink.add('$text\n');
      _inputController.clear();
      _focusNode.requestFocus();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _inputController.dispose();
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
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar'),
                onPressed: _handleCopy,
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Pegar'),
                onPressed: _handlePaste,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.blueAccent),
                tooltip: 'Abrir cuadro para pegar texto largo / script',
                onPressed: _showPasteDialog,
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
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.75,
        color: Colors.black,
        child: Column(
          children: [
            Expanded(
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,
                onKeyEvent: (FocusNode node, KeyEvent event) {
                  if (event is KeyDownEvent) {
                    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
                    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
                    final isShortcutModifier = isControlPressed || isMetaPressed;

                    if (isShortcutModifier && event.logicalKey == LogicalKeyboardKey.keyC) {
                      _handleCopy();
                      return KeyEventResult.handled;
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
                  autofocus: true,
                  textStyle: TerminalStyle(
                    fontFamily: GoogleFonts.robotoMono().fontFamily ?? 'Courier New',
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            // Quick Command Input Bar at bottom of Terminal
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF1E1E1E),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Courier New', fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Comando rápido: escribe o pega aquí (Ctrl+V) y pulsa Enter...',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendQuickCommand(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.lightBlueAccent, size: 18),
                    tooltip: 'Enviar comando (Enter)',
                    onPressed: _sendQuickCommand,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
