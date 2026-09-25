import 'package:drift/drift.dart';

import '../../core/security/device_activation.dart';
import '../db/app_database.dart';

/// ترقيم السندات: «و-K7QX-000001» = البادئة ثم رمز الجهاز ثم تسلسل الجهاز.
///
/// **رمز الجهاز**: كان كل جهاز يبدأ من «و-000001»، فيحمل سندان مختلفان في فرعين
/// الرقم نفسه بعد المزامنة. الرمز أول أربعة أحرف من معرّف الجهاز الثابت
/// ([DeviceActivation.deviceId])، فلا يتصادم فرعان.
///
/// **العدّاد المخزَّن**: كان الرقم التالي يُحسب بقراءة كل مراجع الجدول في كل
/// فتح لشاشة. العدّاد الآن في جدول محلي `doc_counters` — **خارج المزامنة عمدًا**:
/// لو زُومن لكتب جهازٌ عدّادَه فوق عدّاد جهاز آخر فرجع تسلسله إلى الوراء.
///
/// [peek] يعرض الرقم التالي دون أن يستهلكه (تفتح الشاشة وتُغلق بلا فجوة في
/// التسلسل)، و[claim] يثبّته عند الحفظ الفعلي داخل معاملة الحفظ.
class DocNumbering {
  DocNumbering(this.db);

  final AppDatabase db;

  static const String _table = 'doc_counters';
  static const int _width = 6;

  String? _code;

  /// رمز هذا الجهاز في المراجع (أربعة أحرف كبيرة).
  Future<String> deviceCode() async => _code ??= (await DeviceActivation(db).idSeed()).toUpperCase();

  /// الرقم التالي لجدول وبادئة، دون حجزه.
  Future<String> peek(String table, String prefix) async {
    final head = '$prefix${await deviceCode()}-';
    final n = await _counter(table, prefix);
    return '$head${(n + 1).toString().padLeft(_width, '0')}';
  }

  /// تثبيت مرجع حُفظ به سند: يتقدّم العدّاد إليه إن كان بصيغة هذا الجهاز.
  /// المرجع اليدوي أو الوارد من جهاز آخر لا يمس العدّاد.
  Future<void> claim(String table, String prefix, String ref) async {
    final head = '$prefix${await deviceCode()}-';
    if (!ref.startsWith(head)) return;
    final n = int.tryParse(ref.substring(head.length));
    if (n == null) return;
    final current = await _counter(table, prefix);
    if (n > current) await _store(table, prefix, n);
  }

  Future<int> _counter(String table, String prefix) async {
    await _ensureTable();
    final key = _key(table, prefix);
    final row = await db
        .customSelect('SELECT value FROM $_table WHERE key = ?', variables: [Variable.withString(key)])
        .getSingleOrNull();
    if (row != null) return row.read<int>('value');
    // أول استخدام على هذا الجهاز: يُكمل من أعلى رقم موجود في الجدول (بالصيغة
    // القديمة أو الجديدة) حتى لا يبدو التسلسل وكأنه بدأ من جديد. قراءة واحدة فقط.
    final seed = await _maxExisting(table);
    await _store(table, prefix, seed);
    return seed;
  }

  Future<int> _maxExisting(String table) async {
    final rows = await db.customSelect('SELECT DISTINCT ref_no AS r FROM $table').get();
    var max = 0;
    final trailing = RegExp(r'(\d+)$');
    for (final row in rows) {
      final m = trailing.firstMatch((row.data['r'] ?? '').toString());
      final n = m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
      if (n > max) max = n;
    }
    return max;
  }

  Future<void> _store(String table, String prefix, int value) => db.customStatement(
        'INSERT INTO $_table (key, value) VALUES (?, ?) '
        'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
        [_key(table, prefix), value],
      );

  static String _key(String table, String prefix) => '$table|$prefix';

  bool _ready = false;
  Future<void> _ensureTable() async {
    if (_ready) return;
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $_table (key TEXT NOT NULL PRIMARY KEY, value INTEGER NOT NULL)',
    );
    _ready = true;
  }
}
