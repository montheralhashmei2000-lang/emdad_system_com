import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/app_database.dart';
import 'pbkdf2.dart';

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

/// المصادقة والجلسة — نقل مطابق لسلوك نظام الويب:
/// • PBKDF2-HMAC-SHA256 بـ 45,000 دورة + salt لكل مستخدم.
/// • قفل الدخول بعد 5 محاولات خاطئة لمدة 3 دقائق (لكل اسم مستخدم).
/// • مدة الجلسة 12 ساعة ثم يُطلب الدخول من جديد.
class AuthService {
  AuthService(this.db);

  final AppDatabase db;

  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 3); // AUTHCORE.LOCK_MS = 180000
  static const Duration sessionDuration = Duration(hours: 12);
  static const String _kSessionUser = 'imdad.session.userId';
  static const String _kSessionStart = 'imdad.session.startedAt';

  User? _current;
  User? get currentUser => _current;

  /// لا يوجد أي مستخدم بعد ⇒ تظهر تهيئة حساب المدير الأول.
  /// يظهر قسم التهيئة ما دام لا يوجد حساب مدير مُهيّأ محليًا (`AUTH_LOCAL.hasUsers()` في الويب).
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
    final salt = Pbkdf2.newSaltHex();
    final hash = Pbkdf2.deriveHex(password, salt);
    final id = 'local-$u';
    final row = UsersCompanion.insert(
      id: id,
      username: u,
      name: Value(name.isEmpty ? u : name),
      email: Value('$u@imdad.local'),
      role: const Value('admin'),
      saltHex: Value(salt),
      hashHex: Value(hash),
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
    final prefs = await SharedPreferences.getInstance();
    final st = _lockRead(prefs, user);
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
        Pbkdf2.constantTimeEquals(
          Pbkdf2.deriveHex(password, found.saltHex, iterations: found.iterations),
          found.hashHex,
        );

    if (!ok) {
      final ns = st.fails + 1 >= maxAttempts
          ? _LockState(0, now + lockDuration.inMilliseconds)
          : _LockState(st.fails + 1, 0);
      await _lockStore(prefs, user, ns);
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

    await _lockStore(prefs, user, const _LockState(0, 0));
    await _startSession(found);
    return AuthResult(status: AuthStatus.ok, user: found, message: '🌐 تم الدخول محليًا (بدون إنترنت)');
  }

  /// «إعادة تعيين محلي» في الويب: تُمسح حسابات الدخول المحلية (حسابات المدير المُهيّأة من شاشة الدخول)
  /// وأقفال المحاولات والجلسة، فيظهر خيار تهيئة مدير جديد. بقية البيانات لا تُمس.
  Future<void> localReset() async {
    await (db.delete(db.users)..where((t) => t.id.like('local-%'))).go();
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith('imdad.auth.lock.')).toList()) {
      await prefs.remove(k);
    }
    await logout();
  }

  static _LockState _lockRead(SharedPreferences prefs, String user) {
    try {
      final o = jsonDecode(prefs.getString('imdad.auth.lock.$user') ?? '{}') as Map;
      return _LockState((o['fails'] as num?)?.toInt() ?? 0, (o['until'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return const _LockState(0, 0);
    }
  }

  static Future<void> _lockStore(SharedPreferences prefs, String user, _LockState s) =>
      prefs.setString('imdad.auth.lock.$user', jsonEncode({'fails': s.fails, 'until': s.until}));

  /// استعادة جلسة سارية (أقل من 12 ساعة) بعد إعادة فتح التطبيق.
  /// هل انتهت مدة الجلسة (12 ساعة) أو أُوقف الحساب؟ تُستدعى دوريًا والتطبيق مفتوح.
  Future<bool> sessionExpired() async {
    if (_current == null) return true;
    final prefs = await SharedPreferences.getInstance();
    final startedMs = prefs.getInt(_kSessionStart);
    if (startedMs == null) return true;
    final started = DateTime.fromMillisecondsSinceEpoch(startedMs);
    if (DateTime.now().difference(started) >= sessionDuration) return true;
    final rows = await (db.select(db.users)..where((t) => t.id.equals(_current!.id))).get();
    return rows.isEmpty || !rows.first.active;
  }

  Future<User?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kSessionUser);
    final startedMs = prefs.getInt(_kSessionStart);
    if (id == null || startedMs == null) return null;
    final started = DateTime.fromMillisecondsSinceEpoch(startedMs);
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
    return _current;
  }

  Future<void> logout() async {
    _current = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionUser);
    await prefs.remove(_kSessionStart);
  }

  Future<void> _startSession(User user) async {
    _current = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionUser, user.id);
    await prefs.setInt(_kSessionStart, DateTime.now().millisecondsSinceEpoch);
  }

  /// صلاحيات المستخدم الحالي (JSON مطابق لبنية نظام الويب).
  Map<String, dynamic> permissionsOf(User user) {
    try {
      return (jsonDecode(user.permissions) as Map).cast<String, dynamic>();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  bool can(User user, String page, [String action = 'view']) {
    if (user.role == 'admin') return true;
    final perms = permissionsOf(user);
    final p = perms[page];
    if (p is Map) return p[action] == true;
    return false;
  }

  /// نطاق المستودعات: ALL أو قائمة أسماء.
  List<String>? warehouseScopeOf(User user) {
    if (user.role == 'admin' || user.warehouseScope == 'ALL') return null; // كل المستودعات
    try {
      final v = jsonDecode(user.warehouseScope);
      if (v is List) return v.map((e) => e.toString()).toList();
    } catch (_) {}
    return null;
  }

  static String _normalizeUsername(String v) => v.trim();

  static void _validateUsername(String v) {
    if (!RegExp(r'^[A-Za-z0-9_.]{3,20}$').hasMatch(v)) {
      throw ArgumentError('✖ اسم المستخدم: 3-20 حرفًا إنجليزيًا/أرقام/نقطة/شرطة سفلية');
    }
  }

  static void _validatePassword(String v) {
    if (v.length < 6) throw ArgumentError('✖ كلمة المرور 6 أحرف على الأقل');
  }

  /// `fmt(ms)` في الويب.
  static String _fmt(Duration d) {
    final s = (d.inMilliseconds / 1000).ceil();
    return s < 60 ? '$s ثانية' : '${(s / 60).ceil()} دقيقة';
  }
}

class _LockState {
  const _LockState(this.fails, this.until);
  final int fails;
  final int until;
}
