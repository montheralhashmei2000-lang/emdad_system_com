import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/db/app_database.dart';
import '../../data/db/db_cipher.dart' show imdSecureStorage;
import '../error_log.dart';
import 'auth_service.dart';

/// حالة توفّر البصمة على الجهاز.
enum BiometricAvailability {
  /// منصةٌ لا تدعمها (ويندوز وغيره): الميزة لأندرويد وحده.
  unsupportedPlatform,

  /// الجهاز بلا مستشعر، أو لم تُسجَّل فيه بصمةٌ في إعدادات النظام.
  unavailable,

  available,
}

/// الدخول بالبصمة (أندرويد).
///
/// **النموذج الأمني:** البصمة لا تحلّ محلّ كلمة المرور بل تختصر دورة الدخول
/// على جهازٍ سبق أن دخله صاحبه بكلمة مروره:
/// • التفعيل لا يتمّ إلا بعد دخولٍ ناجح بكلمة المرور **ثم** بصمةٌ تؤكّد التفعيل.
/// • الاعتماد يُخزَّن في Android Keystore (`flutter_secure_storage`) لا في
///   قاعدة البيانات ولا `SharedPreferences`: معرّف المستخدم + بصمة (hash)
///   كلمة مروره وقت التفعيل.
/// • تغيير كلمة المرور (أو إعادة تعيينها) يُبطل الاعتماد تلقائيًّا فلا يدخل
///   بالبصمة حتى يدخل بالكلمة الجديدة مرةً ويُعيد التفعيل.
/// • `biometricOnly`: لا رجوع إلى رمز/نمط القفل، فمن يعرف رمز الهاتف لا يدخل.
/// • الحساب الموقوف أو غير المعتمد لا يدخل بالبصمة (نفس شروط [AuthService.login]).
class BiometricService {
  BiometricService(this.db, this.auth, {LocalAuthentication? localAuth, FlutterSecureStorage? storage})
      : _local = localAuth ?? LocalAuthentication(),
        _storage = storage ?? imdSecureStorage;

  final AppDatabase db;
  final AuthService auth;
  final LocalAuthentication _local;
  final FlutterSecureStorage _storage;

  static const _kUser = 'imdad.bio.userId';
  static const _kHash = 'imdad.bio.hash';
  static const _kDeclined = 'imdad.bio.declined';

  /// تُستبدل في الاختبارات.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _isAndroid => debugAndroid ?? Platform.isAndroid;

  Future<BiometricAvailability> availability() async {
    if (!_isAndroid) return BiometricAvailability.unsupportedPlatform;
    try {
      if (!await _local.isDeviceSupported()) return BiometricAvailability.unavailable;
      final types = await _local.getAvailableBiometrics();
      return types.isEmpty ? BiometricAvailability.unavailable : BiometricAvailability.available;
    } catch (err, stack) {
      ErrorLogger.log('biometric.availability', err, stack);
      return BiometricAvailability.unavailable;
    }
  }

  /// معرّف المستخدم المسجَّلة بصمته على هذا الجهاز، أو `null`.
  Future<String?> enrolledUserId() async {
    try {
      final id = await _storage.read(key: _kUser);
      return (id == null || id.isEmpty) ? null : id;
    } catch (err, stack) {
      ErrorLogger.log('biometric.enrolledUserId', err, stack);
      return null;
    }
  }

  /// هل سبق أن رفض المستخدم عرض التفعيل ولا يريد أن يُسأل ثانيةً؟
  Future<bool> declinedPrompt() async {
    try {
      return await _storage.read(key: _kDeclined) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> rememberDeclined() async {
    try {
      await _storage.write(key: _kDeclined, value: '1');
    } catch (err, stack) {
      ErrorLogger.log('biometric.declined', err, stack);
    }
  }

  Future<bool> _prompt(String reason) async {
    try {
      return await _local.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (err, stack) {
      // إلغاءٌ من المستخدم أو قفلٌ مؤقتٌ للمستشعر: ليس خللًا يستحق سجلًّا حرجًا.
      ErrorLogger.log('biometric.prompt.${err.code.name}', err, stack);
      return false;
    } catch (err, stack) {
      ErrorLogger.log('biometric.prompt', err, stack);
      return false;
    }
  }

  /// يفعّل البصمة لـ[user] بعد تأكيدٍ ببصمته. يُستدعى بعد دخولٍ ناجح بكلمة المرور.
  Future<bool> enroll(User user) async {
    if (await availability() != BiometricAvailability.available) return false;
    if (!await _prompt('أكِّد بصمتك لتفعيل الدخول بالبصمة')) return false;
    try {
      await _storage.write(key: _kUser, value: user.id);
      await _storage.write(key: _kHash, value: user.hashHex);
      await _storage.delete(key: _kDeclined);
      return true;
    } catch (err, stack) {
      ErrorLogger.log('biometric.enroll', err, stack);
      return false;
    }
  }

  /// يلغي التفعيل ويمسح الاعتماد.
  Future<void> disable() async {
    try {
      await _storage.delete(key: _kUser);
      await _storage.delete(key: _kHash);
    } catch (err, stack) {
      ErrorLogger.log('biometric.disable', err, stack);
    }
  }

  /// الدخول بالبصمة. يُرجع نتيجةً بنفس شكل [AuthResult] لتعاملها الواجهة كدخولٍ عادي.
  Future<AuthResult> signIn() async {
    const fail = AuthResult(
      status: AuthStatus.badCredentials,
      message: '✖ تعذّر التحقق من البصمة — ادخل بكلمة المرور',
    );
    final id = await enrolledUserId();
    if (id == null) return fail;
    if (!await _prompt('ضع إصبعك للدخول إلى النظام')) return fail;

    final user = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();
    final savedHash = await _storage.read(key: _kHash);
    if (user == null || savedHash != user.hashHex) {
      // الحساب حُذف أو تغيّرت كلمة مروره: الاعتماد القديم لم يعد صالحًا.
      await disable();
      return const AuthResult(
        status: AuthStatus.badCredentials,
        message: '✖ تغيّرت بيانات الحساب — ادخل بكلمة المرور ثم فعّل البصمة من جديد',
      );
    }
    return auth.startSessionFor(user);
  }
}
