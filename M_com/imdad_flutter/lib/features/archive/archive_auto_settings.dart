import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';

/// محتوى إعدادات «الأرشفة التلقائية» — بلا بطاقةٍ خارجية، فيوضع كما هو
/// داخل لوحة الإعدادات وداخل نافذةٍ من شاشة الأرشيف، فيرى المكانان الإعداد
/// نفسه ويحرّره الاثنان.
///
/// **مفصّل بكل عمليةٍ مخزنية**: مفتاحٌ رئيسٌ يهدئ الكل، وكل عمليةٍ من
/// [kArchiveOps] (استلام، صرف، تحويل، مرتجعات، طلبيات إعاشة، جرد، تقارير)
/// بمفتاحها المستقل. تُحفظ التغييرات لحظة التبديل بلا زرّ حفظ.
class ArchiveAutoSettingsCard extends StatefulWidget {
  const ArchiveAutoSettingsCard({super.key});

  @override
  State<ArchiveAutoSettingsCard> createState() => _ArchiveAutoSettingsCardState();
}

class _ArchiveAutoSettingsCardState extends State<ArchiveAutoSettingsCard> {
  late final ArchiveAuto _auto = ArchiveAuto(context.read<AppDatabase>());
  ArchiveAutoSettings? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _auto.load();
    if (mounted) setState(() => _s = s);
  }

  Future<void> _set({bool? enabled, String? op, bool? opValue}) async {
    final s = _s;
    if (s == null) return;
    final next = ArchiveAutoSettings(
      enabled: enabled ?? s.enabled,
      ops: {...s.ops, if (op != null) op: opValue ?? false},
    );
    setState(() => _s = next);
    await _auto.save(next);
  }

  int get _onCount => _s?.ops.values.where((v) => v).length ?? 0;

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const ImdLd('جارٍ تحميل الإعدادات…');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // المفتاح الرئيس: يهدئ الأرشفة كلها دون مسح تفعيلات العمليات —
      // إعادتها تعيد ما كان مفعّلًا بالضبط.
      ImdCheckbox(
        value: s.enabled,
        label: 'تشغيل الأرشفة التلقائية عند الطباعة',
        onChanged: (v) => _set(enabled: v),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ImdChip(
          s.enabled ? 'تعمل الأرشفة تلقائيًّا' : 'الأرشفة التلقائية متوقفة',
          tone: s.enabled ? ImdTone.ok : ImdTone.off,
          icon: s.enabled ? 'check-circle' : 'ban',
        ),
        if (s.enabled)
          ImdChip('${nf(_onCount)} من ${nf(kArchiveOps.length)} عملية مفعّلة', tone: ImdTone.info, icon: 'folder'),
      ]),
      const SizedBox(height: 10),
      // العمليات المفصّلة — تظهر فقط والمفتاح الرئيس يعمل، فلا يُحرّر أحدُ
      // تفصيلاتٍ لا أثر لها.
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.ease,
        alignment: Alignment.topCenter,
        child: s.enabled
            ? ImdGrid(columns: 2, minItemWidth: 250, gap: 4, children: [
                for (final op in kArchiveOps)
                  ImdCheckbox(
                    value: s.ops[op.$1] ?? false,
                    label: op.$2,
                    onChanged: (v) => _set(op: op.$1, opValue: v),
                  ),
              ])
            : const SizedBox.shrink(),
      ),
      const SizedBox(height: 8),
      const ImdNote('تُؤرشف نسخة PDF مطابقة لما طُبع فعلًا لحظة إتمام الطباعة — بنفس بايتاتها لا بإعادة توليدها — '
          'وتظهر في شاشة «الأرشيف الإلكتروني» بشارة «تلقائي» مع نوع العملية. '
          'إعادة طباعة السند نفسه تُحدّث نسخته في الأرشيف ولا تُكرّرها. '
          'تُحفظ التغييرات لحظة التبديل، وتسري على كل من يطبع من هذا الجهاز.'),
    ]);
  }
}
