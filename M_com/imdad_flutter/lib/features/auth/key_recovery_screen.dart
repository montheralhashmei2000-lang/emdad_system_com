import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/backup/key_escrow.dart';
import '../../data/db/db_cipher.dart';
import '../../data/migration/backup_crypto.dart';

/// شاشة ما قبل القاعدة: مفتاح قاعدة البيانات غائبٌ أو لا يُقرأ والقاعدة
/// المشفّرة قائمة (البند H-2).
///
/// كان التطبيق يولّد مفتاحًا جديدًا في هذه الحال فلا تُفتح القاعدة أبدًا، ويضيع
/// أي أملٍ في استرداد القديم. الآن يقف هنا ويعرض طريقين صريحين:
/// • **الاسترداد بملف USB** (`KeyEscrow`) بكلمة مرور المالك — يُتحقق أن المفتاح
///   يفتح قاعدة هذا الجهاز قبل حفظه.
/// • **بدء قاعدة جديدة** — تُنحّى القديمة باسمٍ مختوم ولا تُحذف.
///
/// لا قاعدة ولا جلسة هنا، فلا مزوّدات: تطبيقٌ مستقل يُستبدل بالتطبيق الكامل
/// عند [onResolved].
class KeyRecoveryApp extends StatelessWidget {
  const KeyRecoveryApp({super.key, required this.problem, required this.onResolved});

  final DbKeyMissing problem;
  final Future<void> Function() onResolved;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'نظام الإمداد والتموين',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: KeyRecoveryScreen(problem: problem, onResolved: onResolved),
      );
}

class KeyRecoveryScreen extends StatefulWidget {
  const KeyRecoveryScreen({super.key, required this.problem, required this.onResolved});

  final DbKeyMissing problem;
  final Future<void> Function() onResolved;

  @override
  State<KeyRecoveryScreen> createState() => _KeyRecoveryScreenState();
}

class _KeyRecoveryScreenState extends State<KeyRecoveryScreen> {
  final _password = TextEditingController();
  Uint8List? _file;
  String _fileName = '';
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final f = res?.files.singleOrNull;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (!mounted || bytes == null) return;
    setState(() {
      _file = bytes;
      _fileName = f.name;
      _error = '';
    });
  }

  Future<void> _restore() async {
    final bytes = _file;
    if (bytes == null) return setState(() => _error = '✖ اختر ملف الاسترداد أولًا');
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final escrow = KeyEscrow.open(bytes, _password.text);
      final db = await DbCipher.defaultFile();
      if (!DbCipher.keyOpens(db, escrow.keyHex)) {
        throw BackupError('المفتاح في الملف لا يفتح قاعدة هذا الجهاز — الملف لجهاز «${escrow.deviceId}»');
      }
      await DbCipher.storeKey(escrow.keyHex);
      await widget.onResolved();
    } on BackupError catch (e) {
      if (mounted) setState(() => _error = '✖ ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _error = '✖ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startFresh() async {
    final ok = await imdConfirm(
      context,
      'تُنحّى قاعدة البيانات الحالية جانبًا (لا تُحذف) ويبدأ الجهاز بقاعدةٍ فارغة: '
      'يلزمه تفعيلٌ من جديد، ثم استعادة نسخةٍ احتياطية أو المزامنة مع جهاز الإدارة.\n\n'
      'إن عُثر على ملف الاسترداد لاحقًا أمكن فتح القاعدة المنحّاة. متابعة؟',
      ok: 'بدء قاعدة جديدة',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final db = await DbCipher.defaultFile();
      if (db.existsSync()) DbCipher.setAsideLocked(db);
      if (widget.problem.unreadable) await DbCipher.forgetKey();
      await widget.onResolved();
    } catch (e) {
      if (mounted) setState(() => _error = '✖ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ImdPanel(
                  title: 'مفتاح قاعدة البيانات غير متاح',
                  icon: 'lock',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const ImdNote(
                      'قاعدة البيانات على هذا الجهاز مشفّرة، ومفتاحها لم يعد في مخزن أسرار النظام '
                      '(إعادة تعيين حساب ويندوز، أو عطلٌ في مخزن أندرويد، أو نقل مجلد البيانات). '
                      'لم يُولَّد مفتاحٌ جديد حتى لا تُقفل القاعدة نهائيًّا.',
                    ),
                    const SizedBox(height: 8),
                    Text(widget.problem.message, style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                ),
                const SizedBox(height: 12),
                ImdPanel(
                  title: 'الاسترداد بملف USB',
                  icon: 'key',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const ImdNote('ملف الاسترداد (.${KeyEscrow.extension}) يحفظه المالك من الإعدادات ← النسخ '
                        'الاحتياطي، وكلمة مروره عند المالك.'),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      ImdButton.outline(label: 'اختيار الملف', icon: 'upload', onPressed: _busy ? null : _pick),
                      if (_fileName.isNotEmpty) ImdChip(_fileName, tone: ImdTone.info),
                    ]),
                    const SizedBox(height: 10),
                    ImdLabeled('كلمة مرور الملف', ImdFld(controller: _password, obscure: true)),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ImdButton(label: 'استرداد المفتاح', icon: 'check', busy: _busy, onPressed: _restore),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                ImdPanel(
                  title: 'لا يوجد ملف استرداد',
                  icon: 'alert',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const ImdNote('تُنحّى القاعدة الحالية جانبًا ويبدأ الجهاز من جديد. البيانات '
                        'المزامَنة تعود من جهاز الإدارة، أو تُستعاد نسخةٌ احتياطية.'),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ImdButton(
                        label: 'بدء قاعدة جديدة',
                        icon: 'refresh',
                        kind: ImdBtnKind.danger,
                        onPressed: _busy ? null : _startFresh,
                      ),
                    ),
                  ]),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
