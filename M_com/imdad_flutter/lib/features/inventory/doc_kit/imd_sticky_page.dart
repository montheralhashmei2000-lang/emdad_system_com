import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../core/ui/imd_tokens.dart';
import '../../../core/ui/imd_widgets.dart';


/// شريط الإجراءات (يلتصق بأسفل الشاشة عبر `ImdStickyPage`).
class ImdStickyActions extends StatelessWidget {
  const ImdStickyActions({super.key, required this.children, this.caption});
  final List<Widget> children;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: .96),
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: c.shadowSm,
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: children),
            // الحشوة التلقائية تدفع التنبيه إلى الطرف الآخر من السطر.
            if (caption != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(caption!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: c.muted)),
                ),
              ),
          ]),
    );
  }
}


/// صفحة بمحتوى قابل للتمرير وشريط إجراءات ملتصق بالأسفل كـ `position: sticky; bottom: 12px`:
/// يظهر ملتصقًا ما دام موضعه الطبيعي تحت حافة الشاشة، ويعود لمكانه عند الوصول إليه.
class ImdStickyPage extends StatefulWidget {
  const ImdStickyPage(
      {super.key,
      required this.children,
      required this.sticky,
      this.after = const []});
  final List<Widget> children;
  final Widget sticky;

  /// عناصر بعد الشريط (نادرًا).
  final List<Widget> after;

  @override
  State<ImdStickyPage> createState() => _ImdStickyPageState();
}


class _ImdStickyPageState extends State<ImdStickyPage> {
  final _scroll = ScrollController();
  final _inlineKey = GlobalKey();
  final _viewKey = GlobalKey();
  bool _pinned = false;
  double _stickyHeight = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// القياس ممنوع أثناء مرحلة التخطيط (إشعار تغيّر الحجم يصل داخلها)،
  /// فيؤجَّل إلى ما بعد الإطار وإلا رمى الإطار «RenderBox.size accessed beyond scope».
  void _check() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measure();
      });
      return;
    }
    _measure();
  }

  void _measure() {
    final inline = _inlineKey.currentContext?.findRenderObject() as RenderBox?;
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (inline == null || view == null || !inline.attached || !view.attached) {
      return;
    }
    final bottom =
        inline.localToGlobal(Offset(0, inline.size.height), ancestor: view).dy;
    final pinned = bottom > view.size.height - 12 + .5;
    if (pinned != _pinned || (inline.size.height - _stickyHeight).abs() > .5) {
      setState(() {
        _pinned = pinned;
        _stickyHeight = inline.size.height;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // مضمَّنةٌ داخل شاشةٍ تمرّر نفسها (أقسام الإعدادات): شريط الإجراءات يبقى في
    // آخر المحتوى بلا تثبيتٍ عائم، ولا تمريرَ داخل تمرير.
    if (ImdEmbedScope.of(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...widget.children,
        const SizedBox(height: 10),
        widget.sticky,
        ...widget.after,
      ]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
    final pad = ImdPage.paddingOf(context);
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _check();
        return false;
      },
      child: Stack(key: _viewKey, children: [
        SingleChildScrollView(
          controller: _scroll,
          padding: pad,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...widget.children,
            const SizedBox(height: 10),
            Opacity(
                opacity: _pinned ? 0 : 1,
                child: KeyedSubtree(key: _inlineKey, child: widget.sticky)),
            // Keep the last form fields scrollable above the floating action bar.
            if (_pinned) SizedBox(height: _stickyHeight + 24),
            ...widget.after,
          ]),
        ),
        if (_pinned)
          Positioned(
              left: pad.left,
              right: pad.right,
              bottom: 12,
              child: widget.sticky),
      ]),
    );
  }
}
