import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/error_log.dart';
import '../../core/security/device_activation.dart';
import '../db/app_database.dart';
import '../migration/data_export.dart';
import '../migration/legacy_import.dart';
import '../repos/audit_repo.dart';
import 'sync_crypto.dart';
import 'sync_trust.dart';

export 'sync_models.dart';
import 'sync_models.dart';


class LanSync {
  LanSync(this.db, {this.port = defaultPort, this.discoveryPort = defaultDiscoveryPort, this.ownerPublicKey});

  final AppDatabase db;

  /// المنفذان قابلان للتغيير لكل كائن: تشغيل خادمين على الجهاز نفسه (كما في
  /// الاختبارات) يحتاج منفذين مختلفين، وإلا اقتسما الطلبات عشوائيًا.
  final int port;
  final int discoveryPort;

  /// المفتاح العام للتحقق من توقيع المالك عند الاستيراد (للاختبار؛ الافتراضي المضمَّن).
  final String? ownerPublicKey;

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

  /// مهلة بطاقة الترحيب على الشبكة المحلية.
  ///
  /// `/hello` طلبٌ لا حمولة له، وغرضه أن يُعرف: هل الجهاز على هذا العنوان
  /// الآن؟ وجهازُ الشبكة المحلية يردّ في أجزاء الثانية أو لا يردّ.
  static const Duration helloTimeout = Duration(seconds: 4);

  /// مهلة ترحيب العنوان **المحفوظ** في سطر الثقة.
  ///
  /// أطولُ من [helloTimeout] لأن هذا العنوان قد يكون لفرعٍ بعيد كُتب يدويًا
  /// على شبكةٍ افتراضية (VPN)، وأقصرُ كثيرًا من [wanTimeout] لأن العنوان
  /// المحفوظ غالبًا بائتٌ (DHCP يبدّله): عشرون ثانيةً لكل قرينٍ قبل الالتفات
  /// إلى الاكتشاف تجعل «زامن الآن» يبدو معلَّقًا ثم يفشل، والجهاز على الشبكة
  /// نفسها. وما فات هنا يُدركه الاكتشافُ بعده.
  static const Duration savedHostTimeout = Duration(seconds: 8);

  HttpServer? _server;
  RawDatagramSocket? _beacon;
  PairingOffer? _offer;
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
  final NonceCache _seenNonces = NonceCache();
  int _authFailures = 0;

  /// خمدُ شواهد الرفض المتكررة (انظر [_onAuthFailure]).
  final RejectLog _rejectLog = RejectLog();

  /// ساعة الخمد — تُبدَّل في الاختبار لتجاوز النافذة بلا انتظارٍ حقيقي.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;
  DateTime _now() => clock();

  bool get isReceiving => _server != null;
  String get deviceName => Platform.localHostname;

  /// معرّف هذا الجهاز الثابت — نفس معرّف بطاقة التفعيل.
  ///
  /// اسم الجهاز لا يصلح هوية: يتكرر بين أجهزة، ويتغيّر بتغيير اسم الحاسب.
  /// والمفتاح الدائم معلَّق على هذا المعرّف، فلا بد أن يكون ثابتًا مميّزًا.
  Future<String> deviceId() async => _deviceId ??= await DeviceActivation(db).deviceId();
  String? _deviceId;

