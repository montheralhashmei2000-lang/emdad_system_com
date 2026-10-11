part of '../legacy_import.dart';

/// أساس الاستيراد: علامات المزامنة وترجيح الأحدث، والأدوات القياسية
/// لقراءة حقول الحمولة.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyBase {
  /// يُنفِّذهما حقلا [LegacyImporter] نفسه: مُعلَنان هنا لأن كل الأجزاء
  /// تقرأ القاعدة، و[_LegacyUsers] يقرأ مفتاح المالك.
  AppDatabase get db;
  String get _ownerKey;

  /// علامات الجهازين: المحلية كما كانت **قبل** الاستيراد (المحفِّزات ستغيّرها
  /// أثناءه)، والواردة مع الحمولة.
  Map<String, SyncMark> _local = const {};
  Map<String, SyncMark> _incoming = const {};

  /// علامات (`entity/rowId`) رُفض سجلُّها أو شاهدُ حذفها في هذا الاستيراد: لا
  /// يُثبَّت ختمُها الوارد في `_settleMarks`، فيبقى الختم المحلي على القيمة المحلية.
  Set<String> _rejectedMarks = {};

  /// علامات سجلاتٍ كتبها الاستيراد **بقيمة مختلفة رغم تساوي الختمين** (حسمُ
  /// تعادل الإعدادات): تغيّرت هنا فعلًا فتأخذ رقم تسلسلٍ جديدًا في
  /// `_settleMarks` لتبلغ من سحب القيمة القديمة منّا.
  Set<String> _changedOnTie = {};

  /// معرّفاتٌ حُسم تعارض مفتاحها الطبيعي في هذا الاستيراد: الجدول ← (الخاسر ←
  /// الفائز). تُترجم بها المراجع في الصفوف الواردة بعدها ([_ref])، فلا يُكتب
  /// سجلٌّ يشير إلى وحدةٍ حُذفت للتوّ.
  Map<String, Map<String, String>> _replacedIds = {};

  String _ref(String entity, String id) => _replacedIds[entity]?[id] ?? id;

  /// هل يُقبل السجل الوارد؟ يفوز الأحدث ختمًا؛ وعند تساوي الختم يفوز الوارد
  /// (السجلان متطابقان عمليًا، والترجيح الثابت يمنع تذبذب الأجهزة).
  bool _accept(String entity, String rowId) {
    if (rowId.isEmpty) return true;
    final local = _local['$entity/$rowId'];
    if (local == null) return true;
    final incoming = _incoming['$entity/$rowId'];
    if (incoming == null) return false;
    return incoming.stamp >= local.stamp;
  }

  // ───────── أدوات مساعدة ─────────
  List<Map<String, dynamic>> _rows(Object? v) {
    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  String _s(Map<String, dynamic> m, String k, [String def = '']) {
    final v = m[k];
    if (v == null) return def;
    return v.toString();
  }

  /// كميات السجل الوارد غير سالبة؟ السالب يُتجاوز مع تحذير: مشغّل القاعدة سيرفضه
  /// برمي استثناء، والاستيراد كله معاملة واحدة، فسجلٌّ معيب واحد كان سيُجهض الحمولة
  /// كلها ويتكرر الإجهاض في كل مزامنة.
  bool _quantitiesOk(Map<String, dynamic> r, String table, LegacyImportResult res, {bool hasFactor = true}) {
    final bad = _d(r, 'qty') < 0 || _d(r, 'baseQty') < 0 || (hasFactor && _d(r, 'factor', 1) < 0);
    if (bad) {
      res.warnings.add('تُجوِّز سجل بكمية سالبة في $table (${_id(r)})');
      // لم يُكتب، فلا تُثبَّت علامته: علامةٌ بلا صفٍّ تقول إن الجهاز يحمل
      // نسخةً لا يحملها، فلا تُطلب ثانيةً.
      _rejectedMarks.add('$table/${_s(r, 'id')}');
    }
    return !bad;
  }

  double _d(Map<String, dynamic> m, String k, [double def = 0]) {
    final v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? def;
    return def;
  }

  /// عدد دورات PBKDF2 القادم من نظيرٍ مزامَن: يُحصر بين القديم والحالي فلا يُضعِف الهاش (رقم صغير)
  /// ولا يجمّد الدخول (رقم ضخم). القيمة غير الموجبة تبقى كما هي: `verify` يرفضها أصلًا.
  int _safeIterations(int n) => n < 1 ? n : n.clamp(Pbkdf2.legacyIterations, Pbkdf2.iterations).toInt();

  int _i(Map<String, dynamic> m, String k, [int def = 0]) =>
      _d(m, k, def.toDouble()).round();

  bool _b(Map<String, dynamic> m, String k, [bool def = false]) {
    final v = m[k];
    if (v is bool) return v;
    if (v is String) return v == 'true' || v == '1';
    return def;
  }

  String _json(Object? v, [String def = '[]']) {
    if (v == null) return def;
    if (v is String) return v;
    return jsonEncode(v);
  }

  String _id(Map<String, dynamic> m) {
    final id = _s(m, 'id');
    if (id.isNotEmpty) return id;
    return 'imp-${DateTime.now().microsecondsSinceEpoch}-${m.hashCode.abs()}';
  }

  DateTime _created(Map<String, dynamic> m) {
    final v = m['createdAt'];
    if (v is Map && v['seconds'] is num) {
      return DateTime.fromMillisecondsSinceEpoch(
          ((v['seconds'] as num) * 1000).round());
    }
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.round());
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  void _count(LegacyImportResult res, String key, int n) =>
      res.inserted[key] = (res.inserted[key] ?? 0) + n;
}
