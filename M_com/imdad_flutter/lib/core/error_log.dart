import 'package:flutter/foundation.dart';

/// خطأٌ مسجَّل.
class LoggedError {
  LoggedError({
    required this.source,
    required this.message,
    required this.type,
    required this.critical,
    required this.at,
    this.stack,
  });

  /// موضع الحدوث بصيغة `مجال.عملية` (مثل `archive.cable`).
  final String source;
  final String message;
  final String type;
  final bool critical;
  final DateTime at;
  final StackTrace? stack;

  /// كم مرةً تكرر الخطأ نفسه داخل نافذة التكرار فلم يُسجَّل ثانيةً.
  int suppressed = 0;

  @override
  String toString() => '[$source] $type: $message';
}

/// سجلّ الأخطاء المبتلعة.
///
/// **لماذا ليس [AuditRepo] وحده:** كثيرٌ من المواضع أدنى من قاعدة البيانات
/// (فتح الملف المشفّر قبل وجود القاعدة، وكتابة سجل التدقيق نفسه)، أو بلا
/// قاعدة في متناولها (نماذج الطباعة، مجال النطاق). فالمسجِّل بلا تبعية:
/// يكتب في سجل المنصة ويحفظ آخر [capacity] خطأً في الذاكرة للتشخيص، وتُحقن
/// له عند الإقلاع قناتان: [sink] لحفظ الحرجة في سجل التدقيق، و[userNotifier]
/// لإبلاغ المستخدم.
///
/// **تصنيف الأخطاء:**
/// - [critical]: ما يُفقد به عملٌ أو أثر مساءلة (فشل الأرشفة بعد الطباعة، تعذّر
///   كتابة سجل التدقيق، نطاق مستودعات تالف). تُحفظ في سجل التدقيق، ويُبلَّغ
///   المستخدم إن مُرِّرت [userMessage].
/// - [log]: الثانوية (ملف مؤقت لم يُحذف، شعار لم يُحمَّل). سجل المنصة والذاكرة فقط.
/// - **المتوقعة** (مقبس أغلقه الطرف الآخر، حزمة اكتشاف مشوّهة من الشبكة) لا
///   تُسجَّل: يكفي تعليقٌ عند موضعها يشرح لماذا هي متوقعة.
class ErrorLogger {
  const ErrorLogger._();

  /// أقصى ما يحتفظ به المسجِّل في الذاكرة.
  static const int capacity = 200;

  /// الخطأ نفسه (الموضع + النوع) لا يُسجَّل إلا مرةً في هذه المدة — تحصينًا من
  /// طوفانٍ حين يتكرر عطلٌ في مسارٍ يُستدعى مع كل رسم للشاشة.
  static const Duration dedupeWindow = Duration(seconds: 60);

  static final List<LoggedError> _recent = [];
  static final Map<String, LoggedError> _lastByKey = {};

  /// آخر الأخطاء، الأحدث أولًا.
  static List<LoggedError> get recent => List.unmodifiable(_recent.reversed);

  /// يحفظ الخطأ الحرج في سجل التدقيق. يُحقن من `main` (وهو يتجاوز مصدر `audit.*`
  /// فلا يُستدعى المسجِّل من داخل كتابة سجل التدقيق نفسها).
  static Future<void> Function(LoggedError error)? sink;

  /// يُبلغ المستخدم برسالة عربية (SnackBar). يُحقن من `main`.
  static void Function(String message)? userNotifier;

  /// خطأ ثانوي: سجل المنصة والذاكرة.
  static void log(String source, Object error, [StackTrace? stack]) =>
      _record(source, error, stack, critical: false, userMessage: null);

  /// خطأ حرج: يُحفظ في سجل التدقيق، ويُبلَّغ المستخدم إن وُجدت [userMessage].
  static void critical(String source, Object error, {StackTrace? stack, String? userMessage}) =>
      _record(source, error, stack, critical: true, userMessage: userMessage);

  static void _record(
    String source,
    Object error,
    StackTrace? stack, {
    required bool critical,
    required String? userMessage,
  }) {
    final now = DateTime.now();
    final key = '$source|${error.runtimeType}|$critical';
    final prev = _lastByKey[key];
    if (prev != null && now.difference(prev.at) < dedupeWindow) {
      prev.suppressed++;
      return;
    }

    final entry = LoggedError(
      source: source,
      message: '$error',
      type: '${error.runtimeType}',
      critical: critical,
      at: now,
      stack: stack,
    );
    _lastByKey[key] = entry;
    _recent.add(entry);
    if (_recent.length > capacity) _recent.removeRange(0, _recent.length - capacity);

    debugPrint('${critical ? '✖ خطأ حرج' : '⚠ خطأ'} $entry');
    if (!critical) return;

    // الحفظ والإبلاغ لا يُسقطان المسار الأصلي أبدًا: المسجِّل نفسه لا يرمي.
    final persist = sink;
    if (persist != null && !source.startsWith('audit.')) {
      try {
        persist(entry).catchError((Object e) => debugPrint('ErrorLogger.sink: $e'));
      } catch (e) {
        debugPrint('ErrorLogger.sink: $e');
      }
    }
    if (userMessage != null) {
      try {
        userNotifier?.call(userMessage);
      } catch (e) {
        debugPrint('ErrorLogger.userNotifier: $e');
      }
    }
  }

  /// للاختبارات: يصفّر الذاكرة والتكرار والقنوات.
  @visibleForTesting
  static void reset() {
    _recent.clear();
    _lastByKey.clear();
    sink = null;
    userNotifier = null;
  }
}
