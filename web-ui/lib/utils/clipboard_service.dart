import 'dart:html' as html;
import 'package:flutter/services.dart';

class ClipboardService {
  /// Copies text to browser clipboard with multiple fallbacks:
  /// 1. Synchronous execCommand via DOM textarea
  /// 2. Flutter Clipboard API
  /// 3. Modern Web Navigator Clipboard API
  static Future<bool> copy(String text) async {
    if (text.isEmpty) return false;

    // 1. Try DOM execCommand FIRST (most reliable on plain HTTP / self-hosted IPs)
    final syncSuccess = copySync(text);

    // 2. Also write to Flutter Clipboard engine
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}

    // 3. Also write to Navigator Clipboard if available
    try {
      if (html.window.navigator.clipboard != null) {
        await html.window.navigator.clipboard!.writeText(text);
        return true;
      }
    } catch (_) {}

    return syncSuccess;
  }

  /// Synchronous copy using document.execCommand with direct clipboardData injection
  static bool copySync(String text) {
    if (text.isEmpty) return false;
    try {
      bool copyEventHandled = false;
      void onCopy(html.Event e) {
        if (e is html.ClipboardEvent) {
          e.preventDefault();
          e.stopImmediatePropagation();
          e.clipboardData?.setData('text/plain', text);
          copyEventHandled = true;
        }
      }

      // Add a high-priority capture-phase listener to guarantee our exact text is written
      html.document.addEventListener('copy', onCopy, true);

      final textarea = html.TextAreaElement()
        ..value = text
        ..style.position = 'fixed'
        ..style.top = '0'
        ..style.left = '0'
        ..style.width = '2em'
        ..style.height = '2em'
        ..style.padding = '0'
        ..style.border = 'none'
        ..style.outline = 'none'
        ..style.boxShadow = 'none'
        ..style.background = 'transparent'
        ..style.opacity = '0'
        ..style.pointerEvents = 'none';

      html.document.body?.append(textarea);
      textarea.focus();
      textarea.select();
      textarea.setSelectionRange(0, text.length);

      final execResult = html.document.execCommand('copy');
      textarea.remove();

      html.document.removeEventListener('copy', onCopy, true);

      return execResult == true || copyEventHandled;
    } catch (_) {
      return false;
    }
  }

  /// Reads text from browser clipboard with web API & Flutter fallback.
  static Future<String?> paste() async {
    try {
      if (html.window.navigator.clipboard != null) {
        final text = await html.window.navigator.clipboard!.readText();
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    } catch (_) {}

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        return data.text;
      }
    } catch (_) {}
    return null;
  }
}
