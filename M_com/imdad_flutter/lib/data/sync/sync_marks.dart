import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// علامة سجل واحد: متى عُدِّل آخر مرة، ومتى حُذف إن حُذف.
class SyncMark {
  const SyncMark({
    required this.entity,
    required this.rowId,
    required this.updatedAt,
    this.deletedAt,
  });

  final String entity;
  final String rowId;

  /// بالمللي ثانية منذ الحقبة — ساعة الجهاز الذي كتب السجل.
  final int updatedAt;
  final int? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// اللحظة التي يُقارن بها في الدمج: الأحدث بين التعديل والحذف.
  int get stamp => deletedAt == null ? updatedAt : (deletedAt! > updatedAt ? deletedAt! : updatedAt);

  String get key => '$entity/$rowId';

  Map<String, dynamic> toMap() => {
        'entity': entity,
        'rowId': rowId,
        'updatedAt': updatedAt,
        if (deletedAt != null) 'deletedAt': deletedAt,
      };

  static SyncMark? fromMap(Map<String, dynamic> m) {
    final entity = (m['entity'] ?? '').toString();
    final rowId = (m['rowId'] ?? '').toString();
    if (entity.isEmpty || rowId.isEmpty) return null;
    final updated = (m['updatedAt'] as num?)?.toInt();
    if (updated == null) return null;
    return SyncMark(
      entity: entity,
      rowId: rowId,
      updatedAt: updated,
      deletedAt: (m['deletedAt'] as num?)?.toInt(),
    );
  }
}

/// سجل تغييرات لكل سجل قابل للمزامنة — يحلّ مشكلتين في الدمج:
///
/// • **الحذف لم يكن ينتقل**: صنف حُذف في جهاز يعود من الجهاز الآخر، لأن الدمج
///   يكتب ما عنده ولا يعرف أن الغياب مقصود. الآن يبقى «شاهد حذف» ينتقل معه.
/// • **آخر من يزامن كان يفوز**: الكتابة بالمعرّف تعني أن جهازًا قديم البيانات
///   يدهس تعديلًا أحدث. الآن يُقارن ختم التعديل ويفوز الأحدث.
///
/// السياسة عند التعارض بين حذف وتعديل: **الأحدث يفوز**. تعديل بعد الحذف يُعيد
/// السجل، وحذف بعد التعديل يُزيله — وهو السلوك الذي يتوقعه المستخدم.
///
/// العلامات تُملأ بمحفِّزات SQLite لا بنداءات في المستودعات: المحفِّز يغطي كل
/// مسارات الكتابة (بما فيها الاستيراد والحذف المباشر) فلا ينسى أحدها.
class SyncMarks {
  const SyncMarks(this.db);

  final AppDatabase db;

  static const String table = 'sync_marks';

  /// الجداول المشمولة بالمزامنة ومفتاح كل منها.
  static const Map<String, String> entities = {
    'users': 'id',
    'categories': 'id',
    'items': 'id',
    'warehouses': 'id',
    'suppliers': 'id',
    'beneficiary_units': 'id',
    'facilities': 'id',
    'receipts': 'id',
    'issues': 'id',
    'transfers': 'id',
    'returns': 'id',
    'opening_balances': 'id',
    'adjustments': 'id',
    'strengths': 'id',
    'kitchen_logs': 'id',
    'entitlements': 'item_id',
    'app_settings': 'key',
    // الجرد وسطوره والمراجعة الحساسة وسجل التدقيق: كانت خارج المزامنة، فكانت
    // جلسة جرد تتم في فرع ولا تبلغ الإدارة أبدًا — لا بمزامنة كاملة ولا جزئية.
    'stocktakes': 'id',
    'stocktake_lines': 'id',
    'sensitive_reviews': 'id',
    'audit_logs': 'id',
    // v8: الأصول وعهدها وطلبيات الإعاشة — تُسجَّل هنا يوم تُنشأ لا بعد أن
    // يكتشف أحدهم أن بياناتها لا تغادر جهازها.
    'assets': 'id',
    'asset_assignments': 'id',
    'supply_authorities': 'id',
    'warehouse_stock_limits': 'id',
    'ration_orders': 'id',
    'ration_order_lines': 'id',
    'meal_plans': 'id',
    'meal_plan_entries': 'id',
    'camp_ledgers': 'id',
    'camp_stock_limits': 'id',
    'monthly_settlements': 'id',
  };

  /// المللي ثانية الحالية بصيغة SQLite (لا يوجد `unixepoch('subsec')` في كل نسخة).
  static const String _nowMillis =
      "CAST((julianday('now') - 2440587.5) * 86400000.0 AS INTEGER)";

