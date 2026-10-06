import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/error_log.dart';

/// مصائد الأخطاء العامة: استثناءات الإطار والمهام غير المتزامنة تصل إلى
/// [ErrorLogger] (ومنه إلى سجل التدقيق) بدل أن تمرّ بلا أثر.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final savedFlutter = FlutterError.onError;
  final savedPlatform = PlatformDispatcher.instance.onError;

  setUp(ErrorLogger.reset);
  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedPlatform;
    ErrorLogger.reset();
  });

  test('installGlobalHandlers: خطأ الإطار يُسجَّل حرجًا', () {
    final sunk = <LoggedError>[];
    ErrorLogger.sink = (e) async => sunk.add(e);
    ErrorLogger.installGlobalHandlers();

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom-framework'), stack: StackTrace.current));

    expect(sunk.single.source, 'flutter.framework');
    expect(sunk.single.critical, isTrue);
    expect(sunk.single.message, contains('boom-framework'));
  });

  test('installGlobalHandlers: استثناء غير معالَج يُسجَّل ويُعدّ معالَجًا', () {
    final sunk = <LoggedError>[];
    ErrorLogger.sink = (e) async => sunk.add(e);
    ErrorLogger.installGlobalHandlers();

    final handled = PlatformDispatcher.instance.onError!(StateError('boom-async'), StackTrace.current);

    expect(handled, isTrue);
    expect(sunk.single.source, 'platform.uncaught');
    expect(sunk.single.message, contains('boom-async'));
  });
}
