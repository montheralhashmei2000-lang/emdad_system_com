import 'package:flutter/material.dart';

import '../../core/print/barcode_labels.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_widgets.dart';

/// إعداد «حجم ملصق الباركود» في الإعدادات ▸ الطباعة. محلي لكل جهاز
/// ([LabelSize.prefsKey])؛ الأحجام الجاهزة تُحفظ لحظة اختيارها، و«مخصص»
/// يُحفظ بزرّه بعد فحص العرض والارتفاع.
class LabelSizePanel extends StatefulWidget {
  const LabelSizePanel({super.key});

  @override
  State<LabelSizePanel> createState() => _LabelSizePanelState();
}

class _LabelSizePanelState extends State<LabelSizePanel> {
  static const _custom = 'custom';

  final _w = TextEditingController();
  final _h = TextEditingController();
  LabelSize? _size;
  String _choice = '';
  String? _err;

  static String _keyOf(LabelSize s) => '${s.widthMm}x${s.heightMm}';

  @override
  void initState() {
    super.initState();
    LabelSize.load().then((s) {
      if (!mounted) return;
      setState(() {
        _size = s;
        _choice = s.isPreset ? _keyOf(s) : _custom;
        imdSetText(_w, LabelSize.mm(s.widthMm));
        imdSetText(_h, LabelSize.mm(s.heightMm));
      });
    });
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  Future<void> _apply(LabelSize s) async {
    await LabelSize.save(s);
    if (!mounted) return;
    setState(() {
      _size = s;
      _err = null;
    });
    showImdToast(context, '✔ حجم الملصق: ${s.label}');
  }

  Future<void> _pick(String? v) async {
    if (v == null) return;
    setState(() => _choice = v);
    if (v == _custom) return;
    await _apply(LabelSize.presets.firstWhere((p) => _keyOf(p) == v));
  }

  Future<void> _saveCustom() async {
    final w = double.tryParse(_w.text.trim()), h = double.tryParse(_h.text.trim());
    if (w == null || h == null || !LabelSize.valid(w, h)) {
      setState(() => _err = 'العرض والارتفاع بين ${LabelSize.mm(LabelSize.minMm)} و${LabelSize.mm(LabelSize.maxMm)} مم');
      return;
    }
    await _apply(LabelSize(w, h));
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    if (size == null) return const ImdLd('جارٍ التحميل…');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdNote('مقاس الملصق الواحد عند طباعة ملصقات الباركود من شاشة الأصناف — صفحةٌ لكل ملصق. '
          'يُحفظ على هذا الجهاز وحده. الحالي: ${size.label}'),
      const SizedBox(height: 10),
      ImdLabeled(
        'حجم ملصق الباركود',
        ImdSelect<String>(
          value: _choice,
          title: 'حجم ملصق الباركود',
          items: [
            for (final p in LabelSize.presets) (_keyOf(p), p.label),
            (_custom, 'مخصص'),
          ],
          onChanged: _pick,
        ),
      ),
      if (_choice == _custom) ...[
        const SizedBox(height: 10),
        ImdF2(children: [
          ImdLabeled('العرض (مم)', ImdFld(controller: _w, number: true, errorText: _err)),
          ImdLabeled('الارتفاع (مم)', ImdFld(controller: _h, number: true)),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ImdButton(label: 'حفظ الحجم المخصص', icon: 'check', small: true, onPressed: _saveCustom),
        ),
      ],
    ]);
  }
}
