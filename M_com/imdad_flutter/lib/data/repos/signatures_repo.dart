import 'package:drift/drift.dart';

import '../../core/security/esign.dart';
import '../db/app_database.dart';
import 'documents_repo.dart';

/// تواقيع المستندات المحفوظة.
///
/// المستند يُوقَّع **مرة واحدة** ويُحفظ رمزه: إعادة الطباعة تُخرج الرمز نفسه،
/// فتبقى كل النسخ الورقية من السند الواحد متطابقة ويمكن مقابلتها ببعضها.
class SignaturesRepo {
  const SignaturesRepo(this.db);

  final AppDatabase db;

  static const String table = 'doc_signatures';

  /// يُستدعى عند فتح القاعدة — الجدول خارج مخطط Drift لأنه بنية مساندة.
  static Future<void> install(AppDatabase db) => db.customStatement('''
        CREATE TABLE IF NOT EXISTS $table (
          doc_ref TEXT NOT NULL PRIMARY KEY,
          token TEXT NOT NULL,
          signer TEXT NOT NULL,
          key_id TEXT NOT NULL,
          signed_at INTEGER NOT NULL
        )
      ''');

  Future<String?> tokenFor(String docRef) async {
    final rows = await db
        .customSelect('SELECT token FROM $table WHERE doc_ref = ?', variables: [
      Variable<String>(docRef),
    ]).get();
    return rows.isEmpty ? null : rows.first.read<String>('token');
  }

  /// يوقّع المستند إن لم يكن موقَّعًا، ويعيد الرمز. `null` إن لم يكن للموقِّع
  /// مفتاح على هذا الجهاز — عندها يُطبع المستند بلا رمز تحقق كما كان.
  Future<String?> signOnce({
    required String docRef,
    required Map<String, dynamic> payload,
    String owner = 'commander',
  }) async {
    final existing = await tokenFor(docRef);
    if (existing != null) return existing;

    final esign = ESign(db);
    final token = await esign.sign(docRef: docRef, payload: payload, owner: owner);
    if (token == null) return null;

    await db.customStatement(
      'INSERT INTO $table (doc_ref, token, signer, key_id, signed_at) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT (doc_ref) DO NOTHING',
      [docRef, token, owner, await esign.keyId(owner), DateTime.now().millisecondsSinceEpoch],
    );
    return token;
  }

  /// محتوى المستند الذي يُوقَّع عليه ويُقارن عند التحقق.
  ///
  /// يجب أن يُبنى بالطريقة نفسها عند التوقيع وعند التحقق، ولذلك هو هنا في
  /// موضع واحد: أي اختلاف في الترتيب أو التقريب يُسقط التحقق بلا سبب حقيقي.
  static Map<String, dynamic> payloadOf({
    required String refNo,
    required String date,
    required String warehouse,
    required String party,
    required List<({String item, String unit, double qty})> lines,
  }) =>
      {
        'ref': refNo,
        'date': date,
        'warehouse': warehouse,
        'party': party,
        'lines': [
          for (final l in lines)
            {'item': l.item, 'unit': l.unit, 'qty': (l.qty * 1000).round() / 1000},
        ],
      };

  /// يبني المحتوى من السند المحفوظ في هذا الجهاز — يُستعمل عند التحقق من رمز
  /// ممسوح من ورقة، لمقابلة ما على الورق بما في النظام.
  Future<Map<String, dynamic>?> payloadOfStored(String refNo) async {
    final docs = DocumentsRepo(db);
    for (final kind in DocKind.values) {
      final rows = await docs.rawLines(kind, refNo);
      if (rows.isEmpty) continue;
      final head = rows.first;
      return payloadOf(
        refNo: refNo,
        date: head.date as String,
        warehouse: head.warehouse as String,
        party: _partyOf(kind, head),
        lines: [
          for (final r in rows)
            (
              item: r.itemName as String,
              unit: r.unitName as String,
              qty: (r.qty as num).toDouble(),
            ),
        ],
      );
    }
    return null;
  }

  static String _partyOf(DocKind kind, dynamic head) => switch (kind) {
        DocKind.receipt => head.supplier as String,
        DocKind.issue => head.recipientDisplay as String,
        DocKind.transfer => head.destWarehouse as String,
        DocKind.returnDoc => head.party as String,
      };
}
