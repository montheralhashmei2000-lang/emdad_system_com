import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/security/device_activation.dart';
import '../db/app_database.dart';
import '../migration/data_export.dart';
import '../migration/web_import.dart';
import '../repos/audit_repo.dart';
import 'sync_crypto.dart';
import 'sync_marks.dart';
import 'sync_trust.dart';

/// مزامنة الأجهزة عبر الشبكة المحلية — بديل `lan-sync.js` في نسخة الويب،
/// لكن بلا إنترنت ولا خادم خارجي: جهاز يعمل **مستقبِلًا** فيفتح منفذًا على
/// الشبكة، وبقية الأجهزة ترسل إليه بياناتها أو تسحب منه.
///
/// الأمان (انظر [SyncSession]): المستقبِل يعرض رمز اقتران من ٦ أرقام، ولا يُقبل
/// أي طلب بيانات بلا توقيع مشتقّ منه، والحمولة كلها مشفَّرة. المنفذ يُغلق وحده
/// بانتهاء الجلسة، وتُغلق الجلسة فورًا بعد [maxAuthFailures] محاولة فاشلة.
///
/// قواعد الدمج (انظر [SyncMarks]):
/// • كل سجل له معرّف ثابت، والدمج يكتب فوق السجل بمعرّفه (لا تكرار).
/// • عند اختلاف النسختين **يفوز الأحدث ختمًا**، لا آخر من زامن.
/// • **الحذف ينتقل**: يرافق الحمولةَ شاهدُ حذف، فلا يعود المحذوف من الجهاز الآخر.
class SyncInfo {
  const SyncInfo({
    required this.deviceName,
    required this.records,
    required this.at,
  });

  final String deviceName;
  final int records;
  final DateTime at;

  Map<String, dynamic> toMap() => {
        'device': deviceName,
        'records': records,
        'at': at.toIso8601String(),
      };

