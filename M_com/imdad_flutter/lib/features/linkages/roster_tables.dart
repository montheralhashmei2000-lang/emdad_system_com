import '../../core/print/document_pdf.dart';
import '../../core/ui/imd_format.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';

/// جداول «كشف القوة البشرية» القابلة للاختيار عند الطباعة.
///
/// الكشف الكامل هو الجدول الأصلي. وإلى جانبه جدولٌ لكل حالةٍ يوجد فيها أفراد،
/// وجداول ملخّصةٌ بالأعداد (الحالة، الوحدة الفرعية، المعسكر، القسم، العمل).
/// المستخدم يحدّد ما يُطبع منها.

const List<String> rosterHeaders = [
  'م', 'الاسم', 'الرقم العسكري', 'الرتبة', 'الهاتف', 'هاتف آخر',
  'الوحدة الفرعية', 'المعسكر', 'القسم', 'العمل', 'الحالة', 'من', 'إلى', 'أيام',
];

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

List<String> rosterRow(int i, LinkPerson p) => [
      '${i + 1}', p.fullName, p.militaryNo, p.rank, p.phone, p.phone2,
      p.subUnit, p.camp, p.section, p.job, LinkStatus.label(p.status),
      _d(p.statusFrom), p.statusTo.isEmpty ? '—' : _d(p.statusTo), nf(p.statusDays),
    ];

/// خيارٌ في نافذة الاختيار.
class RosterOption {
  const RosterOption(this.key, this.title, {this.hint = '', this.group = ''});

  final String key;
  final String title;
  final String hint;

  /// عنوان المجموعة في النافذة: الكشف / جدول لكل حالة / ملخصات.
  final String group;
}

const String rosterFullKey = 'roster';
const String _statusPrefix = 'status:';

/// الملخصات: المفتاح ⇒ (العنوان، مستخرِج القيمة من الفرد).
final Map<String, (String, String Function(LinkPerson))> _summaries = {
  'sum:status': ('ملخص حسب الحالة', (p) => LinkStatus.label(p.status)),
  'sum:subUnit': ('ملخص حسب الوحدة الفرعية', (p) => p.subUnit),
  'sum:camp': ('ملخص حسب المعسكر', (p) => p.camp),
  'sum:section': ('ملخص حسب القسم', (p) => p.section),
  'sum:job': ('ملخص حسب العمل', (p) => p.job),
};

/// الخيارات المتاحة لهذه القائمة من الأفراد (حالات بلا أفراد لا تظهر).
List<RosterOption> rosterOptions(List<LinkPerson> persons) {
  final byStatus = <String, int>{};
  for (final p in persons) {
    byStatus[p.status] = (byStatus[p.status] ?? 0) + 1;
  }
  return [
    RosterOption(rosterFullKey, 'كشف الأفراد الكامل', hint: '${persons.length} فردًا', group: 'الكشف'),
    for (final e in byStatus.entries)
      RosterOption('$_statusPrefix${e.key}', 'جدول: ${LinkStatus.label(e.key)}', hint: '${e.value} فردًا', group: 'جدول لكل حالة'),
    for (final e in _summaries.entries) RosterOption(e.key, e.value.$1, group: 'ملخصات بالأعداد'),
  ];
}

PrintSection _summary(String title, List<LinkPerson> persons, String Function(LinkPerson) pick) {
  final counts = <String, int>{};
  for (final p in persons) {
    final v = pick(p).trim();
    final key = v.isEmpty ? 'غير محدد' : v;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  final total = persons.length;
  String pct(int n) => total == 0 ? '0%' : '${(n * 100 / total).toStringAsFixed(1)}%';
  return PrintSection(
    title: title,
    headers: const ['م', 'البند', 'العدد', 'النسبة'],
    columnFlex: const [1, 6, 2, 2],
    rows: [
      for (var i = 0; i < sorted.length; i++) ['${i + 1}', sorted[i].key, nf(sorted[i].value), pct(sorted[i].value)],
    ],
    totalRow: ['', 'الإجمالي', nf(total), total == 0 ? '0%' : '100%'],
    emptyText: 'لا بيانات',
  );
}

/// أقسام الطباعة للجداول المختارة، بترتيب [rosterOptions] لا بترتيب الاختيار.
List<PrintSection> buildRosterSections(List<LinkPerson> persons, Set<String> selected) {
  final out = <PrintSection>[];
  for (final o in rosterOptions(persons)) {
    if (!selected.contains(o.key)) continue;
    if (o.key == rosterFullKey) {
      out.add(PrintSection(
        title: 'كشف الأفراد',
        headers: rosterHeaders,
        rows: [for (var i = 0; i < persons.length; i++) rosterRow(i, persons[i])],
        emptyText: 'لا أفراد',
      ));
    } else if (o.key.startsWith(_statusPrefix)) {
      final status = o.key.substring(_statusPrefix.length);
      final list = persons.where((p) => p.status == status).toList();
      out.add(PrintSection(
        title: '${LinkStatus.label(status)} (${nf(list.length)})',
        headers: rosterHeaders,
        rows: [for (var i = 0; i < list.length; i++) rosterRow(i, list[i])],
      ));
    } else if (_summaries[o.key] case final s?) {
      out.add(_summary(s.$1, persons, s.$2));
    }
  }
  return out;
}
