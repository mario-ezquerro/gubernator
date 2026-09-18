import 'dart:convert';
import 'dart:html' as html;

/// Utility service to download files to the user's local workstation/computer from the browser.
class DownloadService {
  /// Triggers a browser download of a Compose YAML file.
  static void downloadYaml(String content, {String? filename}) {
    var fn = (filename ?? 'docker-compose.yml').trim();
    if (fn.isEmpty) fn = 'docker-compose.yml';
    fn = fn.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '-');
    if (!fn.endsWith('.yml') && !fn.endsWith('.yaml')) {
      fn = '$fn.yml';
    }

    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes], 'application/x-yaml');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fn)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
