import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ui/imd_fonts.dart';
import '../../core/ui/imd_numbers.dart';
import '../db/app_database.dart';
import '../../domain/print_layout.dart';

/// هوية التطبيق والجهة: الاسم والشعار وأسطر الترويسة والسمة.
class AppIdentity {
  const AppIdentity({
    this.name = 'نظام الإمداد والتموين',
    this.logoBase64 = '',
    this.logoSize = 140,
    this.themePref = 'auto',
    this.fontFamily = ImdFonts.defaultFamily,
    this.orgLine1 = '',
    this.orgLine2 = '',
    this.orgLine3 = '',
    this.orgLine4 = '',
    this.showExpiry = true,
  });

  final String name;

  /// الشعار مخزَّنًا Base64 (بلا بادئة data:) — يعمل دون إنترنت.
  final String logoBase64;
  final double logoSize;

  /// light | dark | auto
  final String themePref;

  /// خط الواجهة المختار (انظر [ImdFonts]).
  final String fontFamily;
  final String orgLine1;
  final String orgLine2;
  final String orgLine3;
  final String orgLine4;

  /// هل يظهر حقل «تاريخ الانتهاء» في جداول إدخال الأصناف؟
  ///
  /// **مخزنٌ بلا موادّ تنتهي لا يحتاجه**، وعمودٌ لا يُملأ يضيّق على ما
  /// يُملأ. وهو عرضٌ لا حفظ: إخفاؤه لا يمسّ تواريخ سُجّلت.
  final bool showExpiry;

  List<String> get orgLines =>
      [orgLine1, orgLine2, orgLine3, orgLine4].where((l) => l.trim().isNotEmpty).toList();

  AppIdentity copyWith({
    String? name,
    String? logoBase64,
    double? logoSize,
    String? themePref,
    String? fontFamily,
    String? orgLine1,
    String? orgLine2,
    String? orgLine3,
    String? orgLine4,
    bool? showExpiry,
  }) =>
      AppIdentity(
        name: name ?? this.name,
        logoBase64: logoBase64 ?? this.logoBase64,
        logoSize: logoSize ?? this.logoSize,
        themePref: themePref ?? this.themePref,
        fontFamily: fontFamily ?? this.fontFamily,
        orgLine1: orgLine1 ?? this.orgLine1,
        orgLine2: orgLine2 ?? this.orgLine2,
        orgLine3: orgLine3 ?? this.orgLine3,
        orgLine4: orgLine4 ?? this.orgLine4,
        showExpiry: showExpiry ?? this.showExpiry,
      );

  factory AppIdentity.fromMap(Map<String, dynamic> m) => AppIdentity(
        name: '${m['name'] ?? 'نظام الإمداد والتموين'}',
        logoBase64: '${m['logoBase64'] ?? ''}',
        fontFamily: ImdFonts.normalize('${m['fontFamily'] ?? ''}'),
        logoSize: (m['logoSize'] is num) ? (m['logoSize'] as num).toDouble() : 140,
        themePref: '${m['themePref'] ?? 'auto'}',
        orgLine1: '${m['orgLine1'] ?? ''}',
        orgLine2: '${m['orgLine2'] ?? ''}',
        orgLine3: '${m['orgLine3'] ?? ''}',
        orgLine4: '${m['orgLine4'] ?? ''}',
        showExpiry: m['showExpiry'] != false,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'logoBase64': logoBase64,
        'logoSize': logoSize,
        'themePref': themePref,
        'fontFamily': fontFamily,
        'orgLine1': orgLine1,
        'orgLine2': orgLine2,
        'orgLine3': orgLine3,
        'orgLine4': orgLine4,
        'showExpiry': showExpiry,
      };
}

/// الإعدادات العامة المحفوظة بصيغة JSON (هوية الجهة، تخطيط الطباعة، النماذج).
class SettingsRepo {
  SettingsRepo(this.db);

  final AppDatabase db;