  /// ينشئ الجدول والمحفِّزات إن لم تكن موجودة — يُستدعى عند كل فتح للقاعدة.
  static Future<void> install(AppDatabase db) async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS $table (
        entity TEXT NOT NULL,
        row_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        PRIMARY KEY (entity, row_id)
      )
    ''');

    for (final entry in entities.entries) {
      final t = entry.key;
      final pk = entry.value;
      // الإدراج والتعديل: ختم جديد، وإلغاء أي شاهد حذف سابق على المعرّف نفسه.
      for (final event in ['INSERT', 'UPDATE']) {
        await db.customStatement('''
          CREATE TRIGGER IF NOT EXISTS tg_${t}_${event.toLowerCase()}_mark
          AFTER $event ON $t BEGIN
            INSERT INTO $table (entity, row_id, updated_at, deleted_at)
            VALUES ('$t', NEW.$pk, $_nowMillis, NULL)
            ON CONFLICT (entity, row_id) DO UPDATE
              SET updated_at = excluded.updated_at, deleted_at = NULL;
          END
        ''');
      }
      // الحذف: يبقى شاهد ينتقل إلى بقية الأجهزة.
      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS tg_${t}_delete_mark
        AFTER DELETE ON $t BEGIN
          INSERT INTO $table (entity, row_id, updated_at, deleted_at)
          VALUES ('$t', OLD.$pk, $_nowMillis, $_nowMillis)
          ON CONFLICT (entity, row_id) DO UPDATE
            SET deleted_at = excluded.deleted_at, updated_at = excluded.updated_at;
        END
      ''');

      // سطرٌ سبق المحفِّز لا علامة له، والمحفِّز لا يعمل بأثر رجعي. فلولا هذا
      // الملء لبقيت بيانات جدولٍ أُضيف إلى المزامنة اليوم غائبةً عن كل جهاز
      // تجاوز مزامنته الأولى: التصدير التفاضلي يسأل العلامات، والعلامات خالية.
      //
      // يجري مرة واحدة لكل سطر (`OR IGNORE` يتخطى ما له علامة)، وثمنه دورةٌ
      // واحدة أثقل بعد التحديث ثم يعود كل شيء تفاضليًا.
      await db.customStatement('''
        INSERT OR IGNORE INTO $table (entity, row_id, updated_at, deleted_at)
        SELECT '$t', $pk, $_nowMillis, NULL FROM $t
      ''');
    }
  }

  /// كل العلامات مفهرسة بـ `entity/rowId`.
  Future<Map<String, SyncMark>> snapshot() async {
    final rows = await db.customSelect('SELECT * FROM $table').get();
    return {
      for (final r in rows)
        '${r.read<String>('entity')}/${r.read<String>('row_id')}': SyncMark(
          entity: r.read<String>('entity'),
          rowId: r.read<String>('row_id'),
          updatedAt: r.read<int>('updated_at'),
          deletedAt: r.readNullable<int>('deleted_at'),
        ),
    };
  }

  /// العلامات التي تغيّرت بعد [stamp] — أساس المزامنة التفاضلية.
  ///
  /// المقارنة على `stamp` لا على `updated_at` وحده: شاهد الحذف يحمل ختمه في
  /// `deleted_at`، فلو قِيس بالتعديل وحده لما انتقل حذفٌ وقع بعد آخر مزامنة.
  Future<List<SyncMark>> changedSince(int stamp) async {
    final rows = await db.customSelect(
      'SELECT * FROM $table WHERE MAX(updated_at, COALESCE(deleted_at, 0)) > ?',
      variables: [Variable<int>(stamp)],
    ).get();
    return [
      for (final r in rows)
        SyncMark(
          entity: r.read<String>('entity'),
          rowId: r.read<String>('row_id'),
          updatedAt: r.read<int>('updated_at'),
          deletedAt: r.readNullable<int>('deleted_at'),
        ),
    ];
  }

  /// أحدث ختم في هذا الجهاز — علامة الماء التي يبني عليها الطرف الآخر.
  Future<int> maxStamp() async {
    final row = await db
        .customSelect('SELECT COALESCE(MAX(MAX(updated_at, COALESCE(deleted_at, 0))), 0) AS m '
            'FROM $table')
        .getSingle();
    return row.read<int>('m');
  }

  /// يكتب علامة صراحةً — يُستعمل بعد الدمج لتثبيت الختم الفائز بدل الختم
  /// الذي كتبه المحفِّز لحظة الاستيراد.
  Future<void> put(SyncMark mark) => db.customStatement(
        'INSERT INTO $table (entity, row_id, updated_at, deleted_at) VALUES (?, ?, ?, ?) '
        'ON CONFLICT (entity, row_id) DO UPDATE '
        'SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at',
        [mark.entity, mark.rowId, mark.updatedAt, mark.deletedAt],
      );

  /// يحذف السجل الأصلي نهائيًا مع إبقاء شاهد الحذف (يكتبه المحفِّز).
  Future<void> applyTombstone(SyncMark mark) async {
    final pk = entities[mark.entity];
    if (pk == null) return;
    await db.customStatement(
      'DELETE FROM ${mark.entity} WHERE $pk = ?',
      [mark.rowId],
    );
  }

  /// شواهد الحذف القديمة تُنظَّف بعد مدة طويلة حتى لا ينمو الجدول بلا حد.
  /// المدة أطول بكثير من أي فجوة مزامنة واقعية بين جهازين في الميدان.
  static const Duration tombstoneTtl = Duration(days: 180);

  Future<void> pruneTombstones({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(tombstoneTtl).millisecondsSinceEpoch;
    await db.customStatement(
      'DELETE FROM $table WHERE deleted_at IS NOT NULL AND deleted_at < ?',
      [cutoff],
    );
  }
}
