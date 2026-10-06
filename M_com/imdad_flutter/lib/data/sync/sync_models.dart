import 'sync_crypto.dart';
import 'sync_marks.dart';

/// مزامنة الأجهزة عبر الشبكة المحلية — بلا إنترنت ولا خادم خارجي:
/// جهاز يعمل **مستقبِلًا** فيفتح منفذًا على
/// الشبكة، وبقية الأجهزة ترسل إليه بياناتها أو تسحب منه.
///
/// الأمان (انظر [SyncSession]): المستقبِل يعرض رمز اقتران من ٨ أحرف، ولا يُقبل
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
  const SyncResult({required this.ok, this.message = '', this.records = 0, this.upTo = 0, bool? failed})
      : failed = failed ?? !ok;

  final bool ok;

  /// هل هو **فشل** يُنبَّه إليه؟ غير [ok] لا يعني فشلًا دائمًا (مثل: لا جهاز موثوق
  /// بعد). الواجهة تقرأ هذا الحقل لا نصَّ [message].
  final bool failed;
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
