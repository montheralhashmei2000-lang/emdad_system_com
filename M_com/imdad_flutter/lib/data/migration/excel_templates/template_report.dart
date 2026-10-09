import 'template_kind.dart';

/// صفٌّ لم يُقبل وسبب ذلك.
class RowIssue {
  const RowIssue(this.row, this.reason);

  /// رقم الصف في الورقة (العناوين = 1).
  final int row;
  final String reason;

  @override
  String toString() => 'صف $row: $reason';
}

/// تقرير استيراد قالب — يُحسب بلا كتابة ([dryRun]) ثم يُكتب فعلًا بعد التأكيد.
class TemplateReport {
  TemplateReport({required this.kind, required this.mode, required this.dryRun});

  final TemplateKind kind;
  final ImportMode mode;

  /// تقرير تجريبي لم يُكتب شيء بسببه.
  final bool dryRun;

  /// صفوف نجحت وأنشأت سجلًّا جديدًا.
  int created = 0;

  /// صفوف نجحت وحدَّثت سجلًّا موجودًا.
  int updated = 0;

  /// سجلات حُذفت (نمط الاستبدال).
  int deleted = 0;

  /// سجلات كان يُراد حذفها فبقيت لأن لها حركات أو ارتباطات.
  int kept = 0;

  final List<RowIssue> failed = [];
  final List<String> warnings = [];

  int get ok => created + updated;
  int get failedCount => failed.length;

  String get summary {
    final b = StringBuffer('ناجح $ok');
    if (created > 0 || updated > 0) b.write(' (جديد $created · محدَّث $updated)');
    b.write(' · فاشل $failedCount');
    if (mode == ImportMode.replace) {
      b.write(' · حُذف $deleted · بقي $kept (له ارتباطات)');
    }
    return b.toString();
  }
}
