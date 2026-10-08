part of '../fuel_moves_screen.dart';

/// شريط السند المحفوظ، والحقول المشتركة بين التبويبات، وترشيح السجل.
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesShared on _FuelMovesBase, _FuelMovesActions {
  Widget _savedBanner() {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.successSoft,
        border: Border.all(color: c.success),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('حُفظ السند $_savedRef',
              style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          if (_tab != 'opening')
            ImdButton.outline(
                label: 'طباعة السند',
                icon: 'printer',
                small: true,
                onPressed: _printSaved),
          ImdButton.outline(
            label: 'حركة جديدة',
            icon: 'plus',
            small: true,
            onPressed: () => setState(() => _savedRef = ''),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── حقولٌ مشتركة

  Widget _fuelField({String label = 'نوع الصنف *'}) => ImdLabeled(
        label,
        ImdSelect<String>(
          items: [for (final t in FuelType.all) (t, FuelType.label(t))],
          value: _fuelType,
          onChanged: (v) => setState(() {
            _fuelType = v ?? FuelType.petrol;
            _allocationId = '';
          }),
        ),
        size: 11,
      );

  Widget _warehouseField(String label) => ImdLabeled(
        label,
        ImdSelect<String>(
          items: [
            // نطاق مستودعات الإعاشة لا يحكم خزّانات الوقود: دليلٌ مستقل
            // وصلاحياتٌ مستقلة (`fuelMoves`).
            for (final w in _warehouses) (w.name, w.name),
          ],
          value: _warehouse,
          onChanged: (v) => setState(() => _warehouse = v ?? ''),
        ),
        size: 11,
      );

  Widget _dateField(String label) => ImdLabeled(
        label,
        ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v)),
        size: 11,
      );

  /// ترشيحٌ نصّي على السجل — البحث في السجل أسرع من تقليب صفحاته.
  List<T> _search<T>(List<T> list, String Function(T) hay) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((e) => hay(e).toLowerCase().contains(q)).toList();
  }
}