  /// الجلسة الجارية على الجهاز المستقبِل (منها رمز الاقتران المعروض للمشغّل).
  PairingOffer? get session => _offer;

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
    final session = trustedOnly ? null : await PairingOffer.create(ttl: ttl);
    _offer = session;
    _seenNonces.clear();
    _rejectLog.clear();
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
        : 'جاهز للاستقبال على ${addresses.join('، ')}:$port — رمز الاقتران ${PairingCode.format(session.code)}');
    if (session != null) {
      await AuditRepo(db).log(
        action: 'sync.pair.started',
        entityType: 'مزامنة',
        summary: 'بدء استقبال اقتران — الرمز صالح ${ttl.inMinutes} دقائق',
        details: {'role': 'receiver', 'port': port},
      );
    }
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
          final s = _offer;
          _plainJson(request, {
            'app': 'imdad-sync',
            // 3: الاقتران بمفتاح ECDH مؤقت مع رمز من ٨ أحرف. الإصدار 2 لا يقترن
            // بهذا الإصدار (والمقترنون سلفًا بمفاتيح دائمة لا يتأثرون).
            'v': 3,
            'device': deviceName,
            'id': await deviceId(),
            'salt': s?.saltB64 ?? '',
            'pub': s?.pubB64 ?? '',
            'needsCode': true,
            // ساعة هذا الجهاز — يضبط عليها الطرف الآخر أختامه فلا يُرفض طلبه
            // لانحراف ساعته. ليست سرًّا ولا تُصدَّق وحدها: التوقيع هو الحاكم.
            'now': DateTime.now().millisecondsSinceEpoch,
          });
          continue;
        }

        final candidates = await _sessionsFor(request);
        if (candidates.isEmpty) {
          await _rejectNoSession(request, onEvent);
          continue;
        }

        // سقف الجسم حسب المسار: الاستيراد وحده يحمل حمولةً كبيرة، وما سواه (ثقة،
        // معلومات، تصدير) لا جسم له يُذكر. فلا يُفتح 128 م.ب لمن لم يُثبت هويته.
        final cap = path == '/import' && method == 'POST' ? maxBodyBytes : maxSmallBodyBytes;
        if (request.contentLength > cap) {
          await _rejectTooLarge(request);
          continue;
        }

        // التوقيع قبل الجسم: بصمة الجسم معلنةٌ وداخلةٌ في التوقيع، فيُتحقَّق منه ثم
        // يُقرأ الجسم. الاستيراد يشترطها (الجسم الكبير لا يُقرأ لغير موقِّعٍ)؛ وما
        // سواه يقبل الطلب القديم بلا بصمة لأن سقفه صغير.
        final claimed = request.headers.value(SyncSession.headerBodyDigest);
        if (claimed == null && cap == maxBodyBytes) {
          await _onAuthFailure(request, 'جهاز بإصدار قديم — حدّث التطبيق عليه لإرسال بيانات', onEvent,
              reason: 'no_body_digest');
          continue;
        }
        var auth = claimed == null ? null : _authenticate(request, method, path, null, claimed, candidates);
        if (auth != null && auth.session == null) {
          await _onAuthFailure(request, auth.error, onEvent);
          continue;
        }
        final body = await _readBody(request, cap);
        if (body == null) {
          await _rejectTooLarge(request);
          continue;
        }
        if (auth == null) {
          auth = _authenticate(request, method, path, body, null, candidates);
          if (auth.session == null) {
            await _onAuthFailure(request, auth.error, onEvent);
            continue;
          }
        } else if (!SyncSession.digestMatches(body, claimed!)) {
          await _onAuthFailure(request, 'الجسم لا يطابق البصمة الموقَّعة', onEvent);
          continue;
        }
        final session = auth.session!;
        _authFailures = 0;
        if (auth.paired) await _announcePairing(request, session);

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
            // المعرّف في الجسم لا بدّ أن يطابق ترويسة الطلب. كلاهما من العميل
            // نفسه فلا يختلفان في عميلٍ سليم أبدًا، وكان الجسم وحده هو المعتبر:
            // فمن يملك رمز الاقتران يضع فيه معرّف **جهاز الإدارة**، فيُكتب فوق
            // سطر ثقته مفتاحٌ يعرفه المهاجم (`trustKeyFor(peerId)`) — فينتحله
            // انتحالًا كاملًا، ويفقد جهاز الإدارة الحقيقي مفتاحه فتتوقف مزامنته
            // بصمت لأن توقيعه لم يعد يُقبل.
            final headerId = request.headers.value(SyncSession.headerDevice) ?? '';
            if (headerId != peerId) {
              await _onAuthFailure(request, 'معرّف الجهاز في الطلب لا يطابق ترويسته', onEvent,
                  reason: 'device_id_mismatch');
              break;
            }
            // **ولا يُكتب فوق مفتاح قرينٍ قائم.** مطابقةُ الترويسة بالجسم أعلاه
            // تمنع ادّعاءً متناقضًا لا أكثر: المعرّف يُعلنه العميل عن نفسه في
            // الموضعين، فمن يملك رمز الاقتران يضع معرّف جهاز الإدارة فيهما معًا.
            // فالحارس الفاعل هو هذا: سطرُ قرينٍ موثوقٍ بمفتاحٍ مختلف لا يُستبدل
            // بطلبٍ من الشبكة، بل يُنسى أولًا من الجهاز نفسه («نسيان الجهاز» في
            // شاشة المزامنة) — فعلٌ محليٌّ صريح لا يُنتزع بالرمز وحده.
            //
            // وإعادةُ الاقتران المشروعة لا تتعثّر: جهازٌ أُعيد تثبيته يحمل
            // معرّفًا جديدًا (القاعدة جديدة) فلا يصادم سطرًا قائمًا.
            final existing = (await SyncTrust(db).accepted())[peerId];
            final newKey = session.trustKeyFor(peerId);
            if (existing != null && !_sameKey(existing.key, newKey)) {
              await AuditRepo(db).log(
                action: 'sync.trust_rejected',
                entityType: 'مزامنة',
                summary: 'رُفض استبدال مفتاح القرين $peerId بطلبٍ من '
                    '${request.connectionInfo?.remoteAddress.address ?? 'جهاز'}',
                details: {'device': peerId, 'risk': 'sensitive'},
                risk: AuditRepo.riskHigh,
              );
              await _reject(
                request,
                'الجهاز $peerId موثوقٌ سلفًا بمفتاحٍ آخر — انسَ الجهاز على المستقبِل ثم أعد الاقتران',
                HttpStatus.conflict,
              );
              onEvent?.call('رُفض استبدال مفتاح القرين $peerId — انسَ الجهاز أولًا');
              break;
            }

            // الثقة تُكتب في الاتجاهين: `accepted` ليُقبل طلبه ونحن مستقبِلون،
            // و`peers` لنطرق بابه نحن في دورة المزامنة. المفتاح واحد مشتقٌّ من
            // جلسة الاقتران (`trustKeyFor`) فالعلاقة متكافئة بطبيعتها، ولا
            // سرَّ جديدًا يُمنح هنا. وكتابة `accepted` وحدها كانت تُقعد جهازَ
            // الإدارة عن المزامنة: قائمة `peers` عنده فارغة، فزرُّ «زامن الآن»
            // مُعطَّل واللوحة تقول «لم يُوثَّق جهاز بعد» وعلى الجهاز قرينٌ
            // موثوق. (الخلط المحذور في [SyncTrust] هو أن يصير كل من اتصل بنا
            // قرينًا؛ وهذا المسار لا يُدخل إلا من أدخل إنسانٌ رمزَه.)
            final granted = TrustedPeer(
              deviceId: peerId,
              key: newKey,
              name: '${ask['name'] ?? ''}',
              host: request.connectionInfo?.remoteAddress.address ?? '',
            );
            await SyncTrust(db).accept(granted);
            await SyncTrust(db).remember(granted);
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
            // عدٌّ بـ COUNT(*) لكل جدول — لا تصدير القاعدة كلها لاستخراج رقم.
            final records = await DataExporter(db).countRecords();
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
              includeOwnerSecrets: false,
              since: (since ?? 0) > 0 ? since : null,
            );
            await _sealed(request, session, map);
            onEvent?.call('أرسل نسخة إلى ${request.connectionInfo?.remoteAddress.address}');
            break;

          case 'POST /import':
            // استقبال بيانات جهاز آخر ودمجها هنا.
            final data = await compute(_openTask, (session, body));
            final result = await LegacyImporter(db, ownerPublicKey: ownerPublicKey).importJson(
              data,
              // لسجل التدقيق فقط: مصدر الحمولة.
              source: 'جهاز ${request.headers.value(SyncSession.headerDevice) ?? '؟'} '
                  '(${request.connectionInfo?.remoteAddress.address ?? '؟'})',
            );
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
          // لا يُرسل نصُّ الاستثناء إلى الطرف الآخر (مسارات وأسماء داخلية)؛ يبقى في السجل المحلي.
          request.response.write(jsonEncode({'ok': false, 'error': 'خطأ داخلي في الجهاز المستقبِل'}));
          await request.response.close();
        } catch (_) {
          // متوقع: الطرف الآخر أغلق الاتصال قبل أن نرد عليه بالخطأ: لا مستمع للردّ، والخطأ الأصلي معروض أعلاه.
        }
        ErrorLogger.log('sync.request', e);
        onEvent?.call('خطأ في طلب وارد: $e');
      }
    }
  }

  /// مقارنةُ مفتاحين بزمنٍ ثابت — لا يُستدلّ على المفتاح المحفوظ من زمن الردّ.
  static bool _sameKey(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
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
    // جلسة الاقتران لا تُبنى إلا إن حمل الطلب مفتاح المرسِل المؤقت. طلبٌ بلا
    // مفتاح من جهاز غير موثوق هو إصدار قديم (v2) يوقّع بالرمز وحده.
    final offer = _offer;
    if (offer != null && !offer.isExpired) {
      final epk = request.headers.value(SyncSession.headerPairKey) ?? '';
      final s = epk.isEmpty ? null : offer.sessionFor(epk);
      if (s != null) out.add((session: s, paired: true));
    }
    return out;
  }

  /// طلب لا مفتاح مرشَّحًا له. السبب يُسجَّل في التدقيق بدقة: انتهاء المدة،
  /// أو إصدار قديم، أو مفتاح اقتران معطوب.
  Future<void> _rejectNoSession(HttpRequest request, void Function(String)? onEvent) async {
    final offer = _offer;
    if (_trustedOnly || offer == null) {
      await _reject(request, 'جهاز غير موثوق', HttpStatus.forbidden);
      return;
    }
    if (offer.isExpired) {
      final from = request.connectionInfo?.remoteAddress.address ?? 'جهاز';
      await AuditRepo(db).log(
        action: 'sync.pair.failed',
        entityType: 'مزامنة',
        summary: 'فشل اقتران من $from — انتهت مدة الجلسة',
        details: {'host': from, 'reason': 'expired', 'role': 'receiver', 'risk': 'sensitive'},
      );
      await _reject(request, 'انتهت مدة جلسة المزامنة', HttpStatus.forbidden);
      return;
    }
    final epk = request.headers.value(SyncSession.headerPairKey) ?? '';
    if (epk.isEmpty) {
      await _onAuthFailure(
        request,
        'جهاز بإصدار قديم (v2) — يجب تحديث التطبيق عليه أولاً',
        onEvent,
        reason: 'v2_rejected',
      );
    } else {
      await _onAuthFailure(request, 'مفتاح اقتران غير صالح', onEvent, reason: 'bad_key');
    }
  }

  /// نجاح الاقتران يُسجَّل مرة واحدة لكل مفتاح مؤقت لا لكل طلب.
  Future<void> _announcePairing(HttpRequest request, SyncSession session) async {
    final offer = _offer;
    final epk = request.headers.value(SyncSession.headerPairKey) ?? '';
    if (offer == null || !offer.announced.add(epk)) return;
    offer.pairedFingerprint = session.fingerprint;
    final from = request.connectionInfo?.remoteAddress.address ?? 'جهاز';
    await AuditRepo(db).log(
      action: 'sync.pair.success',
      entityType: 'مزامنة',
      summary: 'اقتران ناجح مع $from',
      details: {
        'role': 'receiver',
        'host': from,
        'device': request.headers.value(SyncSession.headerDevice) ?? '',
      },
    );
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
    List<int>? body,
    String? claimedDigest,
    List<({SyncSession session, bool paired})> candidates,
  ) {
    final ts = request.headers.value(SyncSession.headerTs);
    final nonce = request.headers.value(SyncSession.headerNonce);
    final mac = request.headers.value(SyncSession.headerMac);

    var error = 'توقيع غير مطابق';
    for (final c in candidates) {
      // [claimedDigest] ⇒ تحققٌ قبل قراءة الجسم؛ وإلا على الجسم المقروء.
      final e = claimedDigest != null
          ? c.session.verifyPreBody(
              method: method,
              path: path,
              ts: ts,
              nonce: nonce,
              mac: mac,
              claimedDigest: claimedDigest,
              seenNonces: <String>{},
            )
          : c.session.verify(
              method: method,
              path: path,
              ts: ts,
              nonce: nonce,
              mac: mac,
              body: body!,
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

  /// أقصى حجم لجسم طلب استيراد. يُقرأ بعد التحقق من التوقيع على بصمته المعلنة
  /// (انظر [SyncSession.verifyPreBody])، وبسقفٍ يمنع جسمًا يتجاوز ما أُعلن.
  static const int maxBodyBytes = 128 * 1024 * 1024;

  /// سقف جسم كل مسارٍ غير الاستيراد (طلب ثقة مشفَّر أو طلب بلا جسم).
  static const int maxSmallBodyBytes = 1024 * 1024;

  /// مهلة قراءة الجسم كله: الخادم يعالج طلبًا واحدًا في كل مرة، فاتصالٌ بطيء
  /// يوقف المزامنة للجميع.
  static const Duration bodyTimeout = Duration(seconds: 60);

  /// يقرأ الجسم بسقف حجم ومهلة، ويعيد `null` إن تجاوزهما (أو أعلن حجمًا أكبر).
  Future<Uint8List?> _readBody(HttpRequest request, [int cap = maxBodyBytes]) async {
    if (request.contentLength > cap) return null;
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in request.timeout(bodyTimeout)) {
        builder.add(chunk);
        if (builder.length > cap) return null;
      }
    } on TimeoutException {
      return null;
    }
    return builder.takeBytes();
  }

  /// محاولة فاشلة: تُسجَّل، وبعد [maxAuthFailures] تُغلق الجلسة كلها.
  Future<void> _onAuthFailure(
    HttpRequest request,
    String error,
    void Function(String)? onEvent, {
    String reason = 'bad_code',
  }) async {
    _authFailures++;
    final from = request.connectionInfo?.remoteAddress.address ?? 'جهاز';
    onEvent?.call('رُفض طلب من $from — $error');
    // في وضع الاقتران بالرمز الفشل محاولة اقتران بسبب مصنَّف؛ وفي وضع الموثوقين
    // رفضٌ لطلب جهاز عادي.
    //
    // ويُخمَد التكرار **في وضع الموثوقين وحده**: صفوف `sensitive` لا تُقلَّم أبدًا
    // (`AuditRepo.protectedRisks`)، وهذا الوضع لا يُغلق بعد المحاولات (وذاك صواب:
    // الإغلاق حينها سلاحٌ بيد المهاجم لا حرزٌ منه). فكان من يَصِل الشبكةَ يكتب
    // صفًّا دائمًا لكل طلبٍ مرفوض بلا حدّ، فينفخ القاعدةَ المشفّرة حتى يملأ القرص.
    //
    // أما وضعُ الاقتران فمحدودٌ أصلًا بـ[maxAuthFailures] ثم يُغلق، فسقفُه خمسة
    // صفوف لا تتضخّم — وهي أنفسُ ما في السجل: محاولاتُ تخمينِ رمز الاقتران.
    // فتُسجَّل كلُّها بلا خمد.
    final suppressed = _trustedOnly ? _rejectLog.hit('$from|$reason', _now()) : null;
    if (suppressed == null) {
      await AuditRepo(db).log(
        action: _trustedOnly ? 'sync.reject' : 'sync.pair.failed',
        entityType: 'مزامنة',
        summary: _trustedOnly ? 'رُفض طلب مزامنة من $from — $error' : 'فشل اقتران من $from — $error',
        details: _trustedOnly
            ? {'host': from, 'reason': error, 'risk': 'sensitive'}
            : {'host': from, 'reason': reason, 'message': error, 'role': 'receiver', 'risk': 'sensitive'},
      );
    } else if (suppressed > 0) {
      // نهاية نافذة الخمد: صفٌّ واحد يحمل عدد ما خُمد فيها.
      await AuditRepo(db).log(
        action: 'sync.reject',
        entityType: 'مزامنة',
        summary: 'و$suppressed طلبًا مرفوضًا آخر من $from في آخر '
            '${RejectLog.window.inMinutes} دقائق — $error',
        details: {'host': from, 'reason': reason, 'suppressed': suppressed, 'risk': 'sensitive'},
      );
    }
    await _reject(request, error, HttpStatus.unauthorized);
    // الإغلاق حارسٌ لرمز الاقتران من التخمين. في استقبال الموثوقين لا
    // رمز يُخمَّن — والإغلاق حينها يصير سلاحًا بيد المهاجم: خمس محاولات فاشلة
    // تكفي لتعطيل مزامنة الوحدة كلها.
    if (_trustedOnly) return;
    if (_authFailures >= maxAuthFailures) {
      onEvent?.call('تجاوز عدد المحاولات الفاشلة — أُغلق الاستقبال');
      await AuditRepo(db).log(
        action: 'sync.pair.failed',
        entityType: 'مزامنة',
        summary: 'أُغلق الاستقبال بعد $maxAuthFailures محاولات اقتران فاشلة',
        details: {'host': from, 'reason': 'locked', 'role': 'receiver', 'risk': 'sensitive'},
      );
      // بلا انتظار: النداء يأتي من داخل حلقة الطلبات التي يغلقها الإيقاف نفسه.
      unawaited(stopReceiving());
    }
  }

  /// ردّ 413 ثم قطع الاتصال. الردّ العادي ينتظر استهلاك الجسم المتبقي، وهو ما
  /// نرفض قراءته أصلًا؛ فيُفصل المقبس ليُحرَّر الخادم (يعالج طلبًا واحدًا في كل مرة).
  Future<void> _rejectTooLarge(HttpRequest request) async {
    try {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write('HTTP/1.1 413 Payload Too Large\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
      await socket.flush();
      socket.destroy();
    } catch (_) {
      // متوقع: العميل قطع الاتصال قبل وصول الرفض: لا أحد ليُبلَّغ.
    }
  }

  Future<void> _reject(HttpRequest request, String error, int status) async {
    // ردٌّ عادي ينتظر استهلاك جسمٍ لم نقرأه (ولن نقرأه): فيُفصل المقبس بعد الردّ.
    if (request.contentLength != 0) {
      try {
        final payload = utf8.encode(jsonEncode({'ok': false, 'error': error}));
        final socket = await request.response.detachSocket(writeHeaders: false);
        final phrase = const {400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden'}[status] ?? 'Error';
        socket.add(utf8.encode('HTTP/1.1 $status $phrase\r\n'
            'Content-Type: application/json; charset=utf-8\r\n'
            'Connection: close\r\n'
            'Content-Length: ${payload.length}\r\n\r\n'));
        socket.add(payload);
        await socket.flush();
        socket.destroy();
      } catch (_) {
        // متوقع: العميل قطع الاتصال قبل وصول الرفض.
      }
      return;
    }
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': false, 'error': error}));
      await request.response.close();
    } catch (_) {
      // متوقع: العميل قطع الاتصال قبل وصول الرفض: لا أحد ليُبلَّغ.
    }
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
    _offer = null;
    _seenNonces.clear();
    _rejectLog.clear();
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
      } catch (_) {
        // متوقع: حزمة اكتشاف مشوّهة أو غريبة من الشبكة: تُهمَل ولا تُسجَّل (قد يغمرنا مرسِلٌ خبيث بها).
      }
    });

    // البثّ العام (255.255.255.255) تحجبه كثيرٌ من نقاط الوصول وجدارُ ويندوز،
    // فيُضاف إليه بثُّ كل شبكة على حدة (آخر خانة 255) — وهو ما يعبر فعلًا في
    // شبكات الوحدات. تُجرَّب العناوين كلها: ما حُجب منها لا يضرّ، وما عبر كفى.
    for (final target in await _broadcastTargets()) {
      try {
        socket.send(utf8.encode(_hello), InternetAddress(target), discoveryPort);
      } catch (_) {
        // عنوانٌ لا يُبثّ عليه (واجهة معطَّلة أو شبكة لا تسمح): البقية تكفي.
      }
    }
    await Future<void>.delayed(timeout);
    socket.close();
    return [
      for (final e in found.entries)
        (address: e.key, device: e.value.device, id: e.value.id),
    ];
  }

  /// عناوين البثّ التي يُرسل إليها نداء الاكتشاف: العام وبثُّ كل شبكة محلية.
  ///
  /// يُفترض قناع /24 — وهو قناع شبكات الوحدات عمليًّا، و`NetworkInterface` في
  /// Dart لا تُعلن القناع أصلًا. وخطأُ الافتراض لا يكسر شيئًا: حزمةٌ لا تجد
  /// مستمعًا، والعنوان المحفوظ والبثُّ العام باقيان.
  static Future<List<String>> _broadcastTargets() async {
    final out = <String>{'255.255.255.255'};
    for (final addr in await localAddresses()) {
      final parts = addr.split('.');
      if (parts.length == 4) out.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return out.toList();
  }

  /// بطاقة الترحيب المفتوحة لجهاز على الشبكة — بها يُعرف معرّفه قبل أي توقيع.
  /// [timeout] الافتراضي [helloTimeout] — وهو ما يناسب تأكيدَ عنوانٍ جاء من
  /// الاكتشاف على الشبكة نفسها. والعنوان المحفوظ يُمرَّر له [savedHostTimeout].
  Future<({String device, String id, String salt})?> hello(
    String host, {
    int? port,
    Duration timeout = helloTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse('http://$host:${port ?? this.port}/hello'));
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join().timeout(timeout);
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

  /// الاقتران بجهاز استقبال: يجلب من `/hello` الملح والمفتاح العام المؤقت، ثم
  /// يشتق مفتاح الجلسة من الرمز وECDH، ويثبت صحته بطلب `/info` موقَّع.
  /// رمز خاطئ ⇒ يردّ الخادم بالرفض ولا تُبنى جلسة.
  ///
  /// جهاز استقبال بإصدار قديم (v2) يُرفض بوضوح: لا رجوع إلى الاقتران القديم
  /// لأن إتاحته تُبطل الحماية (هجوم خفض المستوى).
  Future<SyncPairing> pair(String host, String code, {int? port}) async {
    final peerPort = port ?? this.port;
    final normalized = PairingCode.normalize(code);
    if (normalized == null) {
      return const SyncPairing(
        ok: false,
        message: 'رمز الاقتران ٨ أحرف: أرقام ٢–٩ وحروف إنجليزية بلا I وO',
      );
    }
    await _auditPair('sync.pair.started', 'بدء اقتران مع $host', host, {'port': peerPort});
    try {
      final client = HttpClient()..connectionTimeout = wanTimeout;
      final req = await client.getUrl(Uri.parse('http://$host:$peerPort/hello'));
      final res = await req.close();
      final body = await utf8.decoder.bind(res).join();
      client.close();
      if (res.statusCode != HttpStatus.ok) {
        return await _pairFailed(host, 'http_${res.statusCode}', 'الجهاز ردّ بالحالة ${res.statusCode}');
      }
      final map = jsonDecode(body) as Map<String, dynamic>;
      final version = (map['v'] as num?)?.toInt() ?? 0;
      if (version < 3) {
        return await _pairFailed(host, 'v2_rejected', 'يجب تحديث التطبيق على الجهاز الآخر أولاً');
      }
      final salt = (map['salt'] ?? '').toString();
      final pub = (map['pub'] ?? '').toString();
      if (salt.isEmpty || pub.isEmpty) {
        return await _pairFailed(host, 'not_receiving', 'الجهاز لا يستقبل الآن');
      }
      // يُقرأ قبل أول طلب موقَّع، وإلا رُفض الاقتران نفسه لانحراف الساعة.
      _noteClock(host, map);
      final session = await SyncSession.fromPairing(normalized, salt, pub);
      final info = await probe(host, peerPort, session);
      if (info == null) {
        return await _pairFailed(host, 'bad_code', 'رمز الاقتران غير صحيح');
      }
      await _auditPair('sync.pair.success', 'اقتران ناجح مع $host', host, {'device': info.deviceName});
      return SyncPairing(
        ok: true,
        message: 'تم الاقتران',
        peer: SyncPeer(host: host, port: peerPort, session: session, info: info),
      );
    } on SyncCryptoError catch (e) {
      return await _pairFailed(host, 'bad_key', e.message);
    } catch (e) {
      return await _pairFailed(host, 'unreachable', 'تعذّر الاتصال بـ $host — $e');
    }
  }

  Future<SyncPairing> _pairFailed(String host, String reason, String message) async {
    await _auditPair('sync.pair.failed', 'فشل اقتران مع $host — $message', host, {
      'reason': reason,
      'message': message,
      'risk': 'sensitive',
    });
    return SyncPairing(ok: false, message: message);
  }

  /// سجل تدقيق لاقتران صادر من هذا الجهاز (دور المرسِل).
  Future<void> _auditPair(String action, String summary, String host, Map<String, dynamic> extra) =>
      AuditRepo(db).log(
        action: action,
        entityType: 'مزامنة',
        summary: summary,
        details: {'role': 'sender', 'host': host, ...extra},
      );

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
    // في الاتجاهين كذلك (انظر `POST /trust`): هذا الجهاز يسحب ويدفع إلى
    // القرين (`peers`)، ويقبل منه دورةً يبدؤها هو (`accepted`) — فمن فتح
    // تطبيقه أولًا زامن، ولا ينتظر أحدٌ أحدًا.
    await SyncTrust(db).remember(remembered);
    await SyncTrust(db).accept(remembered);
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
    // الترميم أولًا: جهازٌ اقترن قبل أن تُكتب الثقة في الاتجاهين يحمل القرين
    // في `accepted` وحدها، فتبدو قائمة الأقران فارغةً وهو موثوق.
    await store.mirror();
    final peers = await store.peers();
    if (peers.isEmpty) {
      return const SyncResult(ok: false, failed: false, message: 'لا يوجد جهاز موثوق — اقترن مرة واحدة يدويًا');
    }

    var records = 0;
    var reached = 0;
    final problems = <String>[];
    for (final p in peers) {
      final label = p.name.isEmpty ? p.deviceId : p.name;
      final host = await _locate(p);
      if (host == null) {
        // الرسالة تقول ما يُفعل: أكثر ما يُوقف المزامنة أن التطبيق مغلق على
        // الجهاز الآخر أو أن مزامنته التلقائية غير مفعَّلة — فمنفذه مغلق.
        problems.add('$label لم يُعثر عليه (افتح التطبيق عليه وفعّل مزامنته التلقائية، '
            'وتأكّد أن الجهازين على الشبكة نفسها)');
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
      final card = await hello(peer.host, timeout: savedHostTimeout);
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
        includeOwnerSecrets: false,
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
      final result = await LegacyImporter(db, ownerPublicKey: ownerPublicKey).importJson(
        data,
        source: 'جهاز $host',
      );
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
        if (session.pairingEpk != null) SyncSession.headerPairKey: session.pairingEpk!,
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

/// خمدُ شواهد التدقيق المتكررة لطلبٍ مرفوض من المصدر نفسه بالسبب نفسه.
///
/// صفوف `sensitive` لا تُقلَّم أبدًا، واستقبالُ الموثوقين لا يُغلق بعد محاولات
/// فاشلة (الإغلاق حينها سلاحٌ بيد المهاجم لا حرزٌ منه). فبلا خمدٍ يكتب كلُّ من
/// يَصِل الشبكةَ صفًّا دائمًا لكل طلبٍ مرفوض، فتنفخ القاعدةَ المشفّرة بلا حدّ.
///
/// السياسة: أولُ رفضٍ من مفتاحٍ يُسجَّل كاملًا، وما يليه في [window] يُعَدّ ولا
/// يُسجَّل، فإذا انقضت النافذة سُجّل صفٌّ واحد بعدد ما خُمد. فيبقى الخبر (ومعه
/// حجمُه) ولا يبقى التضخّم.
class RejectLog {
  RejectLog({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  /// نافذة الخمد. دقيقتان: أقصرُ من أن تُخفي هجومًا، وأطولُ من أن يُكتب صفٌّ
  /// لكل حزمةٍ في إغراق.
  static const Duration window = Duration(minutes: 2);

  /// سقفُ المفاتيح المتتبَّعة. مهاجمٌ يبدّل عنوانه لكل طلب لا يُنمي الخريطة بلا
  /// حدّ: عند الامتلاء تُنسى الأقدم.
  static const int maxKeys = 512;

  final Map<String, ({DateTime first, int count})> _seen = {};

  /// `null` ⇒ سجّل هذا الرفض كاملًا. رقمٌ > 0 ⇒ انقضت النافذة وهذا عددُ ما خُمد
  /// فيها (سجّل ملخَّصًا). صفرٌ ⇒ اخمد بلا تسجيل.
  int? hit(String key, [DateTime? at]) {
    final now = at ?? _now();
    final e = _seen[key];
    if (e == null) {
      if (_seen.length >= maxKeys) _seen.remove(_seen.keys.first);
      _seen[key] = (first: now, count: 0);
      return null; // أول رفضٍ من هذا المفتاح: يُسجَّل
    }
    if (now.difference(e.first) >= window) {
      _seen[key] = (first: now, count: 0);
      return e.count; // انقضت النافذة: ملخَّصٌ بما خُمد (0 ⇒ لا ملخَّص)
    }
    _seen[key] = (first: e.first, count: e.count + 1);
    return 0; // داخل النافذة: اخمد
  }

  void clear() => _seen.clear();

  @visibleForTesting
  int get length => _seen.length;
}
