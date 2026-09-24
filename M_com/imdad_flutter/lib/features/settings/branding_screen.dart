import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_fonts.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../../main.dart' show ImdTheme;
import '../home/home_shell.dart';
import '../inventory/doc_kit.dart';

/// هوية التطبيق والشعار — نقل `renderBranding()`:
/// الشعار وحجمه وسمة التطبيق، واسم التطبيق وأسطر الجهة الأربعة
/// التي تظهر في الواجهة وفي كل النماذج المطبوعة.
class BrandingScreen extends StatefulWidget {
  const BrandingScreen({super.key});

  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final SettingsRepo _settings = SettingsRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _name = TextEditingController();
  final _l1 = TextEditingController();
  final _l2 = TextEditingController();
  final _l3 = TextEditingController();
  final _l4 = TextEditingController();
  final _size = TextEditingController(text: '140');

  String _logo = '';
  String _theme = 'auto';
  String _font = ImdFonts.defaultFamily;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _l1, _l2, _l3, _l4, _size]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final id = await _settings.identity();
    if (!mounted) return;
    setState(() {
      imdSetText(_name, id.name);
      imdSetText(_l1, id.orgLine1);
      imdSetText(_l2, id.orgLine2);
      imdSetText(_l3, id.orgLine3);
      imdSetText(_l4, id.orgLine4);
      imdSetText(_size, id.logoSize % 1 == 0 ? id.logoSize.toInt().toString() : '${id.logoSize}');
      _logo = id.logoBase64;
      _theme = id.themePref;
      _font = ImdFonts.normalize(id.fontFamily);
      _loading = false;
    });
  }

  bool get _editable => _perm.admin || _perm.has('settings', PermAction.edit);

  /// اختيار ملف الشعار وتخزينه Base64 (حد أقصى ٢ ميجابايت كما في الويب).
  Future<void> _pickLogo() async {
    final picked = await ImdFiles.pick(extensions: const ['png', 'jpg', 'jpeg', 'webp']);
    if (picked == null) return;
    final (name, bytes) = picked;
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted) showImdToast(context, '✖ حجم الشعار أكبر من ٢ ميجابايت', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _logo = base64Encode(bytes));
    showImdToast(context, '✔ اختير الشعار «$name» — اضغط حفظ لتطبيقه');
  }

  Future<void> _save() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    setState(() => _busy = true);
    final id = AppIdentity(
      name: _name.text.trim().isEmpty ? 'نظام الإمداد والتموين' : _name.text.trim(),
      logoBase64: _logo,
      logoSize: double.tryParse(_size.text.trim()) ?? 140,
      themePref: _theme,
      fontFamily: _font,
      orgLine1: _l1.text.trim(),
      orgLine2: _l2.text.trim(),
      orgLine3: _l3.text.trim(),
      orgLine4: _l4.text.trim(),
    );
    await _settings.saveIdentity(id);
    // السمة والخط يُطبَّقان فورًا كما في `applyBranding()` بالويب، بلا إعادة تشغيل.
    if (mounted) {
      context.read<ImdTheme>()
        ..apply(id.themePref)
        ..applyFont(id.fontFamily);
    }
    await AuditRepo(_db).write(
      'BRANDING_UPDATED',
      'settings',
      'تحديث هوية وشعار التطبيق',
      actorEmail: _perm.email,
      details: {'target': id.name, 'risk': 'sensitive'},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, '✔ حُفظت الهوية وطُبِّقت على الواجهة والطباعة');
  }

  Future<void> _resetLogo() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    setState(() => _logo = '');
    showImdToast(context, '✔ أُزيل الشعار — اضغط حفظ لتثبيت الاستعادة');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'هوية التطبيق والشعار', icon: 'image'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final c = context.imd;
    final w = _editable;

    return ImdStickyPage(
      sticky: w
          ? ImdStickyActions(children: [
              ImdButton(label: 'حفظ الهوية والشعار', icon: 'save', busy: _busy, onPressed: _save),
              ImdButton.outline(
                label: 'استعادة الشعار الافتراضي',
                icon: 'rotate-ccw',
                onPressed: _resetLogo,
              ),
            ])
          : const ImdNote('👁 عرض فقط — تعديل الهوية يحتاج صلاحية الإعدادات.'),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // `injectBackToSettings()` — الشاشتان تُفتحان من الإعدادات فقط.
            child: ImdButton.outline(
              label: 'رجوع إلى الإعدادات',
              icon: 'arrow-left',
              small: true,
              onPressed: () => context.read<ImdNav>().go('settings'),
            ),
          ),
        ),
        const ImdPageTitle(
          title: 'هوية التطبيق والشعار',
          icon: 'image',
          subtitle: 'إدارة شعار النظام واسم الجهة الذي يظهر في الواجهة والتقارير '
              'والطباعة الرسمية.',
        ),
        ImdGrid2(children: [
          ImdPanel(
            title: 'الشعار',
            icon: 'image',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _logoPreview(c),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('شعار النظام',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.text)),
                    Text('PNG / JPG / WEBP — يُفضَّل صورة واضحة بخلفية شفافة.',
                        style: TextStyle(fontSize: 12, height: 1.8, color: c.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              ImdButton.outline(
                label: 'اختيار ملف الشعار',
                icon: 'upload',
                small: true,
                onPressed: w ? _pickLogo : null,
              ),
              const SizedBox(height: 10),
              ImdLabeled(
                'حجم الشعار (بكسل)',
                ImdFld(controller: _size, number: true, enabled: w, onChanged: (_) => setState(() {})),
              ),
              const SizedBox(height: 10),
              ImdLabeled(
                'سمة التطبيق',
                ImdSelect<String>(
                  items: const [('light', 'فاتح'), ('dark', 'داكن'), ('auto', 'تلقائي')],
                  value: _theme,
                  onChanged: w ? (v) => setState(() => _theme = v ?? 'auto') : null,
                ),
              ),
              const SizedBox(height: 10),
              ImdLabeled(
                'خط الواجهة',
                ImdSelect<String>(
                  items: [for (final f in ImdFonts.all) (f.family, f.label)],
                  value: _font,
                  onChanged: w ? (v) => setState(() => _font = ImdFonts.normalize(v)) : null,
                ),
              ),
              const SizedBox(height: 8),
              _fontPreview(c),
            ]),
          ),
          ImdPanel(
            title: 'بيانات الجهة',
            icon: 'building',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ImdLabeled('اسم التطبيق', ImdFld(controller: _name, enabled: w)),
              const SizedBox(height: 10),
              ImdLabeled('السطر الأول', ImdFld(controller: _l1, enabled: w)),
              const SizedBox(height: 10),
              ImdLabeled('السطر الثاني', ImdFld(controller: _l2, enabled: w)),
              const SizedBox(height: 10),
              ImdLabeled('السطر الثالث', ImdFld(controller: _l3, enabled: w)),
              const SizedBox(height: 10),
              ImdLabeled('السطر الرابع', ImdFld(controller: _l4, enabled: w)),
            ]),
          ),
        ]),
      ],
    );
  }


  /// معاينة حيّة للخط المختار قبل الحفظ.
  ///
  /// تشمل سطرًا من الأرقام في عمود: خط النظام المحاسبي يجب أن تتراصف خاناته
  /// عموديًا، وهذا ما لا يظهر في نص عادي.
  Widget _fontPreview(ImdColors c) {
    final font = ImdFonts.of(_font);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(font.note, style: TextStyle(fontSize: 11.5, height: 1.7, color: c.muted)),
        const SizedBox(height: 8),
        Text('سند توريد مخزني — أرز أبيض',
            style: TextStyle(
                fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        Text('مستودع الفرع · الجهة الموردة: مؤسسة التموين',
            style: TextStyle(fontFamily: _font, fontSize: 12.5, height: 1.9, color: c.text2)),
        const SizedBox(height: 6),
        for (final n in const ['1,250.500', '9,800.250', '  75.000'])
          Text(n,
              style: TextStyle(
                  fontFamily: _font,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: c.accent)),
      ]),
    );
  }

  /// `.logo-preview` — مربع بحدود متقطعة يعرض الشعار أو الحرف «إ».
  Widget _logoPreview(ImdColors c) {
    final size = (double.tryParse(_size.text.trim()) ?? 140).clamp(40, 200).toDouble();
    Uint8List? bytes;
    if (_logo.isNotEmpty) {
      try {
        bytes = base64Decode(_logo);
      } catch (_) {}
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: bytes == null
          ? Text('إ', style: TextStyle(fontSize: size * 0.4, color: c.accent, fontWeight: FontWeight.w700))
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
    );
  }
}