  /// مفاتيح خاصة بهذا الجهاز لا تغادره بالمزامنة أبدًا: رمز تفعيله ومعرّفه (وعلى
  /// جهاز الإدارة مفتاح المالك الخاص)، وسجلّ الأجهزة المُصدَر لها، وختوم الإلغاء
  /// (تسافر بقناتها الخاصة `deviceRevocations`). كان التصدير يحملها كلها.
  static const Set<String> localOnlyKeys = {
    'device', 'devices', 'revocations', 'ocr',
    // قفل الدخول والجلسة: حالةُ هذا الجهاز وحده، ولا يجوز أن يسافر أو يُستورد.
    'authSession', 'authLocks',
    // إعدادات أمان الجهاز: مهلة القفل التلقائي.
    'security',
    // جدولة النسخ الاحتياطي: مجلد الجهاز وآخر تشغيلة.
    'backupSchedule',
    // تنبيه «انتقلت الصلاحيات الخاصة للمالك»: هل رآه كلُّ مدير على هذا الجهاز؟
    'sysNotice',
    // مسودة الصرف المستعادة تلقائيًا لكل مستخدم: بيانات سند غير مُعتمد، تبقى في
    // القاعدة المشفّرة لا في SharedPreferences (ملفٌّ نصيٌّ مقروء).
    'issueRecovery',
    // إعدادات المزامنة وسجلّ الثقة (`SyncTrust.settingsKey`). **سرٌّ وحالةٌ معًا:**
    //
    // • سرٌّ: كل جهاز موثوق محفوظ هنا بمفتاحه الدائم hex (`TrustedPeer.toMap`).
    //   لو سافر الصفّ لحمل الفرعُ مفاتيحَ كل أجهزة الوحدة، فوقّع بمفتاح جهازٍ
    //   آخر وانتحله انتحالًا كاملًا — وانهار عزل الثقة الذي بُنيت عليه
    //   المزامنة كلها. والنسخة الاحتياطية بلا كلمة مرور تكتبها JSON صريحًا.
    //
    // • حالةٌ محلية: علامات الماء (`pulledUpTo`/`pushedUpTo`) مقيسةٌ بساعة هذا
    //   الجهاز ولكل قرينٍ على حدة. والاستيراد يستبدل قيمة المفتاح **كاملةً**،
    //   فجهازٌ له عدة أقران (الإدارة) كان يفقد علاماتِ بقيتهم عند كل سحبة —
    //   وعلامةٌ تقفز للأمام تعني سجلاتٍ لا تُزامَن أبدًا — بل يفقد أسطرهم من
    //   `peers` فتتوقف مزامنتهم بصمت، ويرث `accepted` القرينِ فيثق بمن لم
    //   يقترن به.
    //
    // مكتوبٌ حرفًا لا `SyncTrust.settingsKey`: ذاك الملف يستورد هذا، فالإشارة
    // إليه تُحدث حلقة استيراد. يربطهما اختبارٌ بدلها (`sync_trust_local_test`).
    'sync',
    // مفاتيح التوقيع الإلكتروني (`ESign`): المفتاح **الخاص** للقائد hex في `priv`.
    // كان يخرج مع كل حمولة مزامنة وكل نسخة احتياطية (وJSON صريحًا بلا كلمة مرور)،
    // فمن بلغه زوّر توقيع القائد على السندات المطبوعة. المفتاح العام وحده يُنشر
    // (يُطبع مع الرمز ويُتحقق به)، والخاص لا يغادر جهاز الموقِّع.
    'esign',
  };

  static const String issueRecoveryKey = 'issueRecovery';

