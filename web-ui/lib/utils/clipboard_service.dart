import 'dart:html' as html;
import 'package:flutter/services.dart';

class ClipboardService {
  /// Copies text to browser clipboard synchronously via execCommand (works on HTTP & HTTPS),
  /// falling back to Flutter Clipboard & Web Navigator APIs.
  static Future<bool> copy(String text) async {
    if (text.isEmpty) return false;

    // 1. Try synchronous execCommand FIRST before any async gap!
    if (copySync(text)) {
      return true;
    }

    // 2. Fallback to Flutter Clipboard API
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {}

    // 3. Fallback to Web Navigator Clipboard API
    try {
      if (html.window.navigator.clipboard != null) {
        await html.window.navigator.clipboard!.writeText(text);
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Synchronous copy using document.execCommand (must be called inside user gesture)
  static bool copySync(String text) {
    if (text.isEmpty) return false;
    try {
      final textarea = html.TextAreaElement()
        ..value = text
        ..style.position = 'fixed'
        ..style.left = '-9999px'
        ..style.top = '-9999px'
        ..style.opacity = '0';
      html.document.body?.append(textarea);
      textarea.focus();
      textarea.select();
      final success = html.document.execCommand('copy');
      textarea.remove();
      if (success == true) return true;
    } catch (_) {}
    return false;
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

