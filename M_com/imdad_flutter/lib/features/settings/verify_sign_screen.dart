import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/esign.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_scan.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/signatures_repo.dart';
import '../home/home_shell.dart';

/// التحقق من توقيع مستند مطبوع.
///
/// يُمسح رمز QR أسفل الورقة (أو يُلصق نصه)، فيتبيّن أمران: أن التوقيع صادر عن
/// مفتاح معروف، وأن محتوى السند في النظام يطابق ما وُقّع عليه فعلًا. سقوط
/// المطابقة يعني أن الورقة أو السجل تغيّر بعد الاعتماد.
class VerifySignScreen extends StatefulWidget {
  const VerifySignScreen({super.key});

  @override
  State<VerifySignScreen> createState() => _VerifySignScreenState();
}

class _VerifySignScreenState extends State<VerifySignScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  final _token = TextEditingController();

  ESignCheck? _result;
  bool _busy = false;
  bool _docFound = false;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      showImdToast(context, '✖ الصق رمز التوقيع أو امسحه بالكاميرا', error: true);
      return;
    }
    setState(() => _busy = true);

    // المرجع يُقرأ من الرمز نفسه، فيُجلب السند المقابل من هذا الجهاز للمقابلة.
    final ref = ESign.refOf(token);
    final payload =
        ref.isEmpty ? null : await SignaturesRepo(_db).payloadOfStored(ref);
    final result = await ESign(_db).verify(token, payload: payload);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      _docFound = payload != null;
    });
  }

  Future<void> _scan() async {
    final v = await ImdScanner.scan(context);
    if (v == null || v.isEmpty) return;
    imdSetText(_token, v);
    await _verify();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;

    return ImdPage(children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ImdButton.outline(
            label: 'رجوع إلى الإعدادات',
            icon: 'arrow-left',
            small: true,
            onPressed: () => context.read<ImdNav>().go('settings'),
          ),
        ),
      ),
      const ImdPageTitle(
        title: 'التحقق من توقيع مستند',
        icon: 'shield',
        subtitle: 'امسح رمز التحقق أسفل السند المطبوع للتأكد من أنه صادر عن '
            'مفتاح معروف وأن محتواه لم يتغيّر بعد الاعتماد.',
      ),
      ImdPanel(
        title: 'رمز التحقق',
        icon: 'scan',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdLabeled(
            'الرمز المطبوع أسفل السند',
            ImdFld(controller: _token, hint: 'IMD1|…'),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ImdButton(label: 'تحقق', icon: 'check', busy: _busy, onPressed: _verify),
            if (ImdScanner.supported)
              ImdButton.outline(label: 'مسح بالكاميرا', icon: 'camera', onPressed: _scan),
            ImdButton.outline(
              label: 'مسح الحقل',
              icon: 'rotate-ccw',
              onPressed: () => setState(() {
                _token.clear();
                _result = null;
              }),
            ),
          ]),
        ]),
      ),
      if (_result != null) ...[
        const SizedBox(height: 12),
        _ResultPanel(result: _result!, docFound: _docFound, colors: c),
      ],
    ]);
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result, required this.docFound, required this.colors});

  final ESignCheck result;
  final bool docFound;
  final ImdColors colors;

  @override
  Widget build(BuildContext context) {
    final ok = result.ok;
    return ImdPanel(
      title: ok ? 'التوقيع سليم' : 'التوقيع غير مقبول',
      icon: ok ? 'check-circle' : 'alert',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdChipsRow(children: [
          ImdChip(result.reason, tone: ok ? ImdTone.ok : ImdTone.err),
          if (result.keyId.isNotEmpty) ImdChip('المفتاح ${result.keyId}', tone: ImdTone.code),
        ]),
        const SizedBox(height: 10),
        _row('المستند', result.docRef.isEmpty ? '—' : result.docRef),
        _row('الموقِّع', result.signer.isEmpty ? '—' : result.signer),
        _row(
          'وقت التوقيع',
          result.signedAt == null
              ? '—'
              : result.signedAt!.toIso8601String().substring(0, 19).replaceFirst('T', ' '),
        ),
        const SizedBox(height: 8),
        // التمييز مهم: توقيع سليم على مستند لم نجده لا يثبت أن الورقة صحيحة.
        ImdNote(
          !docFound
              ? '⚠ السند غير موجود في هذا الجهاز، فتُحقق من التوقيع وحده دون مقابلة '
                  'محتوى الورقة بما في النظام. زامن الأجهزة ثم أعد التحقق.'
              : ok
                  ? '✔ محتوى السند في هذا الجهاز يطابق ما وُقّع عليه حرفًا بحرف.'
                  : '✖ محتوى السند لا يطابق التوقيع — تغيّرت الورقة أو السجل بعد الاعتماد.',
        ),
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12.5, color: colors.muted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.text)),
          ),
        ]),
      );
}
