import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/notifications_repo.dart';
import '../../domain/notification_item.dart';

/// جرس التنبيهات في الشريط العلوي، ولوحته المنسدلة.
///
/// الفحص دوري وعند فتح اللوحة: التنبيهات مشتقّة من حالة البيانات، فلا يبقى
/// تنبيهٌ على حالةٍ عولجت.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, required this.onOpenPage});

  /// يفتح شاشة التنبيه في القشرة.
  final ValueChanged<String> onOpenPage;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final NotificationsRepo _repo = NotificationsRepo(_db);

  List<AppNotification> _items = const [];
  Timer? _timer;
  bool _busy = false;

  /// دورة الفحص: ربع ساعة. أقصر منها يقرأ القاعدة بلا داعٍ، وأطول يجعل تنبيه
  /// نفاد صنفٍ يصل بعد أن نفد.
  static const Duration _every = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    _timer = Timer.periodic(_every, (_) => _scan());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      final perm = Perm.of(context);
      final allowed = perm.admin
          ? null
          : {for (final p in Perm.labels.keys) if (perm.has(p)) p};
      final items = await _repo.scan(allowed: allowed);
      await _repo.prune(items.map((n) => n.id));
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      // فحصٌ فاشل لا يُسقط الواجهة: الجرس يبقى بعدده السابق.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    await _scan();
    if (!mounted) return;
    await showImdModal<void>(
      context,
      title: 'التنبيهات',
      icon: 'bell',
      maxWidth: 560,
      builder: (ctx) => _NotifyList(
        items: _items,
        onTap: (n) async {
          await _repo.markRead(n.id);
          if (!ctx.mounted) return;
          Navigator.of(ctx).pop();
          widget.onOpenPage(n.kind.route);
          await _scan();
        },
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop()),
        if (_items.any((n) => !n.read))
          ImdButton(
            label: 'تعليم الكل مقروءًا',
            icon: 'check',
            onPressed: () async {
              await _repo.markAllRead(_items.map((n) => n.id));
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              await _scan();
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = NotifyRules.unreadOf(_items);
    final danger = _items.any((n) => !n.read && n.severity == NotifySeverity.danger);
    final c = context.imd;
    return Tooltip(
      message: unread == 0 ? 'لا تنبيهات جديدة' : '$unread تنبيهًا جديدًا',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ImdIconButton(icon: 'bell', onPressed: _open),
          if (unread > 0)
            PositionedDirectional(
              top: -2,
              end: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: danger ? c.danger : c.warn,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: c.surface, width: 1.5),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotifyList extends StatelessWidget {
  const _NotifyList({required this.items, required this.onTap});

  final List<AppNotification> items;
  final ValueChanged<AppNotification> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const ImdEmptyBox('لا تنبيهات — كل شيء ضمن الحدود');
    }
    final c = context.imd;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final n in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => onTap(n),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: n.read ? c.surface : c.subtle,
                      border: Border.all(color: n.read ? c.line : c.ring),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _tint(c, n.severity),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ImdIcon(n.kind.icon, size: 16, color: _color(c, n.severity)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            n.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: n.read ? FontWeight.w500 : FontWeight.w700,
                              color: c.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            n.body,
                            style: TextStyle(fontSize: 12.5, height: 1.6, color: c.muted),
                          ),
                        ]),
                      ),
                      if (!n.read)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: _color(c, n.severity),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _color(ImdColors c, NotifySeverity s) => switch (s) {
        NotifySeverity.danger => c.danger,
        NotifySeverity.warning => c.warn,
        NotifySeverity.info => c.accent,
      };

  static Color _tint(ImdColors c, NotifySeverity s) =>
      _color(c, s).withValues(alpha: 0.14);
}
