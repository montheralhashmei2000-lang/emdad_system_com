import 'package:flutter/material.dart';
import '../imd_tokens.dart';
import 'imd_buttons.dart';
import 'imd_fields.dart';

/// محتوى حوار تصفية عمود: بحثٌ وقائمةُ قيمه المميّزة بمربّعات اختيار. يُرجع
/// `Set<String>` بالقيم المسموحة (كل القيم = لا تصفية).
class ImdColumnFilterBody extends StatefulWidget {
  const ImdColumnFilterBody({super.key, required this.values, required this.selected, required this.shown});

  final List<String> values;

  /// المسموح حاليًّا، أو `null` فكلها مسموحة.
  final Set<String>? selected;

  /// نصّ العرض للقيمة (الفارغة «(فارغ)»).
  final String Function(String) shown;

  @override
  State<ImdColumnFilterBody> createState() => _ImdColumnFilterBodyState();
}

class _ImdColumnFilterBodyState extends State<ImdColumnFilterBody> {
  late final Set<String> _sel = {...(widget.selected ?? widget.values)};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final list = [
      for (final v in widget.values)
        if (_q.isEmpty || widget.shown(v).contains(_q)) v,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _q = v.trim()),
          style: TextStyle(fontSize: 13.5, color: c.text),
          decoration: imdFieldDecoration(context).copyWith(hintText: 'بحث في القيم'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(
            onPressed: () => setState(() => _sel.addAll(list)),
            child: const Text('تحديد الكل', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => setState(() => _sel.removeAll(list)),
            child: const Text('إلغاء الكل', style: TextStyle(fontSize: 12)),
          ),
        ]),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: Text('لا قيم مطابقة', style: TextStyle(color: c.muted, fontSize: 13))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final v = list[i];
                      final on = _sel.contains(v);
                      return InkWell(
                        onTap: () => setState(() => on ? _sel.remove(v) : _sel.add(v)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Checkbox(
                              value: on,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) => setState(() => on ? _sel.remove(v) : _sel.add(v)),
                            ),
                            Expanded(
                              child: Text(widget.shown(v),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: v.isEmpty ? c.muted : c.text)),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          // لا يُسمح بتصفيةٍ فارغة: تُخفي كل الصفوف فلا يعرف المستخدم ما جرى.
          ImdButton(
            label: 'تطبيق',
            onPressed: _sel.isEmpty ? null : () => Navigator.of(context).pop(Set<String>.of(_sel)),
          ),
        ]),
      ],
    );
  }
}
