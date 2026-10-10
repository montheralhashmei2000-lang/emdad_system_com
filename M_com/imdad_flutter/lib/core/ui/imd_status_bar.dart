import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'imd_format.dart';
import 'imd_icon.dart';
import 'imd_tokens.dart';

/// عدّاد السجلات التي تعرضها الصفحة الحالية — يغذّيه كل [ImdTable] ويقرؤه
/// [ImdStatusBar].
///
/// **لماذا مجمَّعٌ لا قيمةٌ واحدة:** الصفحة قد تضمّ أكثر من جدول (مسودّاتٌ
/// وسندات)، وكلٌّ يُبلّغ عن نفسه بمفتاحه. العدد المعروض للجدول **الأكبر** —
/// هو جدول الصفحة الرئيسي عادةً — فلا يقفز الرقم بين جدولين بحسب من أعاد البناء
/// آخرًا.
class ImdRecordSink extends ChangeNotifier {
  final Map<Object, ({int shown, int total})> _counts = {};

  /// المعروض بعد التصفية، والإجمالي قبلها — للجدول الأكبر.
  ({int shown, int total})? get current {
    ({int shown, int total})? best;
    for (final v in _counts.values) {
      if (best == null || v.total > best.total) best = v;
    }
    return best;
  }

  void report(Object owner, {required int shown, required int total}) {
    if (_disposed) return;
    final old = _counts[owner];
    if (old != null && old.shown == shown && old.total == total) return;
    _counts[owner] = (shown: shown, total: total);
    notifyListeners();
  }

  void remove(Object owner) {
    // تُنادى من `dispose()` والشجرة مقفلة: الإشعار الفوري يُعيد بناء الشريط
    // أثناء التفكيك فيُلقي «setState() called when widget tree was locked».
    // فيُؤجَّل لما بعد الإطار.
    if (_counts.remove(owner) != null) _notifyAfterFrame();
  }

  bool _disposed = false;
  bool _pending = false;

  void _notifyAfterFrame() {
    if (_pending || _disposed) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// يربط جداول صفحةٍ بعدّادها. القشرة تلفّ كل صفحةٍ مفتوحة بنطاقٍ خاص بها، فلا
/// تُلوِّث جداولُ صفحةٍ مخفيّةٍ عدّادَ الصفحة الظاهرة.
class ImdRecordScope extends InheritedWidget {
  const ImdRecordScope({super.key, required this.sink, required super.child});

  final ImdRecordSink sink;

  static ImdRecordSink? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ImdRecordScope>()?.sink;

  @override
  bool updateShouldNotify(ImdRecordScope old) => old.sink != sink;
}

/// الشريط السفلي لسطح المكتب: الوقت، حالة الاتصال، وعدد السجلات. الكثافة والنمط
/// الكلاسيكي في الإعدادات ▸ «المظهر والعرض» وحدها.
///
/// عرضٌ فقط — لا منطق مزامنةٍ هنا: [connection] تأتيه جاهزةً من القشرة التي
/// تملك `AutoSyncService`.
class ImdStatusBar extends StatefulWidget {
  const ImdStatusBar({
    super.key,
    required this.connection,
    required this.connectionOk,
    this.records,
    this.trailing = const [],
    this.onConnectionTap,
  });

  /// نقر حالة الاتصال (يفتح شاشة المزامنة).
  final VoidCallback? onConnectionTap;

  /// نصّ حالة الاتصال/المزامنة.
  final String connection;

  /// `true` أخضر، `false` تنبيه (فشل)، والرمادي لحالة الإيقاف يقرّره [connection].
  final bool? connectionOk;

  /// عدّاد الصفحة الظاهرة، أو `null` فلا يُعرض عدد.
  final ImdRecordSink? records;

  /// عناصر إضافية في طرف الشريط.
  final List<Widget> trailing;

  @override
  State<ImdStatusBar> createState() => _ImdStatusBarState();
}

class _ImdStatusBarState extends State<ImdStatusBar> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // دقيقةٌ تكفي: الشريط لا يعرض ثواني، ومؤقّتٌ كل ثانية يُعيد رسمه بلا فائدة.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Widget _sep(ImdColors c) => Container(width: 1, height: 14, margin: const EdgeInsets.symmetric(horizontal: 12), color: c.line);

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final style = TextStyle(fontSize: 12, color: c.muted, height: 1.2);
    final dot = widget.connectionOk == null ? c.faint : (widget.connectionOk! ? c.success : c.danger);
    final time = DateFormat('HH:mm').format(_now);
    final date = DateFormat('yyyy/MM/dd').format(_now);

    final sink = widget.records;
    final records = sink == null
        ? const SizedBox.shrink()
        : ListenableBuilder(
            listenable: sink,
            builder: (context, _) {
              final cur = sink.current;
              if (cur == null) return const SizedBox.shrink();
              final text = cur.shown == cur.total
                  ? 'السجلات: ${nf(cur.total)}'
                  : 'السجلات: ${nf(cur.shown)} من ${nf(cur.total)}';
              return Row(mainAxisSize: MainAxisSize.min, children: [
                _sep(c),
                ImdIcon('clipboard', size: 13, color: c.muted),
                const SizedBox(width: 6),
                Text(text, style: style.copyWith(color: c.text2, fontWeight: FontWeight.w600)),
              ]);
            },
          );

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          ImdIcon('clock', size: 13, color: c.muted),
          const SizedBox(width: 6),
          Text('$time  ·  $date', style: style),
          _sep(c),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onConnectionTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(widget.connection, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          ),
          records,
          const Spacer(),
          ...widget.trailing,
        ],
      ),
    );
  }
}
