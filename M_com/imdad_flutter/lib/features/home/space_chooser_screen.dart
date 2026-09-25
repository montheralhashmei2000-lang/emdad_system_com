import 'package:flutter/material.dart';

import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../domain/app_space.dart';

/// اختيار مساحة العمل — لا تظهر إلا لمن يملك المساحتين.
///
/// ومن يملك واحدة يدخلها مباشرة: شاشةُ اختيارٍ بخيارٍ واحد متاح ليست اختيارًا،
/// بل نقرةٌ تُدفع كل يوم بلا مقابل.
class SpaceChooserScreen extends StatelessWidget {
  const SpaceChooserScreen({
    super.key,
    required this.spaces,
    required this.onPick,
    required this.userName,
  });

  final List<String> spaces;
  final ValueChanged<String> onPick;
  final String userName;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final narrow = ImdBp.of(context).tablet;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'نظام الإمداد والتموين',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, color: c.muted, letterSpacing: .3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    userName.isEmpty ? 'اختر القسم' : 'أهلًا $userName — اختر القسم',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يمكنك التبديل بينهما في أي وقت من أعلى الشريط الجانبي.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.8),
                  ),
                  const SizedBox(height: 28),
                  if (narrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in spaces) ...[
                          _card(context, s),
                          const SizedBox(height: 14),
                        ],
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < spaces.length; i++) ...[
                          if (i > 0) const SizedBox(width: 16),
                          Expanded(child: _card(context, spaces[i])),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, String space) {
    final c = context.imd;
    return _SpaceCard(
      space: space,
      onTap: () => onPick(space),
      accent: space == AppSpace.fuel ? c.warn : c.accent,
    );
  }
}

class _SpaceCard extends StatefulWidget {
  const _SpaceCard({
    required this.space,
    required this.onTap,
    required this.accent,
  });

  final String space;
  final VoidCallback onTap;
  final Color accent;

  @override
  State<_SpaceCard> createState() => _SpaceCardState();
}

class _SpaceCardState extends State<_SpaceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(
                color: _hover ? widget.accent : c.line, width: _hover ? 2 : 1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _hover ? imdShadow(c) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ImdIcon(AppSpace.icons[widget.space] ?? 'package',
                    size: 26, color: widget.accent),
              ),
              const SizedBox(height: 16),
              Text(
                AppSpace.label(widget.space),
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: c.text),
              ),
              const SizedBox(height: 8),
              Text(
                AppSpace.descriptions[widget.space] ?? '',
                style: TextStyle(fontSize: 13, color: c.muted, height: 1.9),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Text('ادخل',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: widget.accent)),
                const SizedBox(width: 6),
                ImdIcon('arrow-left', size: 15, color: widget.accent),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
