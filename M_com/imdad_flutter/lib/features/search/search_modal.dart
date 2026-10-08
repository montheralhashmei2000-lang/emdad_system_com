import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/search/search_service.dart';

/// لوحة البحث العام: مدخلٌ واحد يمسح جداول النظام، ونتائجُه مصنَّفةٌ بنوعها.
///
/// اختيار نتيجةٍ يفتح **شاشتها** (`SearchHit.page`) لا السجل نفسه — الشل لا
/// يمرّر وسائط إلى الشاشات بعد.
Future<void> showSearchModal(BuildContext context, {required ValueChanged<String> onOpenPage}) =>
    showImdModal<void>(
      context,
      title: 'البحث العام',
      icon: 'search',
      maxWidth: 600,
      builder: (ctx) => _SearchBody(onOpenPage: onOpenPage),
    );

class _SearchBody extends StatefulWidget {
  const _SearchBody({required this.onOpenPage});

  final ValueChanged<String> onOpenPage;

  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  /// مهلة الكتابة قبل الاستعلام — كتابةُ كلمةٍ لا تُشعل عشرة استعلامات.
  static const Duration _debounce = Duration(milliseconds: 300);

  late final SearchService _svc = SearchService(context.read<AppDatabase>());
  final _q = TextEditingController();
  final _scroll = ScrollController();

  Timer? _timer;
  bool _busy = false;
  SearchHits _hits = const SearchHits.empty();

  /// رقم آخر استعلامٍ أُطلق. الـdebounce يقلّل التكرار ولا يمنع التراكب: بحثٌ
  /// يمسح ستة عشر جدولًا بـ`LIKE '%…%'` قد يتجاوز الـ٣٠٠ م.ث، فيعود الأبطأ
  /// (مدخلٌ أقدم) بعد الأحدث ويكتب نتائجه فوقه. فتُهمل كل نتيجةٍ ليست الأحدث.
  int _seq = 0;

  /// المدخل الذي تنتمي إليه النتائج المعروضة — لرسالة «لم أجد نتائج لـ…».
  String _shown = '';

  /// النتائج مسطَّحةً بترتيب العرض — عليها يمشي السهمان.
  List<SearchHit> _flat = const [];
  int _sel = 0;

  /// مفتاح السطر المختار، ليُمرَّر إليه العرض عند التنقّل بالسهمين.
  final _selKey = GlobalKey();

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // **Esc لا يعتمد على التركيز.** اختصارات [Shortcuts] تُرسَل من العقدة
    // المركَّزة صعودًا، فإن كان التركيز خارج شجرة الحوار — وهو الحال على
    // ويندوز حيث يملكه غلاف `Focus` فوق الـNavigator في `main.dart` — لم يصل
    // Esc إلى الحوار إطلاقًا فلم يُغلق. ومعالجُ لوحة المفاتيح يرى المفتاح
    // أيًّا كان التركيز، وعمرُه عمرُ اللوحة وحدها فلا يصير «Esc عامًّا»
    // (قاعدة الواجهة: Esc يغلق المنتقيات لا كل شيء).
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return false;
    _close();
    return true;
  }

  /// إغلاقٌ لا يتكرّر: Esc قد يصل من المعالج ومن [Shortcuts] معًا.
  void _close() {
    if (_closing || !mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _timer?.cancel();
    _timer = Timer(_debounce, _run);
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    // يُزاد أيضًا للمدخل القصير: استعلامٌ جارٍ أطلقه مدخلٌ أطول ثم مُحي حرفٌ
    // منه يجب أن يسقط، وإلا ظهرت نتائجه على مدخلٍ لا يُبحث به.
    final seq = ++_seq;
    if (q.length < SearchService.minQuery) {
      setState(() {
        _hits = const SearchHits.empty();
        _flat = const [];
        _shown = '';
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    final perm = Perm.of(context);
    final hits = await _svc.search(
      q,
      access: SearchAccess(canView: perm.has, scope: perm.scope),
    );
    if (!mounted || seq != _seq) return;
    setState(() {
      _hits = hits;
      _flat = [for (final list in hits.byType.values) ...list];
      _sel = 0;
      _shown = q;
      _busy = false;
    });
  }

  void _move(int delta) {
    if (_flat.isEmpty) return;
    setState(() => _sel = (_sel + delta) % _flat.length);
    if (_sel < 0) setState(() => _sel += _flat.length);
    // بعد الإطار: سياق السطر المختار لم يُبنَ بعد في هذه اللحظة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .5, duration: const Duration(milliseconds: 120));
    });
  }

  void _open(SearchHit hit) {
    _close();
    widget.onOpenPage(hit.page);
  }

  void _openSelected() {
    if (_sel >= 0 && _sel < _flat.length) _open(_flat[_sel]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // الاختصارات هنا أقربُ إلى حقل النصّ من اختصارات التحرير الافتراضية،
    // فالسهمان وEnter يصلان إلى اللوحة لا إلى المؤشر داخل الحقل.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _OpenIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _OpenIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CloseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveIntent: CallbackAction<_MoveIntent>(onInvoke: (i) {
            _move(i.delta);
            return null;
          }),
          _OpenIntent: CallbackAction<_OpenIntent>(onInvoke: (_) {
            _openSelected();
            return null;
          }),
          _CloseIntent: CallbackAction<_CloseIntent>(onInvoke: (_) {
            _close();
            return null;
          }),
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          ImdFld(
            controller: _q,
            autofocus: true,
            hint: 'صنف، مستودع، مورد، رقم سند، اسم فرد…',
            onChanged: _onChanged,
            onSubmitted: (_) => _openSelected(),
          ),
          const SizedBox(height: 6),
          ImdLdText(
            _busy
                ? '⏳ جارٍ البحث…'
                : (_flat.isEmpty ? 'اكتب حرفين على الأقل' : 'نتائج: ${_hits.total} — ↑↓ للتنقّل، Enter للفتح'),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .5),
            child: _results(c),
          ),
        ]),
      ),
    );
  }

  Widget _results(ImdColors c) {
    if (_busy && _flat.isEmpty) return const Align(child: Padding(padding: EdgeInsets.all(16), child: ImdLd('…')));
    if (_flat.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          _shown.isEmpty
              ? 'ابحث في الأصناف والمستودعات والموردين والوحدات والسندات والأفراد.'
              : 'لم أجد نتائج لـ«$_shown»',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      );
    }
    var i = -1;
    return SingleChildScrollView(
      controller: _scroll,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final entry in _hits.byType.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              '${entry.key} (${entry.value.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.muted),
            ),
          ),
          for (final hit in entry.value) _tile(c, hit, ++i),
        ],
      ]),
    );
  }

  Widget _tile(ImdColors c, SearchHit hit, int index) {
    final on = index == _sel;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _sel = index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(hit),
        child: Container(
          key: on ? _selKey : null,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: on ? c.accentSoft : c.surface,
            border: Border.all(color: on ? c.accent : c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  hit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text),
                ),
                if (hit.subtitle.isNotEmpty)
                  Text(
                    hit.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            ImdIcon('external', size: 13, color: on ? c.accent : c.muted),
          ]),
        ),
      ),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);

  final int delta;
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}
