import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/ids.dart';
import '../db/app_database.dart';
import 'archive_repo.dart';
import 'audit_repo.dart';
import 'settings_repo.dart';

/// كتالوج العمليات القابلة للأرشفة التلقائية — يُعرض في إعدادات «الأرشفة
/// التلقائية»، ومفتاحه يُخزَّن مع كل ملفٍ مؤرشف تلقائيًّا في `opType`.
///
/// **مفصّلة بكل عمليةٍ مخزنية**: تفعيل «الصرف» لا يعني «الاستلام» — كل
/// عمليةٍ مفتاحٌ وإعدادٌ مستقلان.
const List<(String, String, String)> kArchiveOps = [
  ('receipt', 'سندات الاستلام (التوريد)', 'download'),
  ('issue', 'سندات الصرف', 'upload'),
  ('transfer', 'التحويلات المخزنية', 'repeat'),
  ('return', 'المرتجعات', 'undo'),
  ('rationOrder', 'طلبيات الإعاشة', 'clipboard'),
  ('stocktake', 'مستندات الجرد', 'clipboard'),
  ('cable', 'نماذج البرقيات', 'mail'),
  ('contract', 'عقود الشراء', 'clipboard'),
  ('custodySheet', 'مسيرات العهدة', 'dollar'),
  ('moneyReceipt', 'سندات استلام المبالغ', 'dollar'),
  ('report', 'التقارير والمطبوعات', 'file'),
];

/// اسم العملية للعرض — يظهر في الوسوم وشارة نوع العملية.
String archiveOpLabel(String op) {
  for (final o in kArchiveOps) {
    if (o.$1 == op) return o.$2;
  }
  return op;
}

/// مفتاح الإعدادات في جدول `app_settings`.
const String kArchiveAutoKey = 'archive.auto';

/// إعدادات الأرشفة التلقائية — مخزَّنة JSON عبر [SettingsRepo].
///
/// مفتاحٌ رئيسٌ واحد ([enabled]) ومفتاحٌ لكل عمليةٍ من [kArchiveOps]:
/// الغياب يعني غير مفعّلة، فالجديد لا يُؤرشف إلا بأمرٍ صريح.
class ArchiveAutoSettings {
  const ArchiveAutoSettings({this.enabled = false, this.ops = const {}});

  final bool enabled;

  /// مفتاح العملية ⇒ مفعّلة؟
  final Map<String, bool> ops;

  /// هل تُؤرشف العملية الآن؟ التفعيل المزدوج (رئيس + عملية) شرطٌ مقصود:
  /// إيقافٌ واحدٌ يهدئ الأرشفة كلها دون مسح تفعيلات العمليات واحدةً واحدة.
  bool opOn(String op) => enabled && (ops[op] ?? false);

  static ArchiveAutoSettings fromMap(Map<String, dynamic> m) => ArchiveAutoSettings(
        enabled: m['enabled'] == true,
        ops: {
          for (final e in (m['ops'] as Map? ?? {}).entries) '${e.key}': e.value == true,
        },
      );

  Map<String, dynamic> toMap() => {'enabled': enabled, 'ops': ops};
}

/// خدمة الأرشفة التلقائية: تُستدعى من مسارات الطباعة المركزية
/// (`VoucherPrint` للسندات و`DocumentPdf` للتقارير والمطبوعات) بعد إتمام
/// الطباعة بنجاح، فتُؤرشف **نسخة PDF مطابقة لما طُبع فعلًا** — بنفس البايتات
/// لا بإعادة توليدها.
///
/// فشلُ الأرشفة لا يمنع طباعةً تمّت: كل استدعاءٍ محميٌّ عند المستدعي،
/// والأرشفة تُسجَّل في التدقيق فحسب.
class ArchiveAuto {
  ArchiveAuto(this.db);

  final AppDatabase db;

  SettingsRepo get _settings => SettingsRepo(db);

  Future<ArchiveAutoSettings> load() async =>
      ArchiveAutoSettings.fromMap(await _settings.read(kArchiveAutoKey));

  Future<void> save(ArchiveAutoSettings s) => _settings.write(kArchiveAutoKey, s.toMap());

  /// تُستدعى بعد كل طباعةٍ ناجحة. تُعيد true إن أُرشف.
  ///
  /// **إعادة طباعة السند نفسه لا تُكرره في الأرشيف**: تُبحث نسخةٌ تلقائية
  /// سابقة لنفس العملية ونفس الرقم فتُحدَّث بايتاتها وبصمتها — السند في
  /// الأرشيف دائمًا آخر نسخةٍ طُبعت.
  Future<bool> onDocumentPrinted({
    required String op,
    required String title,
    String docRef = '',
    String warehouse = '',
    String docDate = '',
    required List<int> pdfBytes,
    String fileName = '',
  }) async {
    final s = await load();
    if (!s.opOn(op) || pdfBytes.isEmpty) return false;

    final sha = sha256.convert(pdfBytes).toString();

    if (docRef.isNotEmpty) {
      final old = await (db.select(db.archiveFiles)..where((t) =>
          t.opType.equals(op) & t.docRef.equals(docRef) & t.source.equals('auto'))).get();
      if (old.isNotEmpty) {
        final f = old.first;
        await File(f.storedPath).writeAsBytes(pdfBytes, flush: true);
        await (db.update(db.archiveFiles)..where((t) => t.id.equals(f.id))).write(
          ArchiveFilesCompanion(
            sizeBytes: Value(pdfBytes.length),
            sha256: Value(sha),
            updatedAt: Value(DateTime.now()),
          ),
        );
        return true;
      }
    }

    final repo = ArchiveRepo(db);
    final dir = await repo.storageDir();
    final id = Ids.next('ar');
    final dst = File(p.join(dir.path, '$id.pdf'));
    await dst.writeAsBytes(pdfBytes, flush: true);

    await db.into(db.archiveFiles).insert(ArchiveFilesCompanion.insert(
          id: id,
          title: title,
          fileName: fileName.isEmpty ? '${title.replaceAll(RegExp(r'\s+'), '-')}.pdf' : fileName,
          storedPath: dst.path,
          sizeBytes: pdfBytes.length,
          mime: const Value('application/pdf'),
          category: const Value('أرشفة تلقائية'),
          tags: Value(encodeTags(['تلقائي', archiveOpLabel(op)])),
          docRef: Value(docRef),
          warehouse: Value(warehouse),
          docDate: Value(docDate),
          sha256: Value(sha),
          source: const Value('auto'),
          opType: Value(op),
        ));

    await AuditRepo(db).log(
      action: 'archive.auto',
      entityType: 'archive',
      summary: 'أرشفة تلقائية: $title',
      details: {'op': op, 'docRef': docRef, 'warehouse': warehouse, 'sizeBytes': pdfBytes.length},
      risk: AuditRepo.riskNormal,
    );
    return true;
  }
}
