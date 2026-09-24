import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ui/imd_fonts.dart';
import '../db/app_database.dart';
import '../../domain/print_layout.dart';

/// هوية التطبيق والجهة (`APP_CFG` في الويب): الاسم والشعار وأسطر الترويسة والسمة.
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
      };
}

/// الإعدادات العامة المحفوظة بصيغة JSON (هوية الجهة، تخطيط الطباعة، النماذج).
class SettingsRepo {
  SettingsRepo(this.db);

  final AppDatabase db;

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

  Future<PrintLayout> printLayout() async {
    final map = await read(printLayoutKey);
    return map.isEmpty ? PrintLayout.defaults : PrintLayout.fromMap(map);
  }

  Future<void> savePrintLayout(PrintLayout layout) => write(printLayoutKey, layout.toMap());

  /// `loadAppConfig()` — هوية التطبيق والجهة.
  Future<AppIdentity> identity() async {
    final map = await read(orgKey);
    return map.isEmpty ? const AppIdentity() : AppIdentity.fromMap(map);
  }

  Future<void> saveIdentity(AppIdentity id) => write(orgKey, id.toMap());
}
