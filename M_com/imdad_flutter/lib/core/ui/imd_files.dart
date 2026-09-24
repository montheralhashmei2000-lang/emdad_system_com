import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'imd_widgets.dart';

/// حفظ الملفات واختيارها — مقابل التنزيل (`a.download`) و`<input type=file>` في الويب.
class ImdFiles {
  /// يحفظ ملفًا باسم مقترح؛ على ويندوز تظهر نافذة «حفظ باسم»، وعلى أندرويد يُحفظ عبر منتقي النظام.
  static Future<String?> saveBytes(BuildContext context, String fileName, List<int> bytes) async {
    try {
      final data = Uint8List.fromList(bytes);
      final ext = fileName.contains('.') ? fileName.split('.').last : null;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ الملف',
        fileName: fileName,
        bytes: data,
        type: ext == null ? FileType.any : FileType.custom,
        allowedExtensions: ext == null ? null : [ext],
      );
      if (path == null) return null;
      // على سطح المكتب يُرجع المسار فقط دون كتابة الملف.
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await File(path).writeAsBytes(data, flush: true);
      }
      return path;
    } catch (e) {
      if (context.mounted) showImdToast(context, '✖ تعذر حفظ الملف: $e');
      return null;
    }
  }

  /// اختيار ملف واحد وإرجاع محتواه.
  static Future<(String name, Uint8List bytes)?> pick({List<String> extensions = const ['xlsx', 'xls', 'csv']}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    final f = res?.files.singleOrNull;
    if (f == null) return null;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return null;
    return (f.name, bytes);
  }

  /// تاريخ اليوم بصيغة الويب `new Date().toISOString().slice(0,10)`.
  static String today() => DateTime.now().toIso8601String().substring(0, 10);
}
