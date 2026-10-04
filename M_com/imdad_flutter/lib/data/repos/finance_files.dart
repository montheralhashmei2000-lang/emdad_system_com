import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// مرفقٌ ماليّ محفوظ على قرص هذا الجهاز (صورة أو PDF).
class FinAttachment {
  const FinAttachment({required this.name, required this.path, this.size = 0, this.sha256 = ''});

  final String name;
  final String path;
  final int size;
  final String sha256;

  Map<String, Object> toJson() => {'name': name, 'path': path, 'size': size, 'sha256': sha256};

  static List<FinAttachment> decode(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map)
            FinAttachment(
              name: '${e['name'] ?? ''}',
              path: '${e['path'] ?? ''}',
              size: e['size'] is num ? (e['size'] as num).toInt() : 0,
              sha256: '${e['sha256'] ?? ''}',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<FinAttachment> items) => jsonEncode([for (final i in items) i.toJson()]);
}

/// تخزين مرفقات العهد والإخلاءات في مجلد `finance/` داخل بيانات التطبيق.
class FinanceFiles {
  const FinanceFiles._();

  static const Set<String> allowed = {'.pdf', '.png', '.jpg', '.jpeg'};

  static Future<Directory> dir() async {
    final support = await getApplicationSupportDirectory();
    final d = Directory(p.join(support.path, 'finance'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// ينسخ [sourcePath] إلى مجلد المرفقات باسمٍ فريد، ويعيد وصفه.
  static Future<FinAttachment> save(String sourcePath, {required String prefix}) async {
    final ext = p.extension(sourcePath).toLowerCase();
    if (!allowed.contains(ext)) throw StateError('يُقبل PDF أو صورة (PNG/JPG) فقط');
    final src = File(sourcePath);
    if (!await src.exists()) throw StateError('الملف غير موجود: $sourcePath');
    final bytes = await src.readAsBytes();
    final dst = File(p.join((await dir()).path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}$ext'));
    await dst.writeAsBytes(bytes, flush: true);
    return FinAttachment(name: p.basename(sourcePath), path: dst.path, size: bytes.length, sha256: sha256.convert(bytes).toString());
  }

  static Future<void> delete(String path) async {
    if (path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
