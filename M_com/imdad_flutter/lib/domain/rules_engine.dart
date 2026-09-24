/// محرك القواعد — نقل مطابق لـ rules-engine.js بصياغة بشرية ودون أي تنفيذ ديناميكي (eval).
/// الصياغة: `IF stock('أرز') < 100 AND daysLeft('') <= 3 THEN notify('الرصيد منخفض'); block('')`
library;

class RuleCondition {
  const RuleCondition({
    required this.source,
    required this.arg,
    required this.op,
    required this.value,
  });

  /// اسم مصدر البيانات: stock, daysLeft, avgUse, transfers, qty …
  final String source;
  final String arg;
  final String op; // > < >= <= == !=
  final double value;
}

class RuleAction {
  const RuleAction({required this.action, required this.arg});

  /// notify | block | أي إجراء يضيفه التطبيق لاحقًا
  final String action;
  final String arg;
}

class Rule {
  const Rule({
    required this.id,
    required this.line,
    required this.conditions,
    required this.actions,
    this.enabled = true,
  });

  final String id;
  final String line;
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;
  final bool enabled;
}

class RulesRunResult {
  RulesRunResult({required this.fired, required this.notifications, required this.blocked});

  final List<RuleAction> fired;
  final List<String> notifications;
  final bool blocked;
}

typedef RuleDataSource = num Function(String arg, Map<String, dynamic> context);

class RulesEngine {
  final Map<String, RuleDataSource> _sources = {};

  RulesEngine() {
    // مصادر البيانات الافتراضية — نفس أسماء النسخة الحالية
    registerSource('stock', (arg, ctx) => _num((ctx['stockMap'] as Map?)?[arg]));
    registerSource('daysLeft', (arg, ctx) => _num(ctx['daysLeft']));
    registerSource('avgUse', (arg, ctx) => _num((ctx['avgUse'] as Map?)?[arg]));
    registerSource('transfers', (arg, ctx) => _num((ctx['transfers'] as Map?)?[arg]));
    registerSource('qty', (arg, ctx) => _num(ctx['qty']));
  }

  void registerSource(String name, RuleDataSource fn) => _sources[name] = fn;

  static final RegExp _ruleRe = RegExp(r'^IF\s+(.+)\s+THEN\s+(.+)$', caseSensitive: false);
  static final RegExp _condRe =
      RegExp(r'''^([A-Za-z_][\w.]*)\(([^)]*)\)\s*(<=|>=|==|!=|<|>)\s*([-\d.]+)$''');
  static final RegExp _actRe = RegExp(r'''^([A-Za-z_]+)\(([^)]*)\)$''');

  List<Rule> parse(String text) {
    final rules = <Rule>[];
    final lines = text.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final m = _ruleRe.firstMatch(line);
      if (m == null) continue;

      final conds = <RuleCondition>[];
      for (final raw in m.group(1)!.split(RegExp(r'\s+AND\s+', caseSensitive: false))) {
        final c = _condRe.firstMatch(raw.trim());
        if (c == null) continue;
        conds.add(RuleCondition(
          source: c.group(1)!,
          arg: _unquote(c.group(2)!),
          op: c.group(3)!,
          value: double.tryParse(c.group(4)!) ?? 0,
        ));
      }

      final acts = <RuleAction>[];
      for (final raw in m.group(2)!.split(RegExp(r'\s*;\s*'))) {
        final a = _actRe.firstMatch(raw.trim());
        if (a == null) continue;
        acts.add(RuleAction(action: a.group(1)!, arg: _unquote(a.group(2)!)));
      }

      if (conds.isNotEmpty && acts.isNotEmpty) {
        rules.add(Rule(id: 'rule-${i + 1}', line: line, conditions: conds, actions: acts));
      }
    }
    return rules;
  }

  bool evaluate(Rule rule, Map<String, dynamic> context) {
    for (final c in rule.conditions) {
      final src = _sources[c.source];
      final value = src != null ? _num(src(c.arg, context)) : _resolvePath(context, '${c.source}.${c.arg}');
      if (!_compare(c.op, value.toDouble(), c.value)) return false;
    }
    return true;
  }

  RulesRunResult run(String text, Map<String, dynamic> context) =>
      runRules(parse(text), context);

  RulesRunResult runRules(List<Rule> rules, Map<String, dynamic> context) {
    final fired = <RuleAction>[];
    final notes = <String>[];
    var blocked = false;
    for (final r in rules) {
      if (!r.enabled) continue;
      if (!evaluate(r, context)) continue;
      for (final a in r.actions) {
        fired.add(a);
        if (a.action == 'notify') notes.add(a.arg);
        if (a.action == 'block') blocked = true;
      }
    }
    return RulesRunResult(fired: fired, notifications: notes, blocked: blocked);
  }

  static bool _compare(String op, double a, double b) {
    switch (op) {
      case '>':
        return a > b;
      case '<':
        return a < b;
      case '>=':
        return a >= b;
      case '<=':
        return a <= b;
      case '==':
        return a == b;
      case '!=':
        return a != b;
    }
    return false;
  }

  static num _num(Object? v) {
    if (v is num) return v;
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static num _resolvePath(Map<String, dynamic> src, String path) {
    Object? cur = src;
    for (final part in path.split('.')) {
      if (cur is Map) {
        cur = cur[part];
      } else {
        return 0;
      }
    }
    return _num(cur);
  }

  static String _unquote(String v) =>
      v.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
}
