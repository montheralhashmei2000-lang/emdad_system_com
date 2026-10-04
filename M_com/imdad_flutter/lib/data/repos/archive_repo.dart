import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';

/// ترميز وسوم الأرشيف — قائمة JSON نصية تحتوي عناصرها فحسب.
List<String> decodeTags(String raw) {
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const [];
    return [for (final e in parsed) '$e'.trim()].where((t) => t.isNotEmpty).toList();
  } catch (_) {
    // وسمٌ تالفٌ لا يُسقِط الشاشة: تعني القائمة الفارغة «بلا وسوم».
    return const [];
  }
}

String encodeTags(List<String> tags) => jsonEncode(
      [for (final t in tags) t.trim()].where((t) => t.isNotEmpty).toList(),
    );

/// هل الامتداد صورةً تُعاين داخل التطبيق؟
bool archiveIsImage(String fileName) {
  const exts = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'};
  return exts.contains(p.extension(fileName).replaceFirst('.', '').toLowerCase());
}

/// هل الملف PDF — يُعاين ويُطبع من التطبيق مباشرة.
bool archiveIsPdf(String fileName) =>
    p.extension(fileName).replaceFirst('.', '').toLowerCase() == 'pdf';

/// تخمين النوع MIME من الامتداد — للمعاينة لا للاعتماد الأمني.
String archiveMimeOf(String fileName) {
  final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'bmp' => 'image/bmp',
    'xlsx' || 'xls' => 'application/vnd.ms-excel',
    'docx' || 'doc' => 'application/msword',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

/// مستودع الأرشيف الإلكتروني.
///
/// **البيانات الوصفية في القاعدة، والملف على القرص**: كل ملفٍ يُؤرشف يُنسخ
/// إلى مجلد `archive/` داخل بيانات التطبيق باسم معرّفه (فلا مساراتٌ عربيةٌ
/// ولا تصادم أسماء)، وتُحسب لحظة نسخه بصمة SHA-256 تُخزَّن معه — فحصُ
/// النزاهة لاحقًا عبارةٌ عن إعادة حسابٍ ومقارنة.
///
/// يخدم مصدرَي الأرشفة كليهما: اليدوي من الشاشة ([archive])، والتلقائي عند
/// الطباعة — وتلك تكتب عبر [ArchiveAuto] التي تشارك هذا المستودع مجلدَه
/// وترميزَه، فالمستودع المصدر الوحيد لقواعد التخزين.
class ArchiveRepo {
  ArchiveRepo(this.db);

  final AppDatabase db;

  /// مجلد الأرشيف على القرص — يُنشأ عند أول استعمال.
  Future<Directory> storageDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'archive'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// كل الملفات المؤرشفة، المثبَّت أولًا ثم الأحدث وثائقيًّا. التصفية النصية
  /// هنا لا في SQL: حجم الأرشيف على جهاز الفرع يُحتمل كاملًا في الذاكرة،
  /// وبحثُ «أي حقل» بلغةٍ عربية أسهلُ في Dart منه في SQLite.
  Future<List<ArchiveFile>> list({
    String query = '',
    String category = '',
    String warehouse = '',
    String docRef = '',
    String from = '',
    String to = '',
    String tag = '',
    String source = '',
    String opType = '',
    bool onlyPinned = false,
  }) async {
    final rows =
        await (db.select(db.archiveFiles)..where((t) => t.space.equals('supply'))).get();

    final q = query.trim().toLowerCase();
    final tagWanted = tag.trim();
    final out = rows.where((r) {
      if (category.isNotEmpty && r.category != category) return false;
      if (warehouse.isNotEmpty && r.warehouse != warehouse) return false;
      if (docRef.isNotEmpty && r.docRef != docRef) return false;
      if (source.isNotEmpty && r.source != source) return false;
      if (opType.isNotEmpty && r.opType != opType) return false;
      if (onlyPinned && !r.pinned) return false;
      if (from.isNotEmpty && r.docDate.compareTo(from) < 0) return false;
      if (to.isNotEmpty && r.docDate.compareTo(to) > 0) return false;
      if (tagWanted.isNotEmpty && !decodeTags(r.tags).contains(tagWanted)) return false;
      if (q.isNotEmpty) {
        final hay = [
          r.title,
          r.fileName,
          r.category,
          r.docRef,
          r.warehouse,
          r.notes,
          r.createdBy,
          decodeTags(r.tags).join(' '),
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    out.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final byDate = b.docDate.compareTo(a.docDate);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  /// التصنيفات الموجودة فعليًّا — تُقترح عند الإدخال وتملأ قائمة التصفية.
  Future<Set<String>> categories() async {
    final rows = await db.select(db.archiveFiles).get();
    return {for (final r in rows) if (r.category.trim().isNotEmpty) r.category.trim()};
  }

  /// الوسوم الموجودة فعليًّا — نفس الغرض.
  Future<Set<String>> tags() async {
    final rows = await db.select(db.archiveFiles).get();
    return {for (final r in rows) ...decodeTags(r.tags)};
  }

  /// أرشفة ملفٍ واحد: نسخٌ ببصمة، ثم تسجيلٌ، ثم تدقيق.
  ///
  /// المصدر يبقى كما هو على غير مسؤوليتنا — الأرشيف نسخةٌ لا نقل.
  Future<ArchiveFile> archive({
    required String sourcePath,
    required String title,
    String category = 'عام',
    List<String> tags = const [],
    String docRef = '',
    String warehouse = '',
    String docDate = '',
    String notes = '',
    String createdBy = '',
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw StateError('الملف المصدر غير موجود: $sourcePath');
    }
    final bytes = await src.readAsBytes();
    final digest = sha256.convert(bytes).toString();

    final id = Ids.next('ar');
    final dir = await storageDir();
    final dst = File(p.join(dir.path, '$id${p.extension(sourcePath)}'));
    await dst.writeAsBytes(bytes, flush: true);

    await db.into(db.archiveFiles).insert(ArchiveFilesCompanion.insert(
          id: id,
          title: title.trim().isEmpty ? p.basenameWithoutExtension(sourcePath) : title.trim(),
          fileName: p.basename(sourcePath),
          storedPath: dst.path,
          sizeBytes: bytes.lengthInBytes,
          mime: Value(archiveMimeOf(sourcePath)),
          category: Value(category.trim().isEmpty ? 'عام' : category.trim()),
          tags: Value(encodeTags(tags)),
          docRef: Value(docRef.trim()),
          warehouse: Value(warehouse.trim()),
          docDate: Value(docDate.trim()),
          sha256: Value(digest),
          notes: Value(notes.trim()),
          createdBy: Value(createdBy),
        ));

    await AuditRepo(db).log(
      action: 'archive.create',
      entityType: 'archive',
      summary: 'أرشفة «${title.trim()}» (${p.basename(sourcePath)})',
      details: {'id': id, 'sizeBytes': bytes.lengthInBytes, 'sha256': digest},
      risk: AuditRepo.riskNormal,
      actorEmail: createdBy,
    );
    return (db.select(db.archiveFiles)..where((t) => t.id.equals(id))).getSingle();
  }

  /// تحديث البيانات الوصفية — المسار والبصمة لا يُمسّان: تعديلُ الوصف لا
  /// يعيد كتابة الوثيقة.
  Future<void> updateMeta(
    String id, {
    required String title,
    required String category,
    required List<String> tags,
    required String docRef,
    required String warehouse,
    required String docDate,
    required String notes,
    String actor = '',
  }) async {
    await (db.update(db.archiveFiles)..where((t) => t.id.equals(id))).write(
      ArchiveFilesCompanion(
        title: Value(title.trim()),
        category: Value(category.trim().isEmpty ? 'عام' : category.trim()),
        tags: Value(encodeTags(tags)),
        docRef: Value(docRef.trim()),
        warehouse: Value(warehouse.trim()),
        docDate: Value(docDate.trim()),
        notes: Value(notes.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await AuditRepo(db).log(
      action: 'archive.edit',
      entityType: 'archive',
      summary: 'تعديل بيانات ملفٍ مؤرشف: ${title.trim()}',
      details: {'id': id},
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// تثبيت/إلغاء تثبيت — إجراءٌ عارضٌ لا يستحق سطر تدقيق.
  Future<void> setPinned(String id, bool v) async {
    await (db.update(db.archiveFiles)..where((t) => t.id.equals(id))).write(
      ArchiveFilesCompanion(pinned: Value(v), updatedAt: Value(DateTime.now())),
    );
  }

  /// حذف نهائي: السطر من القاعدة والملف من القرص — إجراءٌ خطرٌ يُسجَّل
  /// عالي الخطورة.
  Future<void> delete(ArchiveFile f, {String actor = ''}) async {
    await (db.delete(db.archiveFiles)..where((t) => t.id.equals(f.id))).go();
    final file = File(f.storedPath);
    if (await file.exists()) await file.delete();
    await AuditRepo(db).log(
      action: 'archive.delete',
      entityType: 'archive',
      summary: 'حذف ملفٍ مؤرشف: ${f.title} (${f.fileName})',
      details: {'id': f.id, 'docRef': f.docRef, 'sizeBytes': f.sizeBytes},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  /// فحص نزاهة النسخة المخزَّنة: هل بصمتها اليوم تطابق ما حُفظ لحظة الأرشفة؟
  Future<bool> verifyIntegrity(ArchiveFile f) async {
    if (f.sha256.isEmpty) return true; // نسخةٌ أُرشفت قبل بصمةٍ — لا حكم عليها
    final file = File(f.storedPath);
    if (!await file.exists()) return false;
    return sha256.convert(await file.readAsBytes()).toString() == f.sha256;
  }
}
