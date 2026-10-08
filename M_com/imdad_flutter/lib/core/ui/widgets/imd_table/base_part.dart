part of '../imd_table.dart';

/// حالة الجدول: الحقول وتزامن تمرير النسختين.
///
/// نقلٌ حرفيّ من `_ImdTableState` — خليطٌ في المكتبة نفسها، فواجهة
/// [ImdTable] العامة لم تتغيّر.
mixin _ImdTableBase on State<ImdTable> {
  int _hover = -1;
  int _headerHover = -1;
  int _page = 0;
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  /// متحكّم تمرير نسخة العمود المثبَّت — يُزامَن مع [_vScroll].
  final _vScroll2 = ScrollController();
  final _find = TextEditingController();
  String _findQ = '';

  /// القيم المسموحة لكل عمود مصفّى (فهرس العمود ← نصوص القيم).
  final Map<int, Set<String>> _filters = {};

  /// العمود المجمَّع عليه، أو `null` فلا تجميع.
  int? _groupBy;

  /// قيم المجموعات المطويّة.
  final Set<String> _collapsed = {};

  ImdRecordSink? _sink;

  bool get _tools => widget.values != null && widget.columns.isNotEmpty && (widget.filterable || widget.groupable);

  /// يطابق تمرير النسختين رأسيًّا (الأصل والعمود المثبَّت).
  void _syncV(ScrollController from, ScrollController to) {
    if (!from.hasClients || !to.hasClients) return;
    final o = from.offset;
    if ((to.offset - o).abs() < .5) return;
    to.jumpTo(o.clamp(to.position.minScrollExtent, to.position.maxScrollExtent).toDouble());
  }
}
