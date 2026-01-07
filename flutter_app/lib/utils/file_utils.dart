import 'file_utils_stub.dart'
    if (dart.library.io) 'file_utils_io.dart'
    if (dart.library.html) 'file_utils_web.dart';

class FileUtils {
  static Future<void> saveFile(
      dynamic context, String filename, String content) async {
    await FileUtilsImpl.saveFile(context, filename, content);
  }
}
