import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// علامة سجل واحد: متى عُدِّل آخر مرة، ومتى حُذف إن حُذف.
class SyncMark {
  const SyncMark({
    required this.entity,
    required this.rowId,
    required this.updatedAt,
    this.deletedAt,
    this.seq = 0,
  });

  final String entity;
  final String rowId;

  /// بالمللي ثانية منذ الحقبة — ساعة الجهاز الذي كتب السجل. **للحسم وحده**
  /// (أيُّ النسختين أحدث)، لا لمعرفة ما تغيّر منذ آخر مزامنة.
  final int updatedAt;
  final int? deletedAt;

  /// ترتيب كتابة العلامة **على هذا الجهاز** (عدّادٌ محليٌّ متزايد، انظر
  /// [SyncMarks.seqTable]). لا يغادر الجهاز: لا يدخل [toMap] ولا يُقرأ من
  /// [fromMap]، لأن عدّاد جهازٍ لا معنى له عند غيره.
  final int seq;

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
///
/// **قياسان لا قياس واحد** (إصلاح C-1 في تدقيق 2026-10-10):
/// • `updated_at`/`deleted_at` — ساعة **الكاتب الأصلي**، تسافر مع السجل
///   وتحسم «أيُّ النسختين أحدث».
/// • `seq` — عدّادٌ **محليّ** يتقدّم مع كل كتابةٍ للعلامة على هذا الجهاز،
///   بما فيها ما وصل بالمزامنة. عليه وحده تُبنى المزامنة التفاضلية.
///
/// كانت التفاضلية تُبنى على أكبر ختمٍ في الجدول، وهو خليطٌ من ساعات الأجهزة
/// كلها (الدمج يثبّت ختم المرسِل). فسجلٌّ عبر جهازًا وسيطًا بختمه القديم كان
/// يقع تحت علامة ماءٍ تجاوزته فلا يُطلب أبدًا، وساعةٌ متقدّمة دقائق كانت ترفع
/// العلامة فوق تعديلات الجهاز الآخر فلا تُرسل أبدًا — بلا خطأ ولا أثر.
class SyncMarks {
  const SyncMarks(this.db);

  final AppDatabase db;

  static const String table = 'sync_marks';

  /// عدّاد هذا الجهاز: صفٌّ واحد (`k = 1`) لا ينقص أبدًا — لا بتقليم الشواهد
  /// ولا بحذف العلامات. لو أُخذ `MAX(seq)` بدله لنزل بحذف أعلى علامة فتكرّر رقمٌ
  /// سبق أن حفظه قرينٌ علامةَ ماء، فسقط ما يحمله.
  static const String seqTable = 'sync_seq';

  /// وسمٌ في نصّ المحفِّز الحالي: محفِّزٌ لا يحمله من إصدارٍ أقدم فيُستبدل.
  /// (`CREATE TRIGGER IF NOT EXISTS` لا يحدّث محفِّزًا قائمًا أبدًا.)
  static const String _triggerVersion = 'imdad-mark-v2';

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
    'fuel_warehouses': 'id',
    'fuel_units': 'id',
    'fuel_settings_rows': 'id',
    'fuel_allocations': 'id',
    'fuel_issues': 'id',
    'fuel_supplies': 'id',
    'fuel_openings': 'id',
    'fuel_transfers': 'id',
    'fuel_stocktakes': 'id',
    'fuel_stocktake_lines': 'id',
    'ration_orders': 'id',
    'ration_order_lines': 'id',
    'meal_plans': 'id',
    'meal_plan_entries': 'id',
    'camp_ledgers': 'id',
    'camp_stock_limits': 'id',
    'monthly_settlements': 'id',
    // البرقيات والارتباطات (القوة البشرية والمالية والتسليح): بيانات تشغيلية
    // تُدخل في فرع ويحتاجها غيره. أرشيف الملفات خارج المزامنة عمدًا لأن
    // ملفاته على قرص هذا الجهاز؛ ودليل المسميات مفتاحه مركّب فيُعاد بناؤه محليًّا.
    'cables': 'id',
    'link_persons': 'id',
    'link_status_logs': 'id',
    'link_fin_custodies': 'id',
    'link_clearances': 'id',
    'link_purchase_contracts': 'id',
    'link_armaments': 'id',
    'link_money_receipts': 'id',
    'link_custody_sheets': 'id',
    'link_custody_sheet_rows': 'id',
    'link_finance_ledger': 'id',
  };

  /// المللي ثانية الحالية بصيغة SQLite (لا يوجد `unixepoch('subsec')` في كل نسخة).
  static const String _nowMillis =
      "CAST((julianday('now') - 2440587.5) * 86400000.0 AS INTEGER)";

