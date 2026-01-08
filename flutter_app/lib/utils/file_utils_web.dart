import 'dart:html' as html;
import 'dart:convert';

class FileUtilsImpl {
  static Future<void> saveFile(
      dynamic context, String filename, String content) async {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
