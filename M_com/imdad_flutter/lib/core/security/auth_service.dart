import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/section_block.dart';
import 'owner_promotion.dart';
import 'password_hash.dart';
import 'warehouse_scope.dart';
import '../../data/sync/sync_marks.dart';
import '../../data/sync/sync_trust.dart';
import '../../core/error_log.dart';

/// نتيجة محاولة الدخول
enum AuthStatus { ok, badCredentials, locked, inactive, notApproved }

class AuthResult {
  final AuthStatus status;
  final User? user;
  final int attemptsLeft;
  final Duration lockRemaining;
  final String message;

  const AuthResult({
    required this.status,
    this.user,
    this.attemptsLeft = 0,
    this.lockRemaining = Duration.zero,
    this.message = '',
  });

  bool get isOk => status == AuthStatus.ok;
}

/// المصادقة والجلسة:
/// • PBKDF2-HMAC-SHA256 + salt لكل مستخدم؛ الحسابات القديمة (45,000 دورة) تُعاد
///   تجزئتها بالعدد الحالي تلقائيًا عند أول دخول ناجح.
/// • قفل الدخول بعد 5 محاولات خاطئة لمدة 3 دقائق (لكل اسم مستخدم).
/// • مدة الجلسة 12 ساعة ثم يُطلب الدخول من جديد.
/// • عدّاد المحاولات والجلسة (المعرّف ووقت البدء) محفوظان في قاعدة البيانات
///   المشفّرة (SQLCipher) لا في `SharedPreferences` المقروءة والقابلة للتعديل
///   بملفٍّ نصي. القيم القديمة في `SharedPreferences` تُنقل مرةً واحدة عند أول
///   قراءة ثم تُمسح، فلا تسقط الجلسات القائمة عند الترقية.
class AuthService {
  AuthService(this.db, {this.isBranchDevice});

  final AppDatabase db;

  /// هل هذا جهاز فرع؟ (يصله المالك بالمزامنة فلا يُرقّى فيه ولا يُحدَّد.)
  /// `null` ⇒ ليس فرعًا (جهاز مستقل أو إدارة).
  final Future<bool> Function()? isBranchDevice;

  Future<bool> _isBranch() async {
    try {
      return await isBranchDevice?.call() ?? false;
    } catch (err, stack) {
      ErrorLogger.log('auth.isBranch', err, stack);
      return true; // فشلٌ مغلق: لا ترقية إن لم نعرف
    }
  }

  /// يرقّي المدير المحلي الوحيد إلى مالك إن انطبقت الشروط ([OwnerPromotion.run]).
  /// لا يُفشل الدخول أبدًا: عطبٌ هنا يُسجَّل ويُترك.
  Future<void> _promoteOwnerIfDue() async {
    try {
      await OwnerPromotion.run(db, isBranchDevice: await _isBranch());
    } catch (err, stack) {
      ErrorLogger.log('auth.ownerPromotion', err, stack);
    }
  }

  /// لا مالك وأكثر من مدير ⇒ يُنبَّه المديرون ليحدّدوا المالك. (لا في الفروع.)
  Future<bool> ownerSelectionNeeded() async {
    if (await _isBranch()) return false;
    return OwnerPromotion.needsSelection(db);
  }

  /// يؤكّد كلمة مرور المستخدم الحالي دون فتح جلسة ولا عدّ محاولات — لتأكيد
  /// إجراءٍ حسّاس (تحديد المالك).
  Future<bool> confirmCurrentPassword(String password) async {
    final u = _current;
    if (u == null || password.isEmpty) return false;
    final fresh = await (db.select(db.users)..where((t) => t.id.equals(u.id))).getSingleOrNull();
    if (fresh == null) return false;
    return PasswordHash.verify(password, fresh.saltHex, fresh.hashHex, fresh.iterations);
  }

  /// يحدّد [userId] مالكًا: مديرٌ حالي، وكلمة مروره تأكيدٌ، وليس جهاز فرع.
  Future<bool> assignOwner({required String userId, required String confirmPassword}) async {
    final me = _current;
    if (me == null || !UserRole.isAdmin(me.role)) return false;
    if (await _isBranch()) return false;
    if (!await confirmCurrentPassword(confirmPassword)) return false;
    final ok = await OwnerPromotion.assign(db, userId: userId, actorEmail: me.email);
    if (ok && userId == me.id) {
      _current = await (db.select(db.users)..where((t) => t.id.equals(me.id))).getSingleOrNull() ?? _current;
    }
    return ok;
  }

  /// الحد الأدنى لطول كلمة المرور عند إنشاء الحساب أو تغييرها.
  static const int minPasswordLength = 8;