  /// قيمة العدّاد الحالية — تُقرأ بعد [_bump] داخل المحفِّز نفسه.
  static const String _currentSeq = '(SELECT v FROM $seqTable WHERE k = 1)';
  static const String _bump = 'UPDATE $seqTable SET v = v + 1 WHERE k = 1;';

  /// ينشئ الجداول والمحفِّزات أو يرقّيها — يُستدعى عند كل فتح للقاعدة.
  static Future<void> install(AppDatabase db) async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS $table (
        entity TEXT NOT NULL,
        row_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        seq INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity, row_id)
      )
    ''');
    // قاعدةٌ من إصدارٍ أقدم: الجدول بلا عمود `seq`. علاماتها القائمة تأخذ صفرًا،
    // وأول دورةٍ مع كل قرين كاملةٌ أصلًا (علامات `seq` عند القرين صفر بعد الترقية).
    final cols = {
      for (final r in await db.customSelect('PRAGMA table_info("$table")').get()) r.data['name'] as String,
    };
    if (!cols.contains('seq')) {
      await db.customStatement('ALTER TABLE $table ADD COLUMN seq INTEGER NOT NULL DEFAULT 0');
    }
    await db.customStatement('CREATE INDEX IF NOT EXISTS ix_${table}_seq ON $table (seq)');
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $seqTable (k INTEGER PRIMARY KEY CHECK (k = 1), v INTEGER NOT NULL)',
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO $seqTable (k, v) SELECT 1, COALESCE(MAX(seq), 0) FROM $table',
    );

    final existing = {
      for (final r in await db
          .customSelect("SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'tg_%_mark'")
          .get())
        r.data['name'] as String: (r.data['sql'] as String?) ?? '',
    };
    Future<void> ensure(String name, String body) async {
      final current = existing[name];
      if (current != null && current.contains(_triggerVersion)) return;
      if (current != null) await db.customStatement('DROP TRIGGER IF EXISTS $name');
      await db.customStatement(body);
    }

    for (final entry in entities.entries) {
      final t = entry.key;
      final pk = entry.value;
      // الإدراج والتعديل: ختم جديد، وإلغاء أي شاهد حذف سابق على المعرّف نفسه،
      // ورقمٌ جديد من عدّاد الجهاز.
      for (final event in ['INSERT', 'UPDATE']) {
        final name = 'tg_${t}_${event.toLowerCase()}_mark';
        await ensure(name, '''
          CREATE TRIGGER $name
          AFTER $event ON $t BEGIN
            -- $_triggerVersion
            $_bump
            INSERT INTO $table (entity, row_id, updated_at, deleted_at, seq)
            VALUES ('$t', NEW.$pk, $_nowMillis, NULL, $_currentSeq)
            ON CONFLICT (entity, row_id) DO UPDATE
              SET updated_at = excluded.updated_at, deleted_at = NULL, seq = excluded.seq;
          END
        ''');
      }
      // الحذف: يبقى شاهد ينتقل إلى بقية الأجهزة.
      final del = 'tg_${t}_delete_mark';
      await ensure(del, '''
        CREATE TRIGGER $del
        AFTER DELETE ON $t BEGIN
          -- $_triggerVersion
          $_bump
          INSERT INTO $table (entity, row_id, updated_at, deleted_at, seq)
          VALUES ('$t', OLD.$pk, $_nowMillis, $_nowMillis, $_currentSeq)
          ON CONFLICT (entity, row_id) DO UPDATE
            SET deleted_at = excluded.deleted_at, updated_at = excluded.updated_at, seq = excluded.seq;
        END
      ''');
    }

    // سطرٌ سبق المحفِّز لا علامة له، والمحفِّز لا يعمل بأثر رجعي. فلولا هذا
    // الملء لبقيت بيانات جدولٍ أُضيف إلى المزامنة اليوم غائبةً عن كل جهاز
    // تجاوز مزامنته الأولى: التصدير التفاضلي يسأل العلامات، والعلامات خالية.
    //
    // يجري مرة واحدة لكل سطر (`OR IGNORE` يتخطى ما له علامة)، وثمنه دورةٌ
    // واحدة أثقل بعد التحديث ثم يعود كل شيء تفاضليًا. ورقمٌ واحد من العدّاد
    // لكل ما يُملأ في هذا الفتح: كلها «كُتبت» في اللحظة نفسها.
    await db.customStatement(_bump);
    for (final entry in entities.entries) {
      final t = entry.key;
      final pk = entry.value;
      await db.customStatement('''
        INSERT OR IGNORE INTO $table (entity, row_id, updated_at, deleted_at, seq)
        SELECT '$t', $pk, $_nowMillis, NULL, $_currentSeq FROM $t
      ''');
    }
  }

  static SyncMark _markOf(QueryRow r) => SyncMark(
        entity: r.read<String>('entity'),
        rowId: r.read<String>('row_id'),
        updatedAt: r.read<int>('updated_at'),
        deletedAt: r.readNullable<int>('deleted_at'),
        seq: r.readNullable<int>('seq') ?? 0,
      );

  /// كل العلامات مفهرسة بـ `entity/rowId`.
  Future<Map<String, SyncMark>> snapshot() async {
    final rows = await db.customSelect('SELECT * FROM $table').get();
    return {
      for (final r in rows) '${r.read<String>('entity')}/${r.read<String>('row_id')}': _markOf(r),
    };
  }

  /// العلامات التي تغيّر **ختمها** بعد [stamp] — المسار القديم للمزامنة
  /// التفاضلية، باقٍ لنظيرٍ بإصدارٍ أقدم لا يعرف [changedSinceSeq].
  ///
  /// المقارنة على `stamp` لا على `updated_at` وحده: شاهد الحذف يحمل ختمه في
  /// `deleted_at`، فلو قِيس بالتعديل وحده لما انتقل حذفٌ وقع بعد آخر مزامنة.
  Future<List<SyncMark>> changedSince(int stamp) async {
    final rows = await db.customSelect(
      'SELECT * FROM $table WHERE MAX(updated_at, COALESCE(deleted_at, 0)) > ?',
      variables: [Variable<int>(stamp)],
    ).get();
    return [for (final r in rows) _markOf(r)];
  }

  /// العلامات التي كُتبت على هذا الجهاز بعد الرقم [seq] — أساس المزامنة
  /// التفاضلية: يشمل ما كُتب هنا وما وصل من قرينٍ آخر، أيًّا كانت ساعة كاتبه.
  Future<List<SyncMark>> changedSinceSeq(int seq) async {
    final rows = await db.customSelect(
      'SELECT * FROM $table WHERE seq > ?',
      variables: [Variable<int>(seq)],
    ).get();
    return [for (final r in rows) _markOf(r)];
  }

  /// أحدث ختم في هذا الجهاز — علامة الماء **القديمة** (نظيرٌ بإصدارٍ أقدم).
  /// لا تصلح لغيره: هي خليطٌ من ساعات الأجهزة كلها، انظر [maxSeq].
  Future<int> maxStamp() async {
    final row = await db
        .customSelect('SELECT COALESCE(MAX(MAX(updated_at, COALESCE(deleted_at, 0))), 0) AS m '
            'FROM $table')
        .getSingle();
    return row.read<int>('m');
  }

  /// قيمة عدّاد هذا الجهاز الآن — علامة الماء التي يحفظها القرين ليطلب ما بعدها.
  Future<int> maxSeq() async {
    final row = await db.customSelect('SELECT v FROM $seqTable WHERE k = 1').getSingleOrNull();
    return row?.read<int>('v') ?? 0;
  }

  /// يكتب علامة صراحةً — يُستعمل بعد الدمج لتثبيت الختم الفائز بدل الختم
  /// الذي كتبه المحفِّز لحظة الاستيراد.
  ///
  /// [keepSeq]: العلامة لم تتغيّر على هذا الجهاز (الوارد نسخةٌ مما عندنا)،
  /// فيُعاد رقمها القديم ولا تُعدّ «تغييرًا» يُرسل للأقران من جديد — وإلا
  /// تبادل جهازان السجلَّ نفسه في كل دورة إلى الأبد. وإلا أخذت رقمًا جديدًا.
  Future<void> put(SyncMark mark, {bool keepSeq = false}) async {
    if (keepSeq) {
      await db.customStatement(
        'INSERT INTO $table (entity, row_id, updated_at, deleted_at, seq) VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT (entity, row_id) DO UPDATE '
        'SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at, seq = excluded.seq',
        [mark.entity, mark.rowId, mark.updatedAt, mark.deletedAt, mark.seq],
      );
      return;
    }
    await db.customStatement(_bump);
    await db.customStatement(
      'INSERT INTO $table (entity, row_id, updated_at, deleted_at, seq) VALUES (?, ?, ?, ?, $_currentSeq) '
      'ON CONFLICT (entity, row_id) DO UPDATE '
      'SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at, seq = excluded.seq',
      [mark.entity, mark.rowId, mark.updatedAt, mark.deletedAt],
    );
  }

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
