import 'dart:convert';

/// حجب الأقسام عن مستخدم: قسم الإمداد، وقسم المحروقات، وخمسة أقسامٍ إداريةٍ فرعية.
///
/// **طبقةٌ فوق الصلاحيات لا بديلٌ عنها:** الصلاحيات تقول ماذا يفعل المستخدم في
/// كل صفحة؛ الحجب يقول إن هذا القسم **كله** ليس له — مهما كانت صلاحياته (ومنها
/// المدير الذي يملك كل الصفحات). والمالك وحده لا يُحجب عنه شيء.
///
/// **فشلٌ مغلق:** قيمةٌ تالفة (JSON لا يُقرأ، أو ليست قائمة) تُعامل حجبًا للكل
/// ([parse])؛ فتلفٌ بالمزامنة أو بتعديلٍ يدويٍّ لا يفتح قسمًا كان مغلقًا.
class SectionBlock {
  const SectionBlock._();

  static const String supply = 'supply';
  static const String fuel = 'fuel';
  static const String adminSettings = 'admin.settings';
  static const String adminUsers = 'admin.users';
  static const String adminAudit = 'admin.audit';
  static const String adminSync = 'admin.sync';
  static const String adminDevices = 'admin.devices';

  /// كل الأقسام القابلة للحجب، بترتيب عرضها.
  static const List<String> all = [
    supply,
    fuel,
    adminSettings,
    adminUsers,
    adminAudit,
    adminSync,
    adminDevices,
  ];

  static const Map<String, String> labels = {
    supply: 'قسم الإمداد والتموين',
    fuel: 'قسم المحروقات',
    adminSettings: 'الإعدادات العامة (الهوية، النماذج، التوقيع الإلكتروني، النسخ الاحتياطي)',
    adminUsers: 'المستخدمون',
    adminAudit: 'سجل التدقيق والرقابة',
    adminSync: 'المزامنة',
    adminDevices: 'تفعيل الأجهزة',
  };

  /// أقسام شاشة الإعدادات الداخلية ← القسم الذي يحجبها.
  ///
  /// «نظرة عامة» والمخزون والطباعة وغيرها لا تتبع حجبًا: شاشة الإعدادات نفسها تبقى
  /// متاحةً، وما يُخفى هو أقسامها المحجوبة فقط.
  static const Map<String, String> settingsSections = {
    'company': adminSettings,
    'forms': adminSettings,
    'verify': adminSettings,
    'backup': adminSettings,
    'users': adminUsers,
    'sync': adminSync,
    'devices': adminDevices,
  };

  /// صفحاتٌ إدارية مباشرة (تفتح الإعدادات على قسمٍ بعينه أو تدقّق).
  static const Map<String, String> _adminPages = {
    'branding': adminSettings,
    'formsDesigner': adminSettings,
    'verifySign': adminSettings,
    'usersAccess': adminUsers,
    'lanSync': adminSync,
    'deviceActivation': adminDevices,
    'supplyAudit': adminAudit,
    'auditTrail': adminAudit,
    'activityIntel': adminAudit,
    'executiveCmd': adminAudit,
    'sensitiveOps': adminAudit,
    'healthOps': adminAudit,
    'audit': adminAudit,
  };

  /// صفحاتٌ محايدة: الرئيسية تتبع القسم المفتوح، والإعدادات تُرشَّح أقسامها.
  static const Set<String> _neutral = {'dash', 'dashboard', 'settings'};

  /// القسم الذي تنتمي إليه [page]، أو `null` لصفحةٍ محايدة.
  ///
  /// تُمرَّر **هوية الصفحة الأصلية** لا المطبَّعة: `lanSync` تُطبَّع إلى صلاحيةٍ
  /// نظامية، فيضيع انتماؤها الإداري لو طُبِّعت قبل السؤال.
  static String? sectionOf(String page) {
    if (_neutral.contains(page)) return null;
    final admin = _adminPages[page];
    if (admin != null) return admin;
    if (page.startsWith('fuel')) return fuel;
    return supply;
  }

  // ───────────────────────── القراءة والكتابة

  /// قائمة الأقسام المحجوبة من JSON المخزَّن. التالف ⇒ **كل الأقسام** (فشل مغلق).
  static Set<String> parse(String? json) {
    final text = (json ?? '').trim();
    if (text.isEmpty) return <String>{};
    try {
      final v = jsonDecode(text);
      if (v is! List) return {...all};
      return {for (final e in v) if (e is String && all.contains(e)) e};
    } catch (_) {
      return {...all};
    }
  }

  /// يرمّز مجموعةً إلى JSON مرتّب بلا تكرار وبلا أقسامٍ مجهولة — ترميزٌ **حتميّ**
  /// لأن التوقيع يُحسب على نصّه.
  static String encode(Iterable<String> sections) {
    final set = {for (final s in sections) if (all.contains(s)) s};
    return jsonEncode([for (final s in all) if (set.contains(s)) s]);
  }

  // ───────────────────────── الفحص

  /// هل تُحجب [page] عن حسابٍ بدور [role] وحجبه [blockedJson]؟
  /// المالك لا يُحجب عنه شيء.
  static bool blocksPage({required String? role, required String? blockedJson, required String page}) {
    if (role == 'owner') return false;
    final section = sectionOf(page);
    if (section == null) return false;
    return parse(blockedJson).contains(section);
  }

  /// هل [section] (من [all]) محجوبٌ عن هذا الحساب؟ المالك لا.
  static bool blocksSection({required String? role, required String? blockedJson, required String section}) {
    if (role == 'owner') return false;
    return parse(blockedJson).contains(section);
  }
}
