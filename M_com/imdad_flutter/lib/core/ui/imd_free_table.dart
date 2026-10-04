import 'package:flutter/material.dart';

import '../../domain/free_table.dart';
import 'imd_form.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

/// محرر جدولٍ حر: يضيف المستخدم عمودًا بجانب أي عمود، ويسمّيه بنفسه، ويسحب
/// حافة العمود لتكبيره أو تصغيره، ويضيف الصفوف ويحذفها.
///
/// لا يحمل حالةً خارجية: يُستلم [initial] مرةً واحدة، وكل تعديلٍ يُبلَّغ به
/// [onChanged] بجدولٍ كامل. لإعادة تهيئته من الخارج يُغيَّر `key`.
class ImdFreeTableEditor extends StatefulWidget {
  const ImdFreeTableEditor({super.key, required this.initial, required this.onChanged});

  final FreeTable initial;
  final ValueChanged<FreeTable> onChanged;

  @override
  State<ImdFreeTableEditor> createState() => _ImdFreeTableEditorState();
}

class _Col {
  _Col(String title, this.weight) : title = TextEditingController(text: title);

  final TextEditingController title;
  double weight;
  final key = UniqueKey();
}

class _Row {
  _Row(List<String> cells) : cells = [for (final c in cells) TextEditingController(text: c)];

  final List<TextEditingController> cells;
  final key = UniqueKey();
}

class _ImdFreeTableEditorState extends State<ImdFreeTableEditor> {
  static const double _numW = 40; // عمود «م»
  static const double _actW = 44; // عمود حذف الصف
  static const double _minCol = 84;
  static const double _handle = 10;

  late final List<_Col> _cols = [for (final c in widget.initial.cols) _Col(c.title, c.weight)];
  late final List<_Row> _rows = [
    for (final r in widget.initial.rows) _Row([for (var i = 0; i < _cols.length; i++) i < r.length ? r[i] : '']),
  ];
  String _title = '';

  @override
  void initState() {
    super.initState();
    _title = widget.initial.title;
    if (_rows.isEmpty) _rows.add(_Row(List.filled(_cols.length, '')));
  }

  @override
  void dispose() {
    for (final c in _cols) {
      c.title.dispose();
    }
    for (final r in _rows) {
      for (final c in r.cells) {
        c.dispose();
      }
    }
    super.dispose();
  }

  FreeTable _table() => FreeTable(
        title: _title,
        cols: [for (final c in _cols) FreeCol(c.title.text.trim(), c.weight)],
        rows: [for (final r in _rows) [for (final c in r.cells) c.text]],
      );

  void _emit() => widget.onChanged(_table());

  void _addColAfter(int i) {
    setState(() {
      _cols.insert(i + 1, _Col('', 5));
      for (final r in _rows) {
        r.cells.insert(i + 1, TextEditingController());
      }
    });
    _emit();
  }

  void _removeCol(int i) {
    if (_cols.length <= 1) return;
    setState(() {
      _cols.removeAt(i).title.dispose();
      for (final r in _rows) {
        r.cells.removeAt(i).dispose();
      }
    });
    _emit();
  }

  /// سحب الحافة بين العمود [i] وجاره [i]+1: يكبر أحدهما بقدر ما يصغر الآخر.
  void _drag(int i, double dx, double pxPerWeight) {
    if (pxPerWeight <= 0) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dw = (rtl ? -dx : dx) / pxPerWeight;
    final minW = _minCol / pxPerWeight;
    final a = _cols[i], b = _cols[i + 1];
    final na = (a.weight + dw).clamp(minW, a.weight + b.weight - minW);
    setState(() {
      b.weight = a.weight + b.weight - na;
      a.weight = na;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return LayoutBuilder(builder: (context, box) {
      const fixed = _numW + _actW;
      final minTotal = fixed + _cols.length * (_minCol + _handle);
      final total = box.maxWidth.isFinite && box.maxWidth > minTotal ? box.maxWidth : minTotal;
      final weightSum = _cols.fold<double>(0, (s, e) => s + e.weight);
      final avail = total - fixed;
      final pxPerWeight = avail / weightSum;
      final line = BorderSide(color: c.line);

      Widget header(int i) {
        final col = _cols[i];
        return SizedBox(
          width: col.weight * pxPerWeight,
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ImdFld(controller: col.title, hint: 'اسم العمود', onChanged: (_) => _emit()),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    ImdIconButton(icon: 'plus', tooltip: 'إضافة عمود بجانب هذا العمود', onPressed: () => _addColAfter(i)),
                    if (_cols.length > 1)
                      ImdIconButton(icon: 'trash', tooltip: 'حذف العمود', kind: ImdBtnKind.danger, onPressed: () => _removeCol(i)),
                  ]),
                ]),
              ),
            ),
            // مقبض السحب بين هذا العمود وجاره.
            if (i < _cols.length - 1)
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) => _drag(i, d.delta.dx, pxPerWeight),
                  child: Container(
                    width: _handle,
                    height: 56,
                    alignment: Alignment.center,
                    child: Container(width: 3, height: 40, decoration: BoxDecoration(color: c.ring, borderRadius: BorderRadius.circular(2))),
                  ),
                ),
              ),
          ]),
        );
      }

      final content = SizedBox(
        width: total,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: _numW, child: Center(child: Text('م', style: TextStyle(fontWeight: FontWeight.w700, color: c.muted)))),
            for (var i = 0; i < _cols.length; i++) header(i),
            const SizedBox(width: _actW),
          ]),
          const SizedBox(height: 4),
          for (final (ri, r) in _rows.indexed)
            Container(
              key: r.key,
              decoration: BoxDecoration(border: Border(top: line)),
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                SizedBox(width: _numW, child: Center(child: Text('${ri + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: c.muted)))),
                for (var i = 0; i < _cols.length; i++)
                  SizedBox(
                    width: _cols[i].weight * pxPerWeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ImdFld(controller: r.cells[i], onChanged: (_) => _emit()),
                    ),
                  ),
                SizedBox(
                  width: _actW,
                  child: _rows.length > 1
                      ? ImdIconButton(
                          icon: 'trash',
                          tooltip: 'حذف الصف',
                          kind: ImdBtnKind.danger,
                          onPressed: () {
                            setState(() {
                              final x = _rows.removeAt(ri);
                              for (final cc in x.cells) {
                                cc.dispose();
                              }
                            });
                            _emit();
                          })
                      : const SizedBox.shrink(),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ImdButton.outline(
              label: 'إضافة صف',
              icon: 'plus',
              small: true,
              onPressed: () {
                setState(() => _rows.add(_Row(List.filled(_cols.length, ''))));
                _emit();
              },
            ),
          ),
        ]),
      );

      // الجدول العريض يُمرَّر أفقيًّا في الشاشة الضيّقة بدل أن يفيض.
      return total > box.maxWidth
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: content)
          : content;
    });
  }
}
