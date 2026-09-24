import 'dart:convert';
import 'dart:typed_data';

import '../../core/security/pbkdf2.dart';
import '../db/app_database.dart';
import '../repos/settings_repo.dart';

/// جهاز موثوق: مفتاح دائم يغني عن رمز الاقتران في كل مزامنة لاحقة.
class TrustedPeer {
  const TrustedPeer({
    required this.deviceId,
    required this.key,
    this.name = '',
    this.host = '',
    this.at,
    this.pulledUpTo = 0,
    this.pushedUpTo = 0,
  });

  /// معرّف الجهاز الآخر (ثمانية أحرف — نفس معرّف بطاقة التفعيل).
  final String deviceId;

  /// المفتاح الدائم المشترك بين الجهازين. لا يغادر الجهاز ولا يُعرض.
  final Uint8List key;

  /// اسم الجهاز كما أعلنه عن نفسه — للعرض وحده.
  final String name;

  /// آخر عنوان عُرف به على الشبكة. تلميح لا أكثر: العنوان يتغيّر، والمعرّف لا.
  final String host;

  final DateTime? at;

  /// أحدث ختم سُحب من هذا الجهاز — **بساعته هو**. المرة القادمة نطلب ما بعده.
  ///
  /// صفر ⇒ لم نسحب منه شيئًا بعد، فتكون السحبة الأولى كاملة. وهي المرة الوحيدة
  /// التي تعبر فيها قاعدة كاملة الشبكةَ: بها يصل الجهاز الجديد إلى حالة الوحدة.
  final int pulledUpTo;

  /// أحدث ختم أُرسل إليه — **بساعتنا نحن**. الختمان لا يُخلطان: كل ساعة تقيس
  /// نفسها، ومقارنة ختم جهاز بساعة جهاز آخر أصل كل خطأ في المزامنة التفاضلية.
  final int pushedUpTo;

  TrustedPeer copyWith({
    String? host,
    String? name,
    DateTime? at,
    int? pulledUpTo,
    int? pushedUpTo,
  }) =>
      TrustedPeer(
        deviceId: deviceId,
        key: key,
        name: name ?? this.name,
        host: host ?? this.host,
        at: at ?? this.at,
        pulledUpTo: pulledUpTo ?? this.pulledUpTo,
        pushedUpTo: pushedUpTo ?? this.pushedUpTo,
      );

  Map<String, dynamic> toMap() => {
        'key': Pbkdf2.toHex(key),
        'name': name,
        'host': host,
        if (at != null) 'at': at!.toIso8601String(),
        'pulledUpTo': pulledUpTo,
        'pushedUpTo': pushedUpTo,
      };

  static TrustedPeer? fromMap(String deviceId, Object? raw) {
    if (raw is! Map) return null;
    final hex = '${raw['key'] ?? ''}';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return null;
    return TrustedPeer(
      deviceId: deviceId,
      key: Pbkdf2.fromHex(hex),
      name: '${raw['name'] ?? ''}',
      host: '${raw['host'] ?? ''}',
      at: DateTime.tryParse('${raw['at'] ?? ''}'),
      pulledUpTo: (raw['pulledUpTo'] as num?)?.toInt() ?? 0,
      pushedUpTo: (raw['pushedUpTo'] as num?)?.toInt() ?? 0,
    );
  }
}

/// إعدادات المزامنة التلقائية وسجلّ الأجهزة الموثوقة — محفوظة في `appSettings`.
///
/// **لماذا قائمتان لا واحدة:** الثقة اتجاه لا علاقة متكافئة. [accepted] من
/// نقبل منهم الطلبات ونحن مستقبِلون، و[peers] من نتصل نحن بهم. جهاز الإدارة
/// غالبًا في القائمتين، وجهاز الفرع في الثانية وحدها. خلطهما يعني أن كل من
/// اتصل بنا مرة صار له حق أن نرسل إليه بياناتنا.
class SyncTrust {
  SyncTrust(this.db);

  final AppDatabase db;

  static const String settingsKey = 'sync';

  /// الدورة الافتراضية: ربع ساعة. أقصر من ذلك يستنزف بطارية الهاتف بلا داعٍ،
  /// وأطول يجعل الفروع تعمل على بيانات بائتة نصف يوم.
  static const Duration defaultInterval = Duration(minutes: 15);