  /// مسودة الصرف المحفوظة تلقائيًا للمستخدم [userId]، أو `null`.
  Future<Map<String, dynamic>?> readIssueRecovery(String userId) async {
    final v = (await read(issueRecoveryKey))[userId];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Future<void> writeIssueRecovery(String userId, Map<String, dynamic> snapshot) async {
    final all = await read(issueRecoveryKey);
    all[userId] = snapshot;
    await write(issueRecoveryKey, all);
  }

  Future<void> clearIssueRecovery(String userId) async {
    final all = await read(issueRecoveryKey);
    if (all.remove(userId) == null) return;
    await write(issueRecoveryKey, all);
  }

  static const String printLayoutKey = 'printLayout';
  static const String orgKey = 'org';

  Future<Map<String, dynamic>> read(String key) async {
    final rows = await (db.select(db.appSettings)..where((t) => t.key.equals(key))).get();
    if (rows.isEmpty) return {};
    final decoded = jsonDecode(rows.first.value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<void> write(String key, Map<String, dynamic> value) =>
      db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
            key: key,
            value: Value(jsonEncode(value)),
            updatedAt: Value(DateTime.now()),
          ));

  /// تخطيطات النماذج المُفردة: `{ "<مفتاح النموذج>": {<تخطيط>} }`.
  ///
  /// مفتاحٌ **مزامَن** كالتخطيط العام: صورةُ السند معيارُ الجهة كلها لا تفضيلَ
  /// جهاز. ومفتاحٌ مستقلٌّ عن `printLayout` حتى يبقى الافتراضي العام مقروءًا
  /// بإصدارٍ أقدم كما هو — لا يرى النماذج المُفردة فيطبع بالعام، وهو سلوك
  /// الإصدار السابق بعينه.
  static const String printFormsKey = 'printForms';

  /// تخطيط النموذج [formKey]، أو التخطيط العام إن لم يُفرد النموذج بتصميم.
  ///
  /// [formKey] فارغ (أو `null`) ⇒ التخطيط العام. ومفتاحٌ غير معروف يتبع العام
  /// كذلك: الفهرس قد ينقص مفتاحًا حُذف، فلا تتوقف الطباعة لأجله.
  Future<PrintLayout> printLayoutFor(String? formKey) async {
    if (formKey == null || formKey.isEmpty) return printLayout();
    final own = (await read(printFormsKey))[formKey];
    if (own is! Map) return printLayout();
    return PrintLayout.fromMap(Map<String, dynamic>.from(own));
  }

  Future<PrintLayout> printLayout() async {
    final map = await read(printLayoutKey);
    return map.isEmpty ? PrintLayout.defaults : PrintLayout.fromMap(map);
  }

  Future<void> savePrintLayout(PrintLayout layout) => write(printLayoutKey, layout.toMap());

  /// يُفرد النموذج [formKey] بتخطيطٍ خاص.
  Future<void> savePrintLayoutFor(String formKey, PrintLayout layout) async {
    final all = await read(printFormsKey);
    all[formKey] = layout.toMap();
    await write(printFormsKey, all);
  }

  /// يُعيد النموذج إلى التخطيط العام (يحذف إفراده).
  Future<void> clearPrintLayoutFor(String formKey) async {
    final all = await read(printFormsKey);
    if (all.remove(formKey) == null) return;
    await write(printFormsKey, all);
  }

  /// مفاتيح النماذج المُفردة بتصميمٍ خاص — لوسمها في منتقي المصمم.
  Future<Set<String>> customizedPrintForms() async =>
      (await read(printFormsKey)).entries.where((e) => e.value is Map).map((e) => e.key).toSet();

  /// `loadAppConfig()` — هوية التطبيق والجهة.
  Future<AppIdentity> identity() async {
    final map = await read(orgKey);
    return map.isEmpty ? const AppIdentity() : AppIdentity.fromMap(map);
  }

  Future<void> saveIdentity(AppIdentity id) => write(orgKey, id.toMap());

  static const String numbersKey = ImdNumbers.key;

  /// تفضيلات تنسيق الأرقام — تُزامَن: صورةُ الرقم في السند معيارُ الجهة كلّها.
  Future<ImdNumberPrefs> numbers() async {
    final map = await read(numbersKey);
    return map.isEmpty ? const ImdNumberPrefs() : ImdNumberPrefs.fromMap(map);
  }

  /// يحفظ التفضيل **ويُفعّله في الجلسة** — فلا يُحفظ شيءٌ ويُعرض غيره.
  Future<void> saveNumbers(ImdNumberPrefs p) async {
    await write(numbersKey, p.toMap());
    ImdNumbers.apply(p);
  }

  /// يقرأ التفضيل المحفوظ ويُفعّله — يُنادى مرةً عند الإقلاع.
  Future<void> loadNumbers() async => ImdNumbers.apply(await numbers());
}
