import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_scan.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_screen_actions.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';
import '../inventory/doc_kit.dart';
import 'fuel_print.dart';

part 'fuel_moves/base_part.dart';
part 'fuel_moves/actions_part.dart';
part 'fuel_moves/doc_tabs_part.dart';
part 'fuel_moves/shared_part.dart';
part 'fuel_moves/issue_part.dart';
part 'fuel_moves/supply_part.dart';
part 'fuel_moves/transfer_part.dart';
part 'fuel_moves/opening_part.dart';

/// حركة المحروقات: الصرف والتوريد والتحويل والرصيد الافتتاحي.
///
/// الأربعة في شاشةٍ واحدة بتبويبات لأنها تُدار من مقعدٍ واحد ومن شخصٍ واحد:
/// أمين المحروقات يورّد صباحًا ويصرف نهارًا ويحوّل عند الطلب.
///
/// وكل تبويبٍ **بطاقاتٌ لا شبكةُ حقول**: الصرف سؤالٌ بعد سؤال — من أي مخزن،
/// وعلى أي أساس، ولمن، وبأي مركبة — وخلطُها في شبكةٍ واحدة يجعل الكاتب يقفز
/// بين المعاني في السطر الواحد.
class FuelMovesScreen extends StatefulWidget {
  const FuelMovesScreen({super.key, this.initialTab = 'issue', this.standalone = false});

  /// issue | supply | transfer | opening — يُفتح عليه القادم من القائمة.
  final String initialTab;

  /// `true` ⇒ الشاشة فُتحت من بند شجرةٍ مباشر (لا من باب «حركة المحروقات»
  /// الجامع)، فيُخفى شريط التبويبات الداخلي — التبويبة الواحدة هي الشاشة كلها.
  final bool standalone;

  @override
  State<FuelMovesScreen> createState() => _FuelMovesScreenState();
}

class _FuelMovesScreenState extends State<FuelMovesScreen>
    with
        _FuelMovesBase,
        _FuelMovesActions,
        _FuelMovesDocTabs,
        _FuelMovesShared,
        _FuelMovesIssue,
        _FuelMovesSupply,
        _FuelMovesTransfer,
        _FuelMovesOpening {
  @override
  void initState() {
    super.initState();
    _load();
    _screenActions = ImdScreenActions.maybeOf(context)
      ?..register(
        onSave: () {
          if (!_busy) _submit();
        },
        onPrint: () {
          if (!_busy) _printSaved();
        },
        onNewDoc: _openNewTab,
        onRefresh: _load,
      );
  }

  @override
  void didUpdateWidget(covariant FuelMovesScreen old) {
    super.didUpdateWidget(old);
    // التنقّل بين بنود القائمة يعيد بناء الشاشة نفسها بتبويبٍ آخر.
    if (old.initialTab != widget.initialTab) {
      setState(() {
        _tab = widget.initialTab;
        _savedRef = '';
      });
    }
  }

  @override
  void dispose() {
    _screenActions?.clear();
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  // ───────────────────────── البناء

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'حركة المحروقات', icon: 'swap'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    if (_warehouses.isEmpty) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'حركة المحروقات', icon: 'swap'),
        ImdEmptyState.noData(title: 'عرّف مستودعًا أولًا من شاشة المستودعات'),
      ]);
    }
    final can = Perm.of(context).writable('fuelMoves');

    return ImdPage(children: [
      ImdPageTitle(
        title: switch (_tab) {
          'issue' => 'صرف محروقات',
          'supply' => 'توريد محروقات',
          'transfer' => 'التحويل المخزني',
          _ => 'الرصيد الافتتاحي',
        },
        icon: switch (_tab) {
          'issue' => 'upload',
          'supply' => 'download',
          'transfer' => 'swap',
          _ => 'compass',
        },
        subtitle: switch (_tab) {
          'issue' => 'يُخصم من رصيد المستودع فورًا — الجهة المستفيدة وجهة '
              'الأمر تظهران في التقرير اليومي',
          'supply' => 'تُضاف الكمية إلى رصيد المخزن المستلم فور الحفظ',
          'transfer' => 'نقل نفس الصنف بين مستودعين — يمكن عكس السند إذا بقي '
              'الرصيد كافيًا',
          _ => 'أرصدة بداية الفترة لكل مستودع وصنف — تدخل في حساب الجرد',
        },
        actions: [
          ImdButton.outline(label: 'سند جديد', icon: 'plus-square', small: true, onPressed: _openNewTab),
          if (!widget.standalone)
            ImdItabs(
              value: _tab,
              onChanged: (v) => setState(() {
                _tab = v;
                _savedRef = '';
                _clearForm();
              }),
              tabs: const [
                ImdTab('issue', 'صرف', icon: 'upload'),
                ImdTab('supply', 'توريد', icon: 'download'),
                ImdTab('transfer', 'تحويل', icon: 'swap'),
                ImdTab('opening', 'رصيد افتتاحي', icon: 'compass'),
              ],
            ),
        ],
        trailing: can
            ? ImdButton(
                label: switch (_tab) {
                  'issue' => 'حفظ الصرف',
                  'supply' => 'حفظ التوريد',
                  'transfer' => 'حفظ التحويل',
                  _ => 'حفظ الرصيد',
                },
                icon: 'check',
                busy: _busy,
                onPressed: _submit,
              )
            : null,
      ),
      if (_suspended.isNotEmpty)
        ImdDocTabsBar<Map<String, dynamic>>(
          activeLabel: _activeTabLabel(),
          suspended: _suspended,
          onSelect: _switchDocTab,
          onClose: _closeDocTab,
        ),
      const SizedBox(height: 4),
      if (_savedRef.isNotEmpty) _savedBanner(),
      if (can)
        ...switch (_tab) {
          'issue' => _issueForm(),
          'supply' => _supplyForm(),
          'transfer' => _transferForm(),
          _ => _openingForm(),
        },
      ...switch (_tab) {
        'issue' => _issueLog(),
        'supply' => _supplyLog(),
        'transfer' => _transferLog(),
        _ => _openingLog(),
      },
    ]);
  }
}
