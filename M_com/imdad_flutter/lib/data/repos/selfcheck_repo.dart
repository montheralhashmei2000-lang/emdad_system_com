import 'dart:convert';

import '../../core/ui/imd_format.dart';
import '../db/app_database.dart';
import 'catalog_repo.dart';
import 'movements_repo.dart';
import 'settings_repo.dart';

/// نتيجة فحص واحد (`IMDAD_SELFCHECK.checks[i]`).
class SelfCheckResult {
  const SelfCheckResult({required this.id, required this.label, required this.ok, this.note = ''});
  final String id;
  final String label;
  final bool ok;
  final String note;
}

/// فحص سلامة النظام — نقل `IMDAD_SELFCHECK`:
/// يتحقق من عمل قاعدة البيانات وحسابات الدخول وتخطيط الطباعة،
/// ومن اتساق البيانات (ربط المستودعات بالمعسكرات، وحدات الاستحقاقات، السجلات اليتيمة).
class SelfCheckRepo {
  SelfCheckRepo(this.db, {this.appVersion = ''});

  final AppDatabase db;
  final String appVersion;

  Future<List<SelfCheckResult>> runAll() async {
    final out = <SelfCheckResult>[];
    Future<void> run(String id, String label, Future<(bool, String)> Function() fn) async {
      try {
        final (ok, note) = await fn();
        out.add(SelfCheckResult(id: id, label: label, ok: ok, note: note));
      } catch (e) {
        out.add(SelfCheckResult(id: id, label: label, ok: false, note: 'فشل الفحص: $e'));
      }
    }

    await run('version', 'إصدار التطبيق', () async {
      return (appVersion.isNotEmpty, appVersion.isEmpty ? 'غير محدد' : appVersion);
    });

    await run('db', 'قاعدة البيانات المحلية', () async {
      await db.select(db.appSettings).get();
      return (true, 'تعمل');
    });

    // `PRAGMA key` على SQLite العادية تمرّ بلا خطأ ولا تشفّر شيئًا، فلا يكفي
    // أن يكون التشفير مطلوبًا في الكود — يجب سؤال المكتبة المحمَّلة فعلًا.
    await run('encryption', 'تشفير قاعدة البيانات', () async {
      final rows = await db.customSelect('PRAGMA cipher_version').get();
      final version = rows.isEmpty ? '' : '${rows.first.data.values.first ?? ''}';
      return version.isEmpty
          ? (false, 'غير مشفّرة — المكتبة المحمَّلة ليست SQLCipher')
          : (true, 'مشفّرة (SQLCipher $version)');
    });

    await run('authUsers', 'حسابات المستخدمين المسجّلة', () async {
      final users = await db.select(db.users).get();
      return (
        users.isNotEmpty,
        users.isEmpty ? 'لا يوجد أي حساب — قد تفقد الوصول للنظام' : '${nf(users.length)} حساب',
      );
    });

    await run('printLayout', 'تخطيط النماذج المطبوعة', () async {
      final repo = SettingsRepo(db);
      final layout = await repo.printLayout();
      final ok = layout.right.isNotEmpty || layout.info.isNotEmpty;
      // عددُ المطبوعات المُفردة بتصميمٍ خاص: يجعل الميزة مرئيةً في الفحص،
      // فمن وجد مطبوعةً تخرج بهيئة غير المتوقَّعة عرف من هنا أنها مُفردة.
      final custom = (await repo.customizedPrintForms()).length;
      final tail = custom == 0 ? '' : ' · ${nf(custom)} مطبوعة بتصميم خاص';
      return (ok, (ok ? 'محفوظ وجاهز' : 'لم يُضبط بعد — ستُستخدم القيم الافتراضية') + tail);
    });

    await run('campLink', 'اتساق ربط المستودعات بالمعسكرات', () async {
      final whs = await db.select(db.warehouses).get();
      var linked = 0, broken = 0;
      final campIds = {
        for (final u in await db.select(db.beneficiaryUnits).get())
          if (u.isCamp || u.type == 'camp') u.id,
      };
      for (final w in whs) {
        final ids = _idList(w.campIds);
        if (w.feedsAllCamps || ids.isNotEmpty) linked++;
        // معسكر مرتبط لكنه محذوف من شجرة الوحدات.
        if (ids.any((id) => !campIds.contains(id))) broken++;
      }
      return (
        broken == 0,
        broken > 0
            ? '${nf(broken)} مستودع مرتبط بمعسكر محذوف — يحتاج إعادة ضبط'
            : '${nf(linked)} مستودع مرتبط',
      );
    });

    await run('entUnits', 'اتساق وحدات قياس الاستحقاقات', () async {
      final catalog = CatalogRepo(db);
      final items = {for (final i in await catalog.items()) i.id: i};
      final ents = await db.select(db.entitlements).get();
      var bad = 0;
      for (final e in ents) {
        final it = items[e.itemId];
        if (it == null || e.measureUnitName.isEmpty) continue;
        final units = catalog.unitsOf(it);
        if (units.isNotEmpty && !units.any((u) => u.name == e.measureUnitName)) bad++;
      }
      return (
        bad == 0,
        bad > 0
            ? '${nf(bad)} استحقاق بوحدة قياس غير معرّفة في الصنف — الحساب سيكون خاطئًا'
            : 'كل الوحدات متطابقة',
      );
    });

    await run('orphanEnt', 'استحقاقات بلا أصناف', () async {
      final ids = {for (final i in await db.select(db.items).get()) i.id};
      final orphan =
          (await db.select(db.entitlements).get()).where((e) => !ids.contains(e.itemId)).length;
      return (
        orphan == 0,
        orphan > 0 ? '${nf(orphan)} استحقاق مرتبط بصنف محذوف' : 'لا توجد سجلات يتيمة',
      );
    });

    await run('dupUsernames', 'أسماء دخول مكرّرة', () async {
      // لا قيد تفرّد على `users.username`: إضافته لجدولٍ قائم تُسقط مشغّلات
      // المزامنة المعلّقة عليه، وقاعدةٌ فيها تكرارٌ سابق لن تُفتح بعدها أصلًا.
      // فيُكشف التكرار هنا بدل أن يُمنع هناك. و`login` يختار بترتيبٍ محدَّد
      // (المحلي ثم الأحدث) فلا يتنقّل بين الحسابين، لكن بقاء الاثنين يُشوّش
      // الصلاحيات وتغييرَ كلمة المرور — فيُصلحه المدير بحذف أحدهما.
      final seen = <String, int>{};
      for (final usr in await db.select(db.users).get()) {
        final key = usr.username.trim().toLowerCase();
        if (key.isEmpty) continue;
        seen[key] = (seen[key] ?? 0) + 1;
      }
      final dups = [
        for (final e in seen.entries)
          if (e.value > 1) '«${e.key}» ×${e.value}',
      ];
      return (
        dups.isEmpty,
        dups.isEmpty
            ? 'كل أسماء الدخول مفردة'
            : 'اسمٌ واحد لأكثر من حساب: ${dups.join('، ')} — احذف الزائد',
      );
    });

    await run('orphanMoves', 'حركات بأصناف محذوفة', () async {
      final ids = {for (final i in await db.select(db.items).get()) i.id};
      var orphan = 0;
      for (final r in await db.select(db.receipts).get()) {
        if (!ids.contains(r.itemId)) orphan++;
      }
      for (final r in await db.select(db.issues).get()) {
        if (!ids.contains(r.itemId)) orphan++;
      }
      for (final r in await db.select(db.transfers).get()) {
        if (!ids.contains(r.itemId)) orphan++;
      }
      for (final r in await db.select(db.returns).get()) {
        if (!ids.contains(r.itemId)) orphan++;
      }
      return (
        orphan == 0,
        orphan > 0
            ? '${nf(orphan)} سطر حركة يشير إلى صنف محذوف — سيختل حساب الرصيد'
            : 'كل سطور الحركات مرتبطة بأصناف قائمة',
      );
    });

    // لا تُمنَع هذه الحالة عند الحفظ بل تنشأ بعد دمج جهازين صرف كلٌّ منهما الرصيد
    // نفسه قبل المزامنة، فالكشف هنا هو الحل: القرار (تسوية جرد أو إلغاء سند) إداري.
    await run('negativeStock', 'أرصدة مخزون سالبة', () async {
      final negatives = await MovementsRepo(db).negativeBalances();
      if (negatives.isEmpty) return (true, 'لا توجد أرصدة سالبة');
      final names = {for (final i in await db.select(db.items).get()) i.id: i.name};
      final sample = negatives
          .take(3)
          .map((n) => '${names[n.itemId] ?? n.itemId} في ${n.warehouse} (${nf(n.qty)})')
          .join('، ');
      return (
        false,
        '${nf(negatives.length)} رصيد سالب — راجع سندات الصرف أو سوِّ بالجرد. أشدّها: $sample',
      );
    });

    await run('orphanStocktake', 'سطور جرد بلا أمر', () async {
      final ids = {for (final s in await db.select(db.stocktakes).get()) s.id};
      final orphan =
          (await db.select(db.stocktakeLines).get()).where((l) => !ids.contains(l.sessionId)).length;
      return (
        orphan == 0,
        orphan > 0 ? '${nf(orphan)} سطر جرد بلا أمر — يُنصح بحذفه' : 'لا توجد سطور يتيمة',
      );
    });

    await run('itemUnits', 'وحدات القياس في الأصناف', () async {
      final catalog = CatalogRepo(db);
      var bad = 0;
      for (final it in await catalog.items()) {
        final units = catalog.unitsOf(it);
        if (it.baseUnit.isEmpty || !units.any((u) => u.name == it.baseUnit)) bad++;
      }
      return (
        bad == 0,
        bad > 0
            ? '${nf(bad)} صنف بلا وحدة أساس معرّفة ضمن وحداته'
            : 'كل الأصناف لها وحدة أساس سليمة',
      );
    });

    await run('frozenWh', 'المستودعات المجمّدة للجرد', () async {
      final frozen = (await db.select(db.stocktakes).get())
          .where((s) => s.freeze && s.status == 'COUNTING')
          .map((s) => s.warehouse)
          .toSet();
      return (
        frozen.length <= 1,
        frozen.isEmpty
            ? 'لا توجد مستودعات مجمّدة'
            : '${nf(frozen.length)} مستودع مجمّد: ${frozen.join('، ')}',
      );
    });

    return out;
  }

  static List<String> _idList(String json) {
    try {
      final raw = jsonDecode(json);
      return raw is List ? raw.map((e) => '$e').where((e) => e.isNotEmpty).toList() : const [];
    } catch (_) {
      return const [];
    }
  }
}
