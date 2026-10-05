import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/backup/backup_scheduler.dart';

String _intervalLabel(int h) => switch (h) {
      24 => 'كل يوم',
      72 => 'كل ٣ أيام',
      168 => 'كل أسبوع',
      720 => 'كل شهر',
      _ => 'كل $h ساعة',
    };

/// بطاقة «النسخ الاحتياطي التلقائي المشفّر» في إعدادات النسخ الاحتياطي.
///
/// كلمة المرور تُحفظ في مخزن اعتمادات النظام لا في القاعدة (انظر
/// [BackupSecretStore])، ولا تُعرض بعد ضبطها.
class BackupScheduleCard extends StatefulWidget {
  const BackupScheduleCard({super.key});

  @override
  State<BackupScheduleCard> createState() => _BackupScheduleCardState();
}

class _BackupScheduleCardState extends State<BackupScheduleCard> {
  late final BackupScheduler _scheduler = context.read<BackupScheduler>();
  BackupScheduleConfig? _cfg;
  bool _hasPassword = false;
  final _dirCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scheduler.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _scheduler.removeListener(_reload);
    _dirCtl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final cfg = await _scheduler.config();
    final has = await _scheduler.hasPassword();
    final dir = await _scheduler.effectiveDirectory(cfg);
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _hasPassword = has;
      _dirCtl.text = dir;
    });
  }

  Future<void> _update(BackupScheduleConfig next) async {
    await _scheduler.save(next);
  }

  /// يطلب كلمة مرور جديدة (٨ أحرف فأكثر + تأكيد). `true` إن حُفظت.
  Future<bool> _askPassword() async {
    final pass = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showImdModal<bool>(
      context,
      title: 'كلمة مرور النسخ المجدولة',
      icon: 'lock',
      maxWidth: 440,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdNote('⚠️ نسيانها يعني ضياع كل النسخ المشفّرة نهائيًّا — لا استعادة لها. '
              'تُحفظ في مخزن اعتمادات النظام على هذا الجهاز.'),
          ImdLabeled('كلمة المرور (٨ أحرف فأكثر)', ImdFld(controller: pass, obscure: true)),
          const SizedBox(height: 8),
          ImdLabeled('تأكيد كلمة المرور', ImdFld(controller: confirm, obscure: true)),
      ]),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(
          label: 'حفظ',
          icon: 'save',
          onPressed: () {
            if (pass.text.length < 8) {
              showImdToast(ctx, '✖ كلمة المرور ٨ أحرف على الأقل', error: true);
            } else if (pass.text != confirm.text) {
              showImdToast(ctx, '✖ كلمتا المرور غير متطابقتين', error: true);
            } else {
              Navigator.of(ctx).pop(true);
            }
          },
        ),
      ],
    );
    final value = pass.text;
    pass.dispose();
    confirm.dispose();
    if (ok != true) return false;
    await _scheduler.setPassword(value);
    return true;
  }

  Future<void> _toggle(bool on) async {
    final cfg = _cfg!;
    if (on && !_hasPassword && !await _askPassword()) return;
    await _update(cfg.copyWith(enabled: on));
    if (on && mounted) showImdToast(context, '✔ فُعّل النسخ الاحتياطي التلقائي المشفّر');
  }

  Future<void> _pickDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || _cfg == null) return;
    await _update(_cfg!.copyWith(directory: dir));
  }

  Future<void> _runNow() async {
    final res = await _scheduler.run();
    if (!mounted) return;
    showImdToast(
      context,
      res.ok ? '✔ حُفظت نسخة مشفّرة (${nf(res.records)} سجلًا)' : '✖ ${res.error}',
      error: !res.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final cfg = _cfg;
    return ImdPanel(
      title: 'النسخ الاحتياطي التلقائي المشفّر',
      icon: 'database',
      child: cfg == null
          ? const ImdLd('جارٍ التحميل…')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ImdNote('تُحفظ نسخةٌ كاملة مشفّرة (AES-256) تلقائيًّا بالفاصل الذي تختاره، '
                  'وتُحذف الأقدم منها. تُستعاد من «استعادة من ملف نسخة» بكلمة المرور نفسها. '
                  'احفظ المجلد خارج الجهاز (قرص خارجي أو سحابة) فنسخةٌ على القرص نفسه لا تحميك من تلفه.'),
              const SizedBox(height: 10),
              ImdCheckbox(
                value: cfg.enabled,
                label: 'تفعيل النسخ الاحتياطي التلقائي المشفّر',
                onChanged: _toggle,
              ),
              const SizedBox(height: 10),
              ImdGrid(columns: 2, minItemWidth: 200, gap: 10, children: [
                ImdLabeled(
                  'الفاصل بين النسخ',
                  ImdSelect<int>(
                    items: [
                      for (final h in {...BackupScheduler.intervalChoices, cfg.intervalHours}) (h, _intervalLabel(h)),
                    ],
                    value: cfg.intervalHours,
                    onChanged: (v) => _update(cfg.copyWith(intervalHours: v ?? 24)),
                  ),
                ),
                ImdLabeled(
                  'عدد النسخ المحتفَظ بها',
                  ImdSelect<int>(
                    items: [
                      for (final k in {...BackupScheduler.keepChoices, cfg.keep}) (k, 'آخر $k نسخ'),
                    ],
                    value: cfg.keep,
                    onChanged: (v) => _update(cfg.copyWith(keep: v ?? 7)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              ImdLabeled(
                'مجلد الحفظ',
                Row(children: [
                  Expanded(child: ImdFld(controller: _dirCtl, readOnly: true)),
                  const SizedBox(width: 8),
                  ImdButton.outline(label: 'اختيار المجلد', icon: 'folder', small: true, onPressed: _pickDir),
                ]),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ImdChip(
                  _hasPassword ? 'كلمة المرور محفوظة في مخزن النظام' : 'كلمة المرور غير مضبوطة',
                  tone: _hasPassword ? ImdTone.ok : ImdTone.pend,
                  icon: 'lock',
                ),
                ImdButton.outline(
                  label: _hasPassword ? 'تغيير كلمة المرور' : 'ضبط كلمة المرور',
                  icon: 'lock',
                  small: true,
                  onPressed: _askPassword,
                ),
              ]),
              const SizedBox(height: 10),
              ImdCheckbox(
                value: cfg.includeUsers,
                label: 'تضمين حسابات المستخدمين وبصمات كلمات مرورهم',
                onChanged: (v) => _update(cfg.copyWith(includeUsers: v)),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ImdButton(
                  label: 'نسخة الآن',
                  icon: 'download',
                  small: true,
                  busy: _scheduler.running,
                  onPressed: _hasPassword && !_scheduler.running ? _runNow : null,
                ),
                if (cfg.lastSuccessAt != null)
                  Text('آخر نسخة ناجحة: ${arDate(cfg.lastSuccessAt!)}',
                      style: TextStyle(fontSize: 12.5, color: c.muted)),
              ]),
              if (cfg.lastError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('⚠ آخر محاولة فشلت: ${cfg.lastError}', style: TextStyle(fontSize: 12.5, color: c.danger)),
                ),
              if (cfg.lastFile.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(cfg.lastFile,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11.5, color: c.faint)),
                ),
            ]),
    );
  }
}