  /// هامش أمان يُطرح من علامة الماء عند كل طلب.
  ///
  /// سباقُ الكتابة أثناء التصدير محسوم بترتيب القراءتين في `DataExporter`، فلا
  /// يحتاج هامشًا. الباقي هو ساعةُ جهازٍ تُضبط إلى الوراء (مزامنة وقت، تبديل
  /// منطقة): سجلٌ يُكتب حينها بختم أقدم من العلامة يسقط إلى الأبد.
  ///
  /// ودقيقة واحدة تكفي: كلّ ثانية هنا بياناتٌ تُعاد في كل دورة بلا داعٍ.
  static const Duration overlap = Duration(minutes: 1);

  /// علامة الماء التي تُطلب بها الحمولة التالية. صفر يبقى صفرًا — أي كاملة.
  static int watermark(int stamp) =>
      stamp <= 0 ? 0 : (stamp - overlap.inMilliseconds).clamp(1, stamp);

  Future<Map<String, dynamic>> _read() => SettingsRepo(db).read(settingsKey);

  Future<void> _write(Map<String, dynamic> map) => SettingsRepo(db).write(settingsKey, map);

  /// هل وافق المدير على المزامنة التلقائية على هذا الجهاز؟
  Future<bool> isAuto() async => (await _read())['auto'] == true;

  Future<void> setAuto(bool on) async {
    final map = await _read();
    map['auto'] = on;
    await _write(map);
  }

  Future<Duration> interval() async {
    final minutes = ((await _read())['intervalMinutes'] as num?)?.toInt() ?? 0;
    return minutes >= 1 ? Duration(minutes: minutes) : defaultInterval;
  }

  Future<void> setInterval(Duration d) async {
    final map = await _read();
    map['intervalMinutes'] = d.inMinutes.clamp(1, 24 * 60);
    await _write(map);
  }

  Future<DateTime?> lastSyncAt() async =>
      DateTime.tryParse('${(await _read())['lastAt'] ?? ''}');

  Future<void> markSynced() async {
    final map = await _read();
    map['lastAt'] = DateTime.now().toIso8601String();
    await _write(map);
  }

  // ───────────────────────── من نقبل منهم (ونحن مستقبِلون)

  Future<Map<String, TrustedPeer>> accepted() => _list('accepted');

  Future<void> accept(TrustedPeer peer) => _put('accepted', peer);

  // ───────────────────────── من نتصل نحن بهم

  Future<List<TrustedPeer>> peers() async => (await _list('peers')).values.toList();

  Future<void> remember(TrustedPeer peer) => _put('peers', peer);

  /// تُصفَّر علامات السحب وحدها، فتكون المزامنة القادمة كاملة من كل جهاز
  /// موثوق. الثقة والمفاتيح تبقى — المقصود إعادة جلب البيانات لا قطع العلاقة.
  Future<void> resetPullWatermarks() async {
    final map = await _read();
    final bag = map['peers'];
    if (bag is! Map) return;
    for (final entry in bag.entries) {
      final v = entry.value;
      if (v is Map) v['pulledUpTo'] = 0;
    }
    await _write(map);
  }

  /// يُنسى الجهاز من الجهتين: نسيان نصف العلاقة يترك بابًا مفتوحًا بلا واجهة
  /// تعرضه.
  Future<void> forget(String deviceId) async {
    final map = await _read();
    for (final bucket in ['accepted', 'peers']) {
      final m = map[bucket];
      if (m is Map) m.remove(deviceId);
    }
    await _write(map);
  }

  Future<Map<String, TrustedPeer>> _list(String bucket) async {
    final raw = (await _read())[bucket];
    if (raw is! Map) return {};
    final out = <String, TrustedPeer>{};
    raw.forEach((k, v) {
      final peer = TrustedPeer.fromMap('$k', v);
      if (peer != null) out['$k'] = peer;
    });
    return out;
  }

  Future<void> _put(String bucket, TrustedPeer peer) async {
    final map = await _read();
    final bag = map[bucket] is Map
        ? Map<String, dynamic>.from(map[bucket] as Map)
        : <String, dynamic>{};
    bag[peer.deviceId] = peer.copyWith(at: DateTime.now()).toMap();
    map[bucket] = bag;
    await _write(map);
  }

  /// نسخة نصية للسجل — بلا مفاتيح، فالسجل يُقرأ ويُصدَّر.
  static String describe(Iterable<TrustedPeer> peers) => jsonEncode([
        for (final p in peers) {'device': p.deviceId, 'name': p.name, 'host': p.host},
      ]);
}
