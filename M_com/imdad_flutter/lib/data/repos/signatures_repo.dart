import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/security/esign.dart';
import '../db/app_database.dart';
import '../../domain/esign_policy.dart';
import 'audit_repo.dart';
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
  ///
  /// `digest` بصمة **محتوى** السند لحظة توقيعه: بها يُعرف أن السند عُدِّل بعد
  /// التوقيع، فلا يُطبع رمزٌ قديم على محتوى جديد (كان `signOnce` يعيد الرمز
  /// الأول أبدًا فيسقط التحقق من سندٍ عُدِّل تعديلًا مشروعًا).
  static Future<void> install(AppDatabase db) async {
    await db.customStatement('''
        CREATE TABLE IF NOT EXISTS $table (
          doc_ref TEXT NOT NULL PRIMARY KEY,
          token TEXT NOT NULL,
          signer TEXT NOT NULL,
          key_id TEXT NOT NULL,
          signed_at INTEGER NOT NULL,
          digest TEXT NOT NULL DEFAULT ''
        )
      ''');
    final cols = {
      for (final r in await db.customSelect('PRAGMA table_info("$table")').get()) r.data['name'] as String,
    };
    if (!cols.contains('digest')) {
      await db.customStatement("ALTER TABLE $table ADD COLUMN digest TEXT NOT NULL DEFAULT ''");
    }
  }

  Future<String?> tokenFor(String docRef) async {
    final rows = await db
        .customSelect('SELECT token FROM $table WHERE doc_ref = ?', variables: [
      Variable<String>(docRef),
    ]).get();
    return rows.isEmpty ? null : rows.first.read<String>('token');
  }

  /// بصمة محتوى السند (بلا وقت) — ثابتةٌ ما لم يتغيّر المحتوى.
  static String contentDigest(String docRef, Map<String, dynamic> payload) =>
      base64Url.encode(ESign.digestOf(docRef: docRef, ts: 0, payload: payload));

  /// الرمز المحفوظ إن كان **لهذا المحتوى نفسه**، وإلا `null`.
  Future<String?> _matching(String docRef, String digest) async {
    final rows = await db.customSelect(
      'SELECT token, digest FROM $table WHERE doc_ref = ?',
      variables: [Variable<String>(docRef)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.read<String>('digest') == digest ? rows.first.read<String>('token') : null;
  }

  Future<String?> _signAndStore(String docRef, Map<String, dynamic> payload, String owner, String digest) async {
    final esign = ESign(db);
    final token = await esign.sign(docRef: docRef, payload: payload, owner: owner);
    if (token == null) return null;
    await db.customStatement(
      'INSERT INTO $table (doc_ref, token, signer, key_id, signed_at, digest) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (doc_ref) DO UPDATE SET token = excluded.token, signer = excluded.signer, '
      'key_id = excluded.key_id, signed_at = excluded.signed_at, digest = excluded.digest',
      [docRef, token, owner, await esign.keyId(owner), DateTime.now().millisecondsSinceEpoch, digest],
    );
    return token;
  }

  /// الرمز الذي يُطبع على **سندٍ محفوظ** ([status] حالته في القاعدة).
  ///
  /// • حالةٌ غير نهائية (مسودة، أمر معلّق، ملغى، مرفوض) ⇒ لا رمز أبدًا.
  /// • توقيعٌ سابق لهذا المحتوى نفسه ⇒ يُعاد كما هو (النسخ الورقية متطابقة).
  /// • غير ذلك: الوضع التلقائي يوقّع الآن (أو يعيد التوقيع بعد تعديل)؛ واليدوي
  ///   والمعطَّل لا يوقّعان — التوقيع اليدوي بإجراءٍ صريح ([signManually]).
  ///
  /// `null` أيضًا إن لم يكن للموقِّع مفتاحٌ على هذا الجهاز.
  Future<String?> tokenForPrint({
    required String docRef,
    required String status,
    required Map<String, dynamic> payload,
    required ESignMode mode,
    String owner = 'commander',
  }) async {
    if (!ESignPolicy.signable(status) || mode == ESignMode.off) return null;
    final digest = contentDigest(docRef, payload);
    final existing = await _matching(docRef, digest);
    if (existing != null) return existing;
    if (mode != ESignMode.auto) return null;
    return _signAndStore(docRef, payload, owner, digest);
  }

  /// توقيعٌ يدويٌّ صريح لسندٍ محفوظ — يُستدعى ممن يملك صلاحية التوقيع
  /// (`ESignPolicy.canSign`)، ويُدقَّق بخطورة عالية. يرمي [StateError] إن لم يصلح
  /// السند للتوقيع أو لم يكن مفتاح الموقِّع على هذا الجهاز.
  Future<String> signManually({
    required String docRef,
    required String status,
    required Map<String, dynamic> payload,
    required String actorEmail,
    String owner = 'commander',
  }) async {
    if (!ESignPolicy.signable(status)) {
      throw StateError('✖ لا يُوقَّع سندٌ بحالته الحالية (مسودة أو معلّق أو ملغى أو مرفوض)');
    }
    final token = await _signAndStore(docRef, payload, owner, contentDigest(docRef, payload));
    if (token == null) throw StateError('✖ لا يوجد مفتاح توقيع على هذا الجهاز — جهّزه من الإعدادات');
    await AuditRepo(db).log(
      action: 'esign.signed',
      entityType: 'توقيع إلكتروني',
      summary: 'توقيع السند $docRef إلكترونيًّا باسم القائد',
      details: {'refNo': docRef, 'mode': 'manual'},
      risk: AuditRepo.riskHigh,
      actorEmail: actorEmail,
    );
    return token;
  }

  /// يوقّع المستند إن لم يكن موقَّعًا، ويعيد الرمز. `null` إن لم يكن للموقِّع
  /// مفتاح على هذا الجهاز.
  ///
  /// **قديم** — يوقّع بلا نظرٍ في حالة السند ولا في سياسة التوقيع. الطباعة تمرّ
  /// بـ[tokenForPrint]؛ يبقى هذا لمن يحتاج توقيعًا صريحًا على حمولةٍ بعينها.
  Future<String?> signOnce({
    required String docRef,
    required Map<String, dynamic> payload,
    String owner = 'commander',
  }) async {
    final digest = contentDigest(docRef, payload);
    final existing = await _matching(docRef, digest);
    if (existing != null) return existing;
    return _signAndStore(docRef, payload, owner, digest);
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

  /// حالة السند المحفوظ بمرجعه (أول ما يُعثر عليه)، أو `null`.
  Future<String?> statusOfStored(String refNo) async {
    final docs = DocumentsRepo(db);
    for (final kind in DocKind.values) {
      final rows = await docs.rawLines(kind, refNo);
      if (rows.isNotEmpty) return rows.first.status as String;
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
