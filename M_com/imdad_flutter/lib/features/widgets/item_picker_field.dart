import 'package:flutter/material.dart';

import '../../data/db/app_database.dart';

/// حقل اختيار الصنف بالكتابة أو من القائمة — يقابل item-picker.js في نسخة الويب:
/// يكتب المستخدم أول حرف أو حرفين من الاسم أو الكود أو الباركود فتظهر الاقتراحات.
class ItemPickerField extends StatefulWidget {
  const ItemPickerField({
    super.key,
    required this.items,
    required this.onSelected,
    this.selected,
    this.label = 'الصنف (الكود — الاسم)',
    this.enabled = true,
  });

  final List<Item> items;
  final Item? selected;
  final ValueChanged<Item?> onSelected;
  final String label;
  final bool enabled;

  @override
  State<ItemPickerField> createState() => _ItemPickerFieldState();
}

class _ItemPickerFieldState extends State<ItemPickerField> {
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp('[ً-ْ]'), '')
      .trim();

  String _label(Item i) => i.code.isEmpty ? i.name : '${i.code} — ${i.name}';

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Item>(
      initialValue: TextEditingValue(text: widget.selected == null ? '' : _label(widget.selected!)),
      displayStringForOption: _label,
      optionsBuilder: (value) {
        final q = _norm(value.text);
        if (q.isEmpty) return widget.items.take(40);
        return widget.items.where((i) {
          return _norm(i.name).contains(q) ||
              _norm(i.code).contains(q) ||
              _norm(i.barcode).contains(q);
        }).take(40);
      },
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'اكتب اسم الصنف أو الكود…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    widget.onSelected(null);
                  },
                ),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 520),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = options.elementAt(index);
                return ListTile(
                  dense: true,
                  title: Text(item.name),
                  subtitle: item.code.isEmpty ? null : Text(item.code),
                  trailing: Text(item.baseUnit, style: Theme.of(context).textTheme.bodySmall),
                  onTap: () => onSelected(item),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
