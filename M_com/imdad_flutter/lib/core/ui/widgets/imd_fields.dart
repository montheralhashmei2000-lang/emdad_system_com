import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../imd_icon.dart';
import '../imd_tokens.dart';
import 'imd_dialogs.dart';

/// زخرفة حقول الإدخال الموحّدة.
/// وسمٌ يُعلن أن ما تحته نمطٌ مدمج.
///
/// **تُكتب مرةً حول الجدول فتتبعها حقوله كلها** — بديلًا عن تمرير `compact:`
/// إلى كل حقلٍ في خمس شاشات، وهو ما يُنسى في أوّل حقلٍ يُضاف بعده.
class ImdCompact extends InheritedWidget {
  const ImdCompact({super.key, this.on = true, this.flush = false, required super.child});

  final bool on;

  /// حقولٌ ملتصقةٌ بحدود خليّتها: بلا زوايا مدوَّرة ولا حدٍّ خاص — الفاصل بين
  /// الخلايا خطُّ الشبكة وحده (جداول الإدخال ومجموعات الإدخال [ImdInputGroup]).
  final bool flush;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImdCompact>()?.on ?? false;

  static bool flushOf(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<ImdCompact>();
    return (w?.on ?? false) && w!.flush;
  }

  @override
  bool updateShouldNotify(ImdCompact old) => old.on != on || old.flush != flush;
}

InputDecoration imdFieldDecoration(
  BuildContext context, {
  String? hint,
  String? prefixIcon,
  Widget? suffix,
  bool dense = false,
  bool readOnly = false,
  String? errorText,
}) {
  final c = context.imd;
  final compact = ImdCompact.of(context);
  final flush = ImdCompact.flushOf(context);
  final hasError = errorText != null && errorText.isNotEmpty;
  // رسالة الخطأ من `colorScheme.error`، وحدّ الحقل يوافقها فلا يختلف لونان.
  final err = Theme.of(context).colorScheme.error;
  // الملتصق: بلا زوايا، وبلا حدٍّ في الحالة العادية (خطّ الشبكة يفصل الخلايا)؛
  // يظهر حدّ التركيز والخطأ فقط.
  OutlineInputBorder b(Color col, [double w = 1, bool quiet = false]) => OutlineInputBorder(
        borderRadius: flush
            ? BorderRadius.zero
            : BorderRadius.circular(compact ? ImdSizes.compactRadius : 10),
        borderSide: flush && quiet ? BorderSide.none : BorderSide(color: col, width: w),
      );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    errorText: hasError ? errorText : null,
    errorStyle: TextStyle(fontSize: 12, height: 1.4, color: err),
    errorMaxLines: 2,
    hintStyle: TextStyle(color: c.faint, fontSize: compact ? 12.5 : 14),
    filled: true,
    fillColor: readOnly ? c.bg : c.surface,
    contentPadding: EdgeInsets.symmetric(
      horizontal: compact ? ImdSizes.compactPadH : 12,
      vertical: compact ? ImdSizes.compactPadV : (dense ? 8 : 12),
    ),
    prefixIcon: prefixIcon == null
        ? null
        : Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
            child: ImdIcon(prefixIcon, size: 16, color: c.faint),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    // `suffix` يقع عند نهاية الحقل: يسار الحقل في RTL ويمينه في LTR.
    suffixIcon: suffix == null
        ? null
        : Padding(padding: const EdgeInsetsDirectional.only(end: 10), child: suffix),
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    border: b(c.lineStrong, 1, true),
    enabledBorder: b(c.lineStrong, 1, true),
    disabledBorder: b(c.lineStrong, 1, true),
    focusedBorder: b(c.accent, 1),
    errorBorder: b(hasError ? err : c.danger),
    focusedErrorBorder: b(hasError ? err : c.danger),
  );
}

/// عنوان فوق الحقل (13/600) ثم الحقل.
class ImdField extends StatelessWidget {
  const ImdField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.child,
    this.required = false,
    this.readOnly = false,
    this.keyboardType,
    this.onChanged,
    this.maxLines = 1,
    this.obscure = false,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.onSubmitted,
    this.prefixIcon,
    this.focusNode,
    this.autofocus = false,
    this.errorText,
    this.suffix,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;

  /// رسالة خطأ تظهر تحت الحقل بلون `colorScheme.error`.
  final String? errorText;