  factory SyncInfo.fromMap(Map<String, dynamic> m) => SyncInfo(
        deviceName: (m['device'] ?? '').toString(),
        records: (m['records'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse((m['at'] ?? '').toString()) ?? DateTime.now(),
      );
}

class SyncResult {
  const SyncResult({required this.ok, this.message = '', this.records = 0, this.upTo = 0});

  final bool ok;
  final String message;
  final int records;

  /// أحدث ختم شملته هذه العملية — تُحفظ علامةَ ماءٍ للدورة التالية.
  final int upTo;
}

/// جهاز اقترنّا به: عنوانه وجلسته ومعلوماته معًا، حتى لا تُستعمل جلسة جهاز
/// مع عنوان جهاز آخر.
class SyncPeer {
  const SyncPeer({
    required this.host,
    required this.port,
    required this.session,
    required this.info,
  });

  final String host;
  final int port;
  final SyncSession session;
  final SyncInfo info;

  bool get isExpired => session.isExpired;
}

/// ناتج الاقتران بجهاز استقبال: نظير صالح، أو سبب الرفض.
class SyncPairing {
  const SyncPairing({required this.ok, this.message = '', this.peer});

  final bool ok;
  final String message;
  final SyncPeer? peer;
}

class LanSync {
  LanSync(this.db, {this.port = defaultPort, this.discoveryPort = defaultDiscoveryPort});

  final AppDatabase db;

  /// المنفذان قابلان للتغيير لكل كائن: تشغيل خادمين على الجهاز نفسه (كما في
  /// الاختبارات) يحتاج منفذين مختلفين، وإلا اقتسما الطلبات عشوائيًا.
  final int port;
  final int discoveryPort;

  static const int defaultPort = 8787;

  /// منفذ البث للاكتشاف التلقائي: المستقبِل يردّ على من ينادي.
  static const int defaultDiscoveryPort = 8788;
  static const String _hello = 'IMDAD-SYNC-WHO';

  /// عدد محاولات التوقيع الفاشلة قبل إغلاق الجلسة — يمنع تخمين الرمز.
  static const int maxAuthFailures = 5;

  /// مهلة الاتصال. الشبكة المحلية تردّ في أجزاء الثانية، أما فرعٌ في مدينة
  /// أخرى خلف VPN على وصلة جوال فقد يحتاج ثوانيَ — ومهلةٌ قصيرة تجعله يبدو
  /// «خارج الشبكة» وهو متصل.
  static const Duration wanTimeout = Duration(seconds: 20);

  HttpServer? _server;
  RawDatagramSocket? _beacon;
  SyncSession? _session;
  Timer? _expiry;

  /// استقبال بلا رمز اقتران: لا يُقبل إلا جهاز موثوق سلفًا. وضع المزامنة
  /// التلقائية — المنفذ مفتوح على الدوام، فلا يصحّ أن يبقى معه رمزٌ من ستة
  /// أرقام صالحًا طوال اليوم.
  bool _trustedOnly = false;
  bool get isTrustedOnly => _trustedOnly;

  /// فرق ساعة كل جهاز مستقبِل عن ساعتنا، بالمللي ثانية، كما أعلنه في ترحيبه.
  final Map<String, int> _clockOffset = {};

  /// الفرق المعروف لهذا العنوان — صفر إن لم نسأله بعد.
  int clockOffsetFor(String host) => _clockOffset[host] ?? 0;
  final Set<String> _seenNonces = {};
  int _authFailures = 0;

  bool get isReceiving => _server != null;
  String get deviceName => Platform.localHostname;

  /// معرّف هذا الجهاز الثابت — نفس معرّف بطاقة التفعيل.
  ///
  /// اسم الجهاز لا يصلح هوية: يتكرر بين أجهزة، ويتغيّر بتغيير اسم الحاسب.
  /// والمفتاح الدائم معلَّق على هذا المعرّف، فلا بد أن يكون ثابتًا مميّزًا.
  Future<String> deviceId() async => _deviceId ??= await DeviceActivation(db).deviceId();
  String? _deviceId;

  /// الجلسة الجارية على الجهاز المستقبِل (منها رمز الاقتران المعروض للمشغّل).
  SyncSession? get session => _session;

  /// عناوين هذا الجهاز على الشبكة المحلية، لعرضها على الأجهزة الأخرى.
  static Future<List<String>> localAddresses() async {
    final out = <String>[];
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) out.add(addr.address);
      }
    }
    return out;
  }

  // ───────────────────────── وضع الاستقبال

  /// يبدأ الاستقبال: يفتح المنفذ، ويولّد رمز اقتران جديدًا، ويردّ على الاكتشاف.
  /// [trustedOnly] يفتح المنفذ بلا رمز اقتران ولا مهلة: لا يُقبل إلا جهاز
  /// يحمل مفتاحًا دائمًا سبق أن مُنح باقتران يدوي. هذا وضع المزامنة التلقائية.
  Future<String> startReceiving({
    void Function(String message)? onEvent,
    Duration ttl = SyncSession.defaultTtl,
    bool trustedOnly = false,
  }) async {
    if (_server != null) return (await localAddresses()).join('، ');

    _trustedOnly = trustedOnly;
    final session = trustedOnly ? null : SyncSession.create(ttl: ttl);
    _session = session;
    _seenNonces.clear();
    _authFailures = 0;

    // بلا مشاركة المنفذ: خادمان على منفذ واحد يقتسمان الطلبات عشوائيًا،
    // فمن الأصح أن يظهر «المنفذ مشغول» خطأً صريحًا.
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    unawaited(_serve(server, onEvent));
    await _startBeacon();

    // المنفذ لا يبقى مفتوحًا إلى الأبد: ينتهي بانتهاء عمر الجلسة. أما استقبال
    // الموثوقين فلا مهلة له — ليس فيه سرّ قصير يُخمَّن حتى يُسابَق بالوقت.
    if (session != null) {
      _expiry = Timer(ttl, () async {
        onEvent?.call('انتهت مدة الجلسة — أُغلق الاستقبال');
        await stopReceiving();
      });
    }

    final addresses = await localAddresses();
    onEvent?.call(session == null
        ? 'استقبال تلقائي على ${addresses.join('، ')}:$port — للأجهزة الموثوقة وحدها'
        : 'جاهز للاستقبال على ${addresses.join('، ')}:$port — رمز الاقتران ${session.code}');
    return addresses.join('، ');
  }

  Future<void> _serve(HttpServer server, void Function(String)? onEvent) async {
    await for (final request in server) {
      try {
        final path = request.uri.path;
        final method = request.method;

        // الترحيب وحده مفتوح: يعطي اسم الجهاز ومعرّفه والملح (وليس سرًّا)،
        // بلا أي بيانات. المعرّف هنا لا لهوية يُوثق بها بل ليعرف الجهاز الآخر
        // أنه بلغ الجهاز الذي يقصده قبل أن يوقّع بمفتاحه الدائم.
        if (method == 'GET' && path == '/hello') {
          final s = _session;
          _plainJson(request, {
            'app': 'imdad-sync',
            'v': 2,
            'device': deviceName,
            'id': await deviceId(),
            'salt': s?.saltB64 ?? '',
            'needsCode': true,
            // ساعة هذا الجهاز — يضبط عليها الطرف الآخر أختامه فلا يُرفض طلبه
            // لانحراف ساعته. ليست سرًّا ولا تُصدَّق وحدها: التوقيع هو الحاكم.
            'now': DateTime.now().millisecondsSinceEpoch,
          });
          continue;
        }

        final candidates = await _sessionsFor(request);
        if (candidates.isEmpty) {
          await _reject(
            request,
            _trustedOnly ? 'جهاز غير موثوق' : 'انتهت مدة جلسة المزامنة',
            HttpStatus.forbidden,
          );
          continue;
        }

        final body = await _readBody(request);
        final auth = _authenticate(request, method, path, body, candidates);
        if (auth.session == null) {
          await _onAuthFailure(request, auth.error, onEvent);
          continue;
        }
        final session = auth.session!;
        _authFailures = 0;

        switch ('$method $path') {
          // منح ثقة دائمة لجهاز اقترن الآن برمز صحيح. لا يُقبل إلا على جلسة
          // الرمز نفسها: لو قُبل على جلسة ثقة قائمة لاستطاع جهاز موثوق أن
          // يبدّل مفتاحه متى شاء، وصار المفتاح الأول بلا معنى.
          case 'POST /trust':
            if (!auth.paired) {
              await _reject(request, 'المنح يحتاج اقترانًا برمز', HttpStatus.forbidden);
              break;
            }
            final ask = await compute(_openTask, (session, body));
            final peerId = '${ask['device'] ?? ''}';
            if (peerId.isEmpty) {
              await _reject(request, 'طلب ثقة بلا معرّف جهاز', HttpStatus.badRequest);
              break;
            }
            await SyncTrust(db).accept(TrustedPeer(
              deviceId: peerId,
              key: session.trustKeyFor(peerId),
              name: '${ask['name'] ?? ''}',
              host: request.connectionInfo?.remoteAddress.address ?? '',
            ));
            await AuditRepo(db).log(
              action: 'sync.trust',
              entityType: 'مزامنة',
              summary: 'مُنح الجهاز $peerId ثقة دائمة للمزامنة',
              details: {'device': peerId, 'risk': 'sensitive'},
            );
            await _sealed(request, session, {
              'ok': true,
              'device': await deviceId(),
              'name': deviceName,
            });
            onEvent?.call('مُنح الجهاز $peerId ثقة دائمة — يزامن بعد اليوم بلا رمز');
            break;

          case 'GET /info':
            final map = await DataExporter(db).toMap();
            final records = map.entries
                .where((e) => e.value is List)
                .fold<int>(0, (s, e) => s + (e.value as List).length);
            await _sealed(request, session, SyncInfo(
              deviceName: deviceName,
              records: records,
              at: DateTime.now(),
            ).toMap());
            break;

          case 'GET /export':
            // إرسال بيانات هذا الجهاز إلى الجهاز الطالب (سحب).
            final includeUsers = request.uri.queryParameters['users'] == '1';
            // غياب `since` ⇒ نسخة كاملة، كما يطلبها جهاز جديد أو نسخة احتياطية.
            final since = int.tryParse(request.uri.queryParameters['since'] ?? '');
            final map = await DataExporter(db).toMap(
              includeUsers: includeUsers,
              since: (since ?? 0) > 0 ? since : null,
            );
            await _sealed(request, session, map);
            onEvent?.call('أرسل نسخة إلى ${request.connectionInfo?.remoteAddress.address}');
            break;

          case 'POST /import':
            // استقبال بيانات جهاز آخر ودمجها هنا.
            final data = await compute(_openTask, (session, body));
            final result = await WebImporter(db).importJson(data);
            await AuditRepo(db).log(
              action: 'sync.receive',
              entityType: 'مزامنة',
              summary: 'استقبال ${result.total} سجلًا من '
                  '${request.connectionInfo?.remoteAddress.address ?? 'جهاز'}',
              details: {'records': result.total},
            );
            await _sealed(request, session, {'ok': true, 'records': result.total});
            onEvent?.call('استُقبل ${result.total} سجلًا من '
                '${request.connectionInfo?.remoteAddress.address}');
            break;

          default:
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
        }
      } catch (e) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(jsonEncode({'ok': false, 'error': '$e'}));
          await request.response.close();
        } catch (_) {}
        onEvent?.call('خطأ في طلب وارد: $e');
      }
    }
  }

  /// المفاتيح التي قد يكون الطلب موقَّعًا بأحدها.
  ///
  /// **كلاهما لا أحدهما**: جهاز موثوق سلفًا قد يعود ليقترن برمز جديد (بعد
  /// إعادة تثبيت مثلًا)، فيوقّع بمفتاح الرمز لا بمفتاح الثقة. لو اكتفينا
  /// بمفتاح الثقة لأنه أعرف بالجهاز لرُفض كل اقتران يدوي بعد الأول.
  Future<List<({SyncSession session, bool paired})>> _sessionsFor(HttpRequest request) async {
    final out = <({SyncSession session, bool paired})>[];
    final peerId = request.headers.value(SyncSession.headerDevice) ?? '';
    if (peerId.isNotEmpty) {
      final peer = (await SyncTrust(db).accepted())[peerId];
      if (peer != null) out.add((session: SyncSession.fromKey(peer.key), paired: false));
    }
    final s = _session;
    if (s != null && !s.isExpired) out.add((session: s, paired: true));
    return out;
  }

  /// يجرّب المفاتيح المرشَّحة، ثم يستهلك الـnonce مرة واحدة عند النجاح.
  ///
  /// التجربة تجري على مجموعة nonce مؤقتة عن قصد: لو سُجّل الـnonce في السجل
  /// الدائم عند أول مفتاح فاشل لردّ المفتاح الثاني الطلبَ «مكرَّرًا» وهو أول
  /// مرة — فيستحيل أن ينجح طلب صحيح كلما كان للجهاز مفتاحان.
  ({SyncSession? session, bool paired, String error}) _authenticate(
    HttpRequest request,
    String method,
    String path,
    List<int> body,
    List<({SyncSession session, bool paired})> candidates,
  ) {
    final ts = request.headers.value(SyncSession.headerTs);
    final nonce = request.headers.value(SyncSession.headerNonce);
    final mac = request.headers.value(SyncSession.headerMac);

    var error = 'توقيع غير مطابق';
    for (final c in candidates) {
      final e = c.session.verify(
        method: method,
        path: path,
        ts: ts,
        nonce: nonce,
        mac: mac,
        body: body,
        seenNonces: <String>{},
      );
      if (e == null) {
        if (!_seenNonces.add(nonce!)) {
          return (session: null, paired: false, error: 'طلب مكرر (إعادة إرسال)');
        }
        return (session: c.session, paired: c.paired, error: '');
      }
      error = e;
    }
    return (session: null, paired: false, error: error);
  }

  Future<List<int>> _readBody(HttpRequest request) async {
    final chunks = <int>[];
    await for (final chunk in request) {
      chunks.addAll(chunk);
    }
    return chunks;
  }

  /// محاولة فاشلة: تُسجَّل، وبعد [maxAuthFailures] تُغلق الجلسة كلها.
  Future<void> _onAuthFailure(
    HttpRequest request,
    String error,
    void Function(String)? onEvent,
  ) async {
    _authFailures++;
    final from = request.connectionInfo?.remoteAddress.address ?? 'جهاز';
    onEvent?.call('رُفض طلب من $from — $error');
    await AuditRepo(db).log(
      action: 'sync.reject',
      entityType: 'مزامنة',
      summary: 'رُفض طلب مزامنة من $from — $error',
      details: {'host': from, 'reason': error, 'risk': 'sensitive'},
    );
    await _reject(request, error, HttpStatus.unauthorized);
    // الإغلاق حارسٌ لرمز الأرقام الستة من التخمين. في استقبال الموثوقين لا
    // رمز يُخمَّن — والإغلاق حينها يصير سلاحًا بيد المهاجم: خمس محاولات فاشلة
    // تكفي لتعطيل مزامنة الوحدة كلها.
    if (_trustedOnly) return;
    if (_authFailures >= maxAuthFailures) {
      onEvent?.call('تجاوز عدد المحاولات الفاشلة — أُغلق الاستقبال');
      // بلا انتظار: النداء يأتي من داخل حلقة الطلبات التي يغلقها الإيقاف نفسه.
      unawaited(stopReceiving());
    }
  }

  Future<void> _reject(HttpRequest request, String error, int status) async {
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': false, 'error': error}));
      await request.response.close();
    } catch (_) {}
  }

  void _plainJson(HttpRequest request, Map<String, dynamic> body) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    request.response.close();
  }

  /// ردّ مشفَّر — لا يقرؤه إلا حامل رمز الاقتران.
  Future<void> _sealed(
    HttpRequest request,
    SyncSession session,
    Map<String, dynamic> body,
  ) async {
    final sealed = await compute(_sealTask, (session, body));
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..add(sealed);
    await request.response.close();
  }

  /// يردّ على نداءات الاكتشاف فتظهر أجهزة الاستقبال تلقائيًا في القائمة.
  Future<void> _startBeacon() async {
    if (_beacon != null) return;
    await deviceId(); // يُحمَّل قبل فتح المنفذ ليُعلن في كل ردّ اكتشاف

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
    socket.broadcastEnabled = true;
    _beacon = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null) return;
      if (utf8.decode(packet.data, allowMalformed: true).trim() != _hello) return;
      // الردّ متزامن داخل المستمع، فالمعرّف يُقرأ مرة عند فتح المنفذ لا عند
      // كل نداء.
      socket.send(
        utf8.encode(jsonEncode({'device': deviceName, 'id': _deviceId ?? '', 'port': port})),
        packet.address,
        packet.port,
      );
    });
  }

  Future<void> stopReceiving() async {
    _expiry?.cancel();
    _expiry = null;
    _trustedOnly = false;
    // الحالة تُصفَّر أولًا ثم يُغلق المنفذ: إغلاق الخادم لا يكتمل ما دامت حلقة
    // الطلبات جارية، فلو انتظرناه قبل التصفير لبقي الجهاز «مستقبِلًا» ظاهريًا.
    final server = _server;
    _server = null;
    _session = null;
    _seenNonces.clear();
    _beacon?.close();
    _beacon = null;
    await server?.close(force: true);
  }

  // ───────────────────────── وضع الإرسال/السحب

  /// يبحث عن أجهزة الاستقبال على الشبكة خلال مهلة قصيرة.
  Future<List<({String address, String device, String id})>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = <String, ({String device, String id})>{};
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null) return;
      try {
        final map = jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>;
        found[packet.address.address] = (
          device: '${map['device'] ?? ''}',
          id: '${map['id'] ?? ''}',
        );
      } catch (_) {}
    });

    socket.send(utf8.encode(_hello), InternetAddress('255.255.255.255'), discoveryPort);
    await Future<void>.delayed(timeout);
    socket.close();
    return [
      for (final e in found.entries)
        (address: e.key, device: e.value.device, id: e.value.id),
    ];
  }

  /// بطاقة الترحيب المفتوحة لجهاز على الشبكة — بها يُعرف معرّفه قبل أي توقيع.
  Future<({String device, String id, String salt})?> hello(String host, {int? port}) async {
    final client = HttpClient()..connectionTimeout = wanTimeout;
    try {
      final req = await client.getUrl(Uri.parse('http://$host:${port ?? this.port}/hello'));
      final res = await req.close();
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode != HttpStatus.ok) return null;
      final map = jsonDecode(body) as Map<String, dynamic>;
      if (map['app'] != 'imdad-sync') return null;
      _noteClock(host, map);
      return (
        device: '${map['device'] ?? ''}',
        id: '${map['id'] ?? ''}',
        salt: '${map['salt'] ?? ''}',
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// الاقتران بجهاز استقبال: يجلب الملح من `/hello`، ثم يثبت صحة الرمز بطلب
  /// `/info` موقَّع. رمز خاطئ ⇒ يردّ الخادم بالرفض ولا تُبنى جلسة.
  Future<SyncPairing> pair(String host, String code, {int? port}) async {
    final peerPort = port ?? this.port;
    final digits = code.trim();
    if (digits.length != 6 || int.tryParse(digits) == null) {
      return const SyncPairing(ok: false, message: 'رمز الاقتران ستة أرقام');
    }
    try {
      final client = HttpClient()..connectionTimeout = wanTimeout;
      final req = await client.getUrl(Uri.parse('http://$host:$peerPort/hello'));
      final res = await req.close();
      final body = await utf8.decoder.bind(res).join();
      client.close();
      if (res.statusCode != HttpStatus.ok) {
        return SyncPairing(ok: false, message: 'الجهاز ردّ بالحالة ${res.statusCode}');
      }
      final map = jsonDecode(body) as Map<String, dynamic>;
      final salt = (map['salt'] ?? '').toString();
      if (salt.isEmpty) {
        return const SyncPairing(ok: false, message: 'الجهاز لا يستقبل الآن');
      }
      // يُقرأ قبل أول طلب موقَّع، وإلا رُفض الاقتران نفسه لانحراف الساعة.
      _noteClock(host, map);
      final session = SyncSession.fromCode(digits, salt);
      final info = await probe(host, peerPort, session);
      if (info == null) {
        return const SyncPairing(ok: false, message: 'رمز الاقتران غير صحيح');
      }
      return SyncPairing(
        ok: true,
        message: 'تم الاقتران',
        peer: SyncPeer(host: host, port: peerPort, session: session, info: info),
      );
    } catch (e) {
      return SyncPairing(ok: false, message: 'تعذّر الاتصال بـ $host — $e');
    }
  }

  /// يطلب من الجهاز المقترن ثقةً دائمة، ويحفظ طرفَي العلاقة.
  ///
  /// بعدها يزامن الجهازان بلا رمز ولا مشغّل: هذه هي الخطوة الوحيدة التي تحتاج
  /// إنسانًا في عمر الاقتران كله.
  Future<TrustedPeer?> trust(SyncPeer peer) async {
    final me = await deviceId();
    final sealed = await compute(_sealTask, (peer.session, {'device': me, 'name': deviceName}));
    final res = await _send(peer.host, peer.port, peer.session, 'POST', '/trust', body: sealed);
    if (res == null || res['ok'] != true) return null;
    final theirId = '${res['device'] ?? ''}';
    if (theirId.isEmpty) return null;
    final remembered = TrustedPeer(
      deviceId: theirId,
      key: peer.session.trustKeyFor(me),
      name: '${res['name'] ?? peer.info.deviceName}',
      host: peer.host,
    );
    await SyncTrust(db).remember(remembered);
    return remembered;
  }

  /// دورة مزامنة كاملة مع الأجهزة الموثوقة — بلا رمز ولا ضغطة زر.
  ///
  /// تسحب أولًا ثم ترسل: السحب يجلب ما تغيّر هناك، والإرسال يبلّغ ما تغيّر هنا،
  /// والدمج في الحالين يرجّح الأحدث ختمًا فلا يهم الترتيب في النتيجة النهائية.
  ///
  /// والحسابات مشمولة دائمًا: المزامنة التلقائية وُضعت أصلًا ليصل حساب المستخدم
  /// إلى جهاز الفرع بلا أن يلمسه أحد. استثناؤها يُفرغ الميزة من معناها.
  Future<SyncResult> autoSync({void Function(String message)? onEvent}) async {
    final store = SyncTrust(db);
    final peers = await store.peers();
    if (peers.isEmpty) {
      return const SyncResult(ok: false, message: 'لا يوجد جهاز موثوق — اقترن مرة واحدة يدويًا');
    }

    var records = 0;
    var reached = 0;
    final problems = <String>[];
    for (final p in peers) {
      final label = p.name.isEmpty ? p.deviceId : p.name;
      final host = await _locate(p);
      if (host == null) {
        problems.add('$label خارج الشبكة');
        continue;
      }
      final peer = SyncPeer(
        host: host,
        port: port,
        session: SyncSession.fromKey(p.key),
        info: SyncInfo(deviceName: p.name, records: 0, at: DateTime.now()),
      );
      // أول دورة مع جهاز (علامة ماء صفر) كاملة بالضرورة — بها يبلغ الجهاز
      // الجديد حالةَ الوحدة. وما بعدها تفاضليّ: ما تغيّر وحده يعبر الشبكة.
      final pulled = await pull(peer, includeUsers: true, since: SyncTrust.watermark(p.pulledUpTo));
      final pushed = await push(peer, includeUsers: true, since: SyncTrust.watermark(p.pushedUpTo));
      if (!pulled.ok || !pushed.ok) {
        problems.add('$label: ${pulled.ok ? pushed.message : pulled.message}');
        continue;
      }
      // العلامتان تُحفظان معًا بعد نجاح الطرفين: حفظ علامة عمليةٍ فشلت أختُها
      // يعني تخطّي تغييرات لن تُطلب مرة أخرى أبدًا.
      await store.remember(p.copyWith(
        host: host,
        pulledUpTo: pulled.upTo > p.pulledUpTo ? pulled.upTo : p.pulledUpTo,
        pushedUpTo: pushed.upTo > p.pushedUpTo ? pushed.upTo : p.pushedUpTo,
      ));
      reached++;
      records += pulled.records + pushed.records;
      onEvent?.call('زامن $label — سحب ${pulled.records} وأرسل ${pushed.records}');
    }

    if (reached == 0) {
      return SyncResult(ok: false, message: problems.join('، '));
    }
    await store.markSynced();
    return SyncResult(
      ok: true,
      records: records,
      message: 'زُومن $reached جهازًا ($records سجلًا)'
          '${problems.isEmpty ? '' : ' — تعذّر: ${problems.join('، ')}'}',
    );
  }

  /// أين هذا الجهاز الموثوق الآن؟ عنوانه المحفوظ أولًا، فإن تبدّل فبالبحث.
  ///
  /// عناوين الشبكة المحلية تُوزَّع بالـDHCP وتتبدّل بين يوم وآخر، والثقة معلّقة
  /// على معرّف الجهاز لا على عنوانه — فالعنوان يُتحقق منه ولا يُوثق به.
  Future<String?> _locate(TrustedPeer peer) async {
    if (peer.host.isNotEmpty) {
      final card = await hello(peer.host);
      if (card != null && card.id == peer.deviceId) return peer.host;
    }
    for (final d in await discover()) {
      if (d.id != peer.deviceId) continue;
      // الترحيب هنا ليس تكرارًا: منه تُقرأ ساعة الجهاز قبل أول طلب موقَّع.
      if (await hello(d.address) == null) continue;
      await SyncTrust(db).remember(peer.copyWith(host: d.address));
      return d.address;
    }
    return null;
  }

  /// يسجّل فرق ساعة جهازٍ من ترحيبه.
  ///
  /// نسخة قديمة لا تُعلن ساعتها ⇒ صفر، أي سلوك ما قبل هذا التغيير: الأجهزة
  /// المتوافقة تتفاهم، والقديمة لا تنكسر.
  void _noteClock(String host, Map<String, dynamic> hello) {
    final theirs = (hello['now'] as num?)?.toInt();
    if (theirs == null) return;
    _clockOffset[host] = theirs - DateTime.now().millisecondsSinceEpoch;
  }

  Future<SyncInfo?> probe(String host, int port, SyncSession session) async {
    try {
      final map = await _send(host, port, session, 'GET', '/info');
      return map == null ? null : SyncInfo.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  /// يرسل بيانات هذا الجهاز إلى جهاز الاستقبال.
  /// [since] > 0 ⇒ لا يُرسل إلا ما تغيّر بعده (مزامنة تفاضلية).
  Future<SyncResult> push(SyncPeer peer, {bool includeUsers = false, int since = 0}) async {
    final host = peer.host;
    final session = peer.session;
    try {
      final map = await DataExporter(db).toMap(
        includeUsers: includeUsers,
        since: since > 0 ? since : null,
      );
      final upTo = ((map['meta'] as Map)['maxStamp'] as num?)?.toInt() ?? 0;
      final payload = await compute(_sealTask, (session, map));
      final decoded = await _send(host, peer.port, session, 'POST', '/import', body: payload);
      if (decoded == null) {
        return const SyncResult(ok: false, message: 'رفض الجهاز الطلب — أعد الاقتران');
      }
      final records = (decoded['records'] as num?)?.toInt() ?? 0;
      await AuditRepo(db).log(
        action: 'sync.push',
        entityType: 'مزامنة',
        summary: 'إرسال $records سجلًا إلى $host',
        details: {'host': host, 'records': records},
      );
      return SyncResult(
        ok: true,
        records: records,
        upTo: upTo,
        message: 'أُرسل $records سجلًا',
      );
    } on SyncCryptoError catch (e) {
      return SyncResult(ok: false, message: e.message);
    } catch (e) {
      return SyncResult(ok: false, message: 'تعذّر الاتصال بـ $host — $e');
    }
  }

  /// يسحب بيانات جهاز الاستقبال ويدمجها هنا.
  /// [since] > 0 ⇒ لا يُطلب إلا ما تغيّر بعده على الجهاز الآخر.
  Future<SyncResult> pull(SyncPeer peer, {bool includeUsers = false, int since = 0}) async {
    final host = peer.host;
    try {
      final data = await _send(
        host,
        peer.port,
        peer.session,
        'GET',
        '/export',
        query: {
          'users': includeUsers ? '1' : '0',
          if (since > 0) 'since': '$since',
        },
      );
      if (data == null) {
        return const SyncResult(ok: false, message: 'رفض الجهاز الطلب — أعد الاقتران');
      }
      final upTo = ((data['meta'] as Map?)?['maxStamp'] as num?)?.toInt() ?? 0;
      final result = await WebImporter(db).importJson(data);
      await AuditRepo(db).log(
        action: 'sync.pull',
        entityType: 'مزامنة',
        summary: 'سحب ${result.total} سجلًا من $host',
        details: {'host': host, 'records': result.total},
      );
      return SyncResult(
        ok: true,
        records: result.total,
        upTo: upTo,
        message: 'سُحب ${result.total} سجلًا',
      );
    } on SyncCryptoError catch (e) {
      return SyncResult(ok: false, message: e.message);
    } catch (e) {
      return SyncResult(ok: false, message: 'تعذّر الاتصال بـ $host — $e');
    }
  }

  /// طلب موقَّع إلى جهاز الاستقبال، وفكّ تشفير ردّه. `null` عند الرفض.
  Future<Map<String, dynamic>?> _send(
    String host,
    int port,
    SyncSession session,
    String method,
    String path, {
    Map<String, String> query = const {},
    List<int> body = const [],
  }) async {
    final client = HttpClient()..connectionTimeout = wanTimeout;
    try {
      final uri = Uri.parse('http://$host:$port$path').replace(
        queryParameters: query.isEmpty ? null : query,
      );
      // التوقيع على المسار وحده دون قائمة الاستعلام، كما يتحقق منه الخادم.
      final headers = {
        ...session.signHeaders(method, path, body, skewMs: clockOffsetFor(host)),
        SyncSession.headerDevice: await deviceId(),
      };
      final req = await client.openUrl(method, uri);
      headers.forEach(req.headers.set);
      if (body.isNotEmpty) {
        req.headers.contentType = ContentType.binary;
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close();
      final bytes = await _collect(res);
      if (res.statusCode != HttpStatus.ok) return null;
      return await compute(_openTask, (session, bytes));
    } finally {
      client.close();
    }
  }

  static Future<List<int>> _collect(HttpClientResponse res) async {
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    return out;
  }
}

/// التشفير وفكّه يجريان في خيط منفصل: AES في Dart الخالص يجمّد الواجهة
/// مع الحمولات الكبيرة (تصدير قاعدة كاملة).
Uint8List _sealTask((SyncSession, Map<String, dynamic>) arg) => arg.$1.sealJson(arg.$2);

Map<String, dynamic> _openTask((SyncSession, List<int>) arg) => arg.$1.openJson(arg.$2);
