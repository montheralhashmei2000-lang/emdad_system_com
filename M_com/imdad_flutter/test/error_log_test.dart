import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/error_log.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/audit_repo.dart';

/// الأخطاء المبتلعة تُسجَّل: الثانوية في الذاكرة والمنصة، والحرجة في سجل
/// التدقيق مع إبلاغ المستخدم، دون أن يُسقط المسجِّلُ المسارَ الأصلي.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ErrorLogger.reset);
  tearDown(ErrorLogger.reset);

  test('خطأ ثانوي: يُحفظ في الذاكرة ولا يصل إلى سجل التدقيق ولا المستخدم', () {
    final persisted = <LoggedError>[];
    final shown = <String>[];
    ErrorLogger.sink = (e) async => persisted.add(e);
    ErrorLogger.userNotifier = shown.add;

    ErrorLogger.log('cable.attachmentDelete', const FormatException('x'));

    expect(ErrorLogger.recent.single.source, 'cable.attachmentDelete');
    expect(ErrorLogger.recent.single.critical, isFalse);
    expect(persisted, isEmpty);
    expect(shown, isEmpty);
  });

  test('خطأ حرج: يُحفظ ويُبلَّغ به المستخدم', () {
    final persisted = <LoggedError>[];
    final shown = <String>[];
    ErrorLogger.sink = (e) async => persisted.add(e);
    ErrorLogger.userNotifier = shown.add;

    ErrorLogger.critical('archive.cable', StateError('disk'), userMessage: 'تعذّرت الأرشفة');

    expect(persisted.single.source, 'archive.cable');
    expect(shown, ['تعذّرت الأرشفة']);
  });

  test('حرج بلا رسالة: يُحفظ ولا يُزعَج المستخدم', () {
    final shown = <String>[];
    final persisted = <LoggedError>[];
    ErrorLogger.sink = (e) async => persisted.add(e);
    ErrorLogger.userNotifier = shown.add;
    ErrorLogger.critical('users.scopeJson', const FormatException('bad'));
    expect(persisted, hasLength(1));
    expect(shown, isEmpty);
  });

  test('الخطأ نفسه المتكرر يُسجَّل مرة داخل النافذة ويُعدّ المكبوت', () {
    for (var i = 0; i < 5; i++) {
      ErrorLogger.log('catalog.itemUnits', const FormatException('bad json'));
    }
    expect(ErrorLogger.recent, hasLength(1));
    expect(ErrorLogger.recent.single.suppressed, 4);
    // موضعٌ آخر ليس تكرارًا.
    ErrorLogger.log('catalog.campIds', const FormatException('bad json'));
    expect(ErrorLogger.recent, hasLength(2));
  });

  test('الذاكرة محدودة السعة', () {
    for (var i = 0; i < ErrorLogger.capacity + 30; i++) {
      ErrorLogger.log('src.$i', const FormatException('x'));
    }
    expect(ErrorLogger.recent, hasLength(ErrorLogger.capacity));
    expect(ErrorLogger.recent.first.source, 'src.${ErrorLogger.capacity + 29}', reason: 'الأحدث أولًا');
  });

  test('المسجِّل لا يُسقط المسار الأصلي ولو رمى الحافظ أو المُبلِّغ', () {
    ErrorLogger.sink = (e) => throw StateError('sink down');
    ErrorLogger.userNotifier = (m) => throw StateError('no ui');
    expect(() => ErrorLogger.critical('a.b', Exception('x'), userMessage: 'm'), returnsNormally);

    ErrorLogger.sink = (e) => Future<void>.error(StateError('async sink down'));
    expect(() => ErrorLogger.critical('a.c', Exception('y')), returnsNormally);
  });

  test('مصدر audit.* لا يمرّ بالحافظ — منعًا للدوران حين يفشل سجل التدقيق نفسه', () {
    var calls = 0;
    ErrorLogger.sink = (e) async => calls++;
    ErrorLogger.critical('audit.write', Exception('db closed'));
    expect(calls, 0);
    expect(ErrorLogger.recent.single.source, 'audit.write');
  });

  test('فشل كتابة سجل التدقيق لا يرمي ويُسجَّل خطأً حرجًا', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    await db.close();

    await expectLater(AuditRepo(db).write('x', 'نظام', 'y'), completes);

    expect(ErrorLogger.recent.map((e) => e.source), contains('audit.write'));
    expect(ErrorLogger.recent.firstWhere((e) => e.source == 'audit.write').critical, isTrue);
  });
}
