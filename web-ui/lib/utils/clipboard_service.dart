import 'dart:html' as html;
import 'package:flutter/services.dart';

class ClipboardService {
  /// Copies text to browser clipboard with web API & Flutter fallback.
  static Future<bool> copy(String text) async {
    if (text.isEmpty) return false;
    bool ok = false;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      ok = true;
    } catch (_) {}

    try {
      if (html.window.navigator.clipboard != null) {
        await html.window.navigator.clipboard!.writeText(text);
        ok = true;
      }
    } catch (_) {}
    return ok;
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