  /// هل يُنبَّه هذا المستخدم لتغيير كلمة مروره بعد الدخول؟ كلمته أقصر من الحد
  /// الحالي ([minPasswordLength]) وليس مديرًا (المدراء لا يُزعَجون بالتنبيه).
  static bool shouldSuggestPasswordChange({required String role, required String password}) =>
      !UserRole.isAdmin(role) && password.length < minPasswordLength;

  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 3); // AUTHCORE.LOCK_MS = 180000
  static const Duration sessionDuration = Duration(hours: 12);
  // مفاتيح التخزين القديم في SharedPreferences — للترحيل والمسح فقط.
  static const String _kSessionUser = 'imdad.session.userId';
  static const String _kSessionStart = 'imdad.session.startedAt';
  static const String _kLockPrefix = 'imdad.auth.lock.';

  // مفاتيح قاعدة البيانات (جدول الإعدادات، محلية فقط: SettingsRepo.localOnlyKeys).
  static const String _sessionKey = 'authSession';
  static const String _locksKey = 'authLocks';

  User? _current;
  User? get currentUser => _current;

  /// يرتفع كلما تغيّر **دور** المستخدم الحالي أو **حجب أقسامه** في القاعدة (وصل
  /// بالمزامنة مثلًا) فتُعيد الشاشات بناءها. الكائن الحالي يُستبدل بالمحدَّث فيسري
  /// الحجب والدور الجديدان فورًا لا عند الدخول التالي فقط.
  final ValueNotifier<int> userVersion = ValueNotifier<int>(0);
  StreamSubscription<Object?>? _userWatch;

  void _watchCurrent() {
    _userWatch?.cancel();
    _userWatch = db.tableUpdates(TableUpdateQuery.onTable(db.users)).listen((_) => _refreshCurrent());
  }

  Future<void> _refreshCurrent() async {
    final me = _current;
    if (me == null) return;
    final fresh = await (db.select(db.users)..where((t) => t.id.equals(me.id))).getSingleOrNull();
    if (fresh == null || _current?.id != me.id) return; // الحذف والإيقاف يعالجهما فحص الجلسة
    if (fresh.role == me.role && fresh.sectionBlocked == me.sectionBlocked) return;
    _current = fresh;
    userVersion.value++;
  }

  /// لا يوجد أي مستخدم بعد ⇒ تظهر تهيئة حساب المدير الأول.
  /// يظهر قسم التهيئة ما دام لا يوجد حساب مدير مُهيّأ محليًا.
  Future<bool> needsBootstrap() async {
    final count =
        await db.customSelect("SELECT COUNT(*) AS c FROM users WHERE id LIKE 'local-%'").getSingle();
    return (count.data['c'] as int) == 0;
  }

  /// هل على هذا الجهاز أي حساب يُدخل به؟
  ///
  /// غير [needsBootstrap] عمدًا: ذاك يسأل عن حساب مدير **مُهيّأ محليًا**، وهذا
  /// يسأل عن أي حساب مهما كان مصدره. جهاز الفرع يستقبل حساباته بالمزامنة
  /// بمعرّفات ليست `local-`، فلو قِيس دخوله بـ[needsBootstrap] لبقي «جديدًا»
  /// إلى الأبد رغم امتلاكه حسابات.
  Future<bool> hasAnyUser() async {
    final count = await db.customSelect('SELECT COUNT(*) AS c FROM users').getSingle();
    return (count.data['c'] as int) > 0;
  }

  Future<User> createAdmin({
    required String username,
    required String password,
    String name = '',
  }) async {
    final u = _normalizeUsername(username);
    _validateUsername(u);
    _validatePassword(password);
    final ph = await PasswordHash.create(password);
    final id = 'local-$u';
    final row = UsersCompanion.insert(
      id: id,
      username: u,
      name: Value(name.isEmpty ? u : name),
      email: Value('$u@imdad.local'),
      role: const Value('admin'),
      saltHex: Value(ph.saltHex),
      hashHex: Value(ph.hashHex),
      iterations: Value(ph.iterations),
      warehouseScope: const Value('ALL'),
    );
    await db.into(db.users).insert(row);
    final user = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
    await _startSession(user);
    return user;
  }

  Future<AuthResult> login(String username, String password) async {
    // نفس `doLogin` في auth-ux.js: الرسائل، وعدّاد المحاولات لكل اسم مستخدم (حتى غير الموجود).
    final u = username.trim();
    if (u.isEmpty || password.isEmpty) {
      return const AuthResult(status: AuthStatus.badCredentials, message: '✖ أدخل اسم المستخدم وكلمة المرور');
    }
    final user = u.contains('@') ? u.split('@').first : u;
    // المطابقة غير حساسة لحالة الأحرف، فالعدّاد كذلك: وإلا أخذ كل شكل للاسم
    // (admin / Admin / ADMIN …) خمس محاولات مستقلة وسقط القفل.
    final lockKey = user.toLowerCase();
    final st = await _lockRead(lockKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (st.until > now) {
      final remaining = Duration(milliseconds: st.until - now);
      return AuthResult(
        status: AuthStatus.locked,
        lockRemaining: remaining,
        message: '⏳ تم قفل الدخول مؤقتًا بسبب محاولات كثيرة. حاول بعد ${_fmt(remaining)}',
      );
    }

    // الحساب المحلي بالاسم نفسه أولًا، ثم مطابقة غير حساسة لحالة الأحرف (findUserAccount).
    var matches = await (db.select(db.users)..where((t) => t.username.equals(user))).get();
    if (matches.isEmpty) {
      final all = await db.select(db.users).get();
      final q = user.toLowerCase();
      matches = all
          .where((x) => x.username.toLowerCase() == q || x.email.toLowerCase() == u.toLowerCase())
          .toList();
    }
    final found = matches.isEmpty ? null : matches.first;
    final ok = found != null &&
        await PasswordHash.verify(password, found.saltHex, found.hashHex, found.iterations);

    if (!ok) {
      final ns = st.fails + 1 >= maxAttempts
          ? _LockState(0, now + lockDuration.inMilliseconds)
          : _LockState(st.fails + 1, 0);
      await _lockStore(lockKey, ns);
      if (ns.until > now) {
        return const AuthResult(
          status: AuthStatus.locked,
          lockRemaining: lockDuration,
          message: '⛔ كثير جدًا من المحاولات — تم قفل الدخول لهذا المستخدم مؤقتًا.',
        );
      }
      return AuthResult(
        status: AuthStatus.badCredentials,
        attemptsLeft: maxAttempts - ns.fails,
        message: '✖ اسم المستخدم أو كلمة المرور غير صحيحة (${ns.fails}/$maxAttempts)',
      );
    }

    if (!found.active) {
      return const AuthResult(
        status: AuthStatus.inactive,
        message: '✖ الحساب غير مفعّل — اطلب من مدير النظام تفعيل حسابك',
      );
    }
    if (!found.approved) {
      return const AuthResult(
        status: AuthStatus.notApproved,
        message: '✖ الحساب غير معتمد بعد — انتظر اعتماد المدير',
      );
    }

    await _lockStore(lockKey, const _LockState(0, 0));
    await _promoteOwnerIfDue();
    final fresh =
        await (db.select(db.users)..where((t) => t.id.equals(found.id))).getSingleOrNull() ?? found;
    final account = await _upgradeHash(fresh, password);
    await _startSession(account);
    return AuthResult(status: AuthStatus.ok, user: account, message: '🌐 تم الدخول محليًا (بدون إنترنت)');
  }

  /// يفتح جلسةً لمستخدمٍ تحقّق منه مسارٌ آخر غير كلمة المرور (البصمة).
  /// الشروط بعد التحقق هي نفسها: مفعَّل ومعتمد.
  Future<AuthResult> startSessionFor(User user) async {
    if (!user.active) {
      return const AuthResult(
        status: AuthStatus.inactive,
        message: '✖ الحساب غير مفعّل — اطلب من مدير النظام تفعيل حسابك',
      );
    }
    if (!user.approved) {
      return const AuthResult(
        status: AuthStatus.notApproved,
        message: '✖ الحساب غير معتمد بعد — انتظر اعتماد المدير',
      );
    }
    await _startSession(user);
    return AuthResult(status: AuthStatus.ok, user: user, message: '🌐 تم الدخول بالبصمة');
  }

  /// إعادة تجزئة كلمة المرور بالعدد الحالي من الدورات إن كانت بصمتها أضعف.
  ///
  /// لا تُعرف كلمة المرور الصريحة إلا لحظة الدخول، فهذه الفرصة الوحيدة للترقية.
  /// التحديث يمر بمشغّلات المزامنة فتصل البصمة الجديدة إلى بقية الأجهزة، وفشله
  /// لا يمنع الدخول: البصمة القديمة ما زالت صحيحة.
  Future<User> _upgradeHash(User user, String password) async {
    if (!PasswordHash.needsUpgrade(user.iterations)) return user;
    try {
      final ph = await PasswordHash.create(password);
      await (db.update(db.users)..where((t) => t.id.equals(user.id) & t.hashHex.equals(user.hashHex))).write(
        UsersCompanion(
          saltHex: Value(ph.saltHex),
          hashHex: Value(ph.hashHex),
          iterations: Value(ph.iterations),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return await (db.select(db.users)..where((t) => t.id.equals(user.id))).getSingleOrNull() ?? user;
    } catch (_) {
      return user;
    }
  }

  /// «إعادة تعيين محلي»: تُمسح حسابات الدخول من **هذا الجهاز وحده**، وأقفال
  /// المحاولات والجلسة، فيظهر خيار تهيئة مدير جديد أو استقبال الحسابات
  /// بالمزامنة. بقية البيانات لا تُمس.
  ///
  /// **و«محلي» تعني محليًا حقًا.** الحذف في هذا النظام يُكتب له شاهدٌ تحمله
  /// المزامنة إلى بقية الأجهزة — وهو الصواب في حذف صنف أو سند، وكارثةٌ هنا:
  /// مسؤول فرعٍ نسي كلمة مروره فضغط هذا الزر، فسافر الشاهد إلى جهاز الإدارة
  /// وحذف حساب المدير هناك، ثم إلى كل فرع. إجراءُ إنقاذٍ على جهاز واحد يقفل
  /// الوحدة كلها خارج نظامها.
  ///
  /// فتُمحى الشواهد بعد الحذف مباشرة: الجهاز الآخر لا يعلم أن شيئًا حُذف هنا،
  /// وتُصفَّر علامات السحب فتعود الحسابات إليه في أول مزامنة.
  Future<void> localReset() async {
    await (db.delete(db.users)..where((t) => t.id.like('local-%'))).go();

    // لا شاهد يسافر: ما جرى هنا شأن هذا الجهاز.
    await db.customStatement(
      "DELETE FROM ${SyncMarks.table} WHERE entity = 'users' AND deleted_at IS NOT NULL",
    );
    // وتصفير علامات السحب يجعل المزامنة القادمة كاملة، فتعود الحسابات — ولولاه
    // لظنّ الجهاز أنه استلمها فلا يطلبها مرة أخرى أبدًا.
    await SyncTrust(db).resetPullWatermarks();

    await SettingsRepo(db).write(_locksKey, {});
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(_kLockPrefix)).toList()) {
      await prefs.remove(k);
    }
    await logout();
  }

  /// حالة القفل لمستخدم. إن لم توجد في القاعدة وُجد قديمها في SharedPreferences
  /// فيُنقل إلى القاعدة ويُمسح من هناك.
  Future<_LockState> _lockRead(String user) async {
    final repo = SettingsRepo(db);
    final locks = await repo.read(_locksKey);
    final inDb = locks[user];
    if (inDb is Map) return _LockState.fromMap(inDb);

    final prefs = await SharedPreferences.getInstance();
    final legacyRaw = prefs.getString('$_kLockPrefix$user');
    if (legacyRaw == null) return const _LockState(0, 0);
    _LockState legacy = const _LockState(0, 0);
    try {
      legacy = _LockState.fromMap(jsonDecode(legacyRaw) as Map);
    } catch (err, stack) {
      ErrorLogger.log('auth.legacyLock', err, stack);
    }
    locks[user] = legacy.toMap();
    await repo.write(_locksKey, locks);
    await prefs.remove('$_kLockPrefix$user');
    return legacy;
  }

  Future<void> _lockStore(String user, _LockState s) async {
    final repo = SettingsRepo(db);
    final locks = await repo.read(_locksKey);
    if (s.fails == 0 && s.until == 0) {
      locks.remove(user); // لا حاجة لسطر صفري
    } else {
      locks[user] = s.toMap();
    }
    await repo.write(_locksKey, locks);
    // لا يبقى نظيرٌ قديم يُحيي العدّاد بعد تصفيره.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kLockPrefix$user');
  }

  /// الجلسة المحفوظة: (المعرّف، وقت البدء بالمللي ثانية) أو `null`.
  /// إن لم توجد في القاعدة وُجدت قديمةً في SharedPreferences فتُنقل (ترحيلٌ
  /// لمرةٍ واحدة يُبقي الجلسات القائمة صالحة).
  Future<(String, int)?> _readSession() async {
    final repo = SettingsRepo(db);
    final map = await repo.read(_sessionKey);
    final id = map['userId'];
    final at = map['startedAt'];
    if (id is String && id.isNotEmpty && at is num) return (id, at.toInt());

    final prefs = await SharedPreferences.getInstance();
    final legacyId = prefs.getString(_kSessionUser);
    final legacyAt = prefs.getInt(_kSessionStart);
    if (legacyId == null || legacyAt == null) return null;
    await repo.write(_sessionKey, {'userId': legacyId, 'startedAt': legacyAt});
    await _clearLegacySession(prefs);
    return (legacyId, legacyAt);
  }

  Future<void> _clearLegacySession(SharedPreferences prefs) async {
    await prefs.remove(_kSessionUser);
    await prefs.remove(_kSessionStart);
  }

  /// استعادة جلسة سارية (أقل من 12 ساعة) بعد إعادة فتح التطبيق.
  /// هل انتهت مدة الجلسة (12 ساعة) أو أُوقف الحساب؟ تُستدعى دوريًا والتطبيق مفتوح.
  Future<bool> sessionExpired() async {
    if (_current == null) return true;
    final session = await _readSession();
    if (session == null) return true;
    final started = DateTime.fromMillisecondsSinceEpoch(session.$2);
    if (DateTime.now().difference(started) >= sessionDuration) return true;
    final rows = await (db.select(db.users)..where((t) => t.id.equals(_current!.id))).get();
    return rows.isEmpty || !rows.first.active;
  }

  Future<User?> restoreSession() async {
    await _promoteOwnerIfDue();
    final session = await _readSession();
    if (session == null) return null;
    final id = session.$1;
    final started = DateTime.fromMillisecondsSinceEpoch(session.$2);
    if (DateTime.now().difference(started) >= sessionDuration) {
      await logout();
      return null;
    }
    final rows = await (db.select(db.users)..where((t) => t.id.equals(id))).get();
    if (rows.isEmpty || !rows.first.active) {
      await logout();
      return null;
    }
    _current = rows.first;
    _watchCurrent();
    return _current;
  }

  Future<void> logout() async {
    _userWatch?.cancel();
    _userWatch = null;
    _current = null;
    await SettingsRepo(db).write(_sessionKey, {});
    await _clearLegacySession(await SharedPreferences.getInstance());
  }

  Future<void> _startSession(User user) async {
    _current = user;
    _watchCurrent();
    await SettingsRepo(db).write(_sessionKey, {
      'userId': user.id,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _clearLegacySession(await SharedPreferences.getInstance());
  }

  /// صلاحيات المستخدم الحالي، مخزَّنةً JSON.
  Map<String, dynamic> permissionsOf(User user) {
    try {
      return (jsonDecode(user.permissions) as Map).cast<String, dynamic>();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  bool can(User user, String page, [String action = 'view']) {
    if (SysPerm.isSys(page)) return UserRole.isOwner(user.role);
    // القسم المحجوب مغلق (المالك وحده لا يُحجب عنه شيء).
    if (SectionBlock.blocksPage(role: user.role, blockedJson: user.sectionBlocked, page: page)) return false;
    if (UserRole.isAdmin(user.role)) return true;
    final perms = permissionsOf(user);
    return AccessControl.allows(perms[page] is Map ? perms[page] as Map : null, action);
  }

  /// نطاق المستودعات: `null` ⇒ كل المستودعات (المدير أو `ALL`)، وإلا قائمة أسماء.
  /// التالف يُرجع قائمةً فارغة (فشل مغلق) — انظر [parseWarehouseScope].
  List<String>? warehouseScopeOf(User user) {
    if (UserRole.isAdmin(user.role)) return null;
    return parseWarehouseScope(user.warehouseScope, source: 'auth.warehouseScope');
  }

  static String _normalizeUsername(String v) => v.trim();

  static void _validateUsername(String v) {
    if (!RegExp(r'^[A-Za-z0-9_.]{3,20}$').hasMatch(v)) {
      throw ArgumentError('✖ اسم المستخدم: 3-20 حرفًا إنجليزيًا/أرقام/نقطة/شرطة سفلية');
    }
  }

  static void _validatePassword(String v) {
    if (v.length < minPasswordLength) throw ArgumentError('✖ كلمة المرور $minPasswordLength أحرف على الأقل');
  }

  /// مدّةٌ بالمللي ثانية إلى نصٍّ مقروء.
  static String _fmt(Duration d) {
    final s = (d.inMilliseconds / 1000).ceil();
    return s < 60 ? '$s ثانية' : '${(s / 60).ceil()} دقيقة';
  }
}

class _LockState {
  const _LockState(this.fails, this.until);

  factory _LockState.fromMap(Map o) =>
      _LockState((o['fails'] as num?)?.toInt() ?? 0, (o['until'] as num?)?.toInt() ?? 0);

  final int fails;
  final int until;

  Map<String, dynamic> toMap() => {'fails': fails, 'until': until};
}