  /// عنصر عند نهاية الحقل (يسار الحقل في RTL). لا يُطبَّق مع [child] المخصص.
  final Widget? suffix;
  final Widget? child;
  final bool required;
  final bool readOnly;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool obscure;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final ValueChanged<String>? onSubmitted;
  final String? prefixIcon;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  if (required) TextSpan(text: ' *', style: TextStyle(color: c.danger)),
                ]),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text2),
              ),
            ),
          child ??
              TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                readOnly: readOnly,
                keyboardType: keyboardType,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                maxLines: maxLines,
                obscureText: obscure,
                inputFormatters: inputFormatters,
                textAlign: textAlign,
                style: TextStyle(fontSize: 14, color: readOnly ? c.muted : c.text),
                decoration: imdFieldDecoration(context,
                    hint: hint,
                    readOnly: readOnly,
                    prefixIcon: prefixIcon,
                    suffix: suffix,
                    errorText: errorText),
              ),
          // الحقل المخصص يرسم ديكوره بنفسه، فتُعرض رسالة الخطأ تحته هنا.
          if (child != null && errorText != null && errorText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(errorText!,
                  style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

/// قائمة اختيارٍ تُفتح كنافذةٍ كبيرة بها بحثٌ وقائمةُ خيارات — لا القائمة الصغيرة
/// المنسدلة الافتراضية: على سطح المكتب تُقرأ عشرات الخيارات دفعةً واحدة، وعلى
/// الجوال تُنقر بالإصبع بلا تصويبٍ على سطرٍ ضيّق.
///
/// الحقل نفسه يعرض القيمة المختارة بإطار الحقول المعتاد. [onChanged] `null` ⇒
/// معطَّل.
class ImdSelect<T> extends StatelessWidget {
  const ImdSelect({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.dense = false,
    this.title,
  });

  final List<(T, String)> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool dense;

  /// عنوان النافذة — الافتراضي [hint] أو «اختر».
  final String? title;

  Future<void> _open(BuildContext context) async {
    final picked = await showImdModal<_Pick<T>>(
      context,
      title: title ?? hint ?? 'اختر',
      icon: 'search',
      maxWidth: 460,
      builder: (ctx) => ImdPickerBody<T>(items: items, value: value),
    );
    if (picked != null) onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final compact = ImdCompact.of(context);
    final shown = [for (final e in items) if (e.$1 == value) e.$2];
    final enabled = onChanged != null;
    final fontSize = compact ? 13.0 : 14.0;
    // الارتفاع **ثابتٌ** لا حدٌّ أدنى: يساوي الحقل المدمج تمامًا فلا يعلو زرّ «+»
    // المجاور له ([ImdInputGroup]).
    return SizedBox(
      height: compact ? ImdSizes.compactField : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? ImdSizes.compactRadius : ImdSizes.radius),
        onTap: enabled ? () => _open(context) : null,
        child: InputDecorator(
          isEmpty: shown.isEmpty,
          decoration: imdFieldDecoration(context, dense: dense, readOnly: !enabled),
          child: Row(children: [
            Expanded(
              child: shown.isEmpty
                  ? Text(hint ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.faint, fontSize: compact ? 12.5 : 14))
                  : Text(shown.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: fontSize,
                          color: enabled ? c.text : c.muted,
                          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily)),
            ),
            ImdIcon('chevron-down', size: 16, color: c.muted),
          ]),
        ),
      ),
    );
  }
}

/// اختيارٌ مُرجَع: يميّز «اختير عنصرٌ قيمته null» عن «أُغلقت النافذة بلا اختيار».
class _Pick<T> {
  const _Pick(this.value);
  final T? value;
}

/// محتوى نافذة الاختيار: بحثٌ فوريّ وقائمةٌ تُمرَّر. Enter يختار أول المطابقات،
/// والخيار الحالي معلَّمٌ بعلامة ✓.
class ImdPickerBody<T> extends StatefulWidget {
  const ImdPickerBody({super.key, required this.items, required this.value});

  final List<(T, String)> items;
  final T? value;

  @override
  State<ImdPickerBody<T>> createState() => _ImdPickerBodyState<T>();
}

class _ImdPickerBodyState<T> extends State<ImdPickerBody<T>> {
  String _q = '';

  List<(T, String)> get _list =>
      _q.isEmpty ? widget.items : [for (final e in widget.items) if (e.$2.toLowerCase().contains(_q.toLowerCase())) e];

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final list = _list;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.items.length > 6) ...[
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v.trim()),
            onSubmitted: (_) {
              if (list.isNotEmpty) Navigator.of(context).pop(_Pick<T>(list.first.$1));
            },
            style: TextStyle(fontSize: 13.5, color: c.text),
            decoration: imdFieldDecoration(context, dense: true).copyWith(hintText: 'بحث…'),
          ),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .55),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: Text('لا خيارات مطابقة', style: TextStyle(color: c.muted, fontSize: 13))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final on = e.$1 == widget.value;
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => Navigator.of(context).pop(_Pick<T>(e.$1)),
                        child: Container(
                          constraints: BoxConstraints(minHeight: ImdSizes.touchMin - 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: on ? c.accentSoft : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(e.$2,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                                      color: on ? c.accent : c.text)),
                            ),
                            if (on) ImdIcon('check', size: 15, color: c.accent),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
