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

  /// Synchronous copy using document.execCommand
  static bool copySync(String text) {
    if (text.isEmpty) return false;
    try {
      final textarea = html.TextAreaElement()
        ..value = text
        ..setAttribute('readonly', '')
        ..style.position = 'fixed'
        ..style.top = '0'
        ..style.left = '0'
        ..style.width = '2em'
        ..style.height = '2em'
        ..style.padding = '0'
        ..style.border = 'none'
        ..style.outline = 'none'
        ..style.boxShadow = 'none'
        ..style.background = 'transparent';
      html.document.body?.append(textarea);
      textarea.select();
      textarea.setSelectionRange(0, text.length);
      final success = html.document.execCommand('copy');
      textarea.remove();
      return success == true;
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
