import 'invoice_models.dart';

/// يحوّل **النص الخام الذي أخرجه OCR** لفاتورة إلى حقولها: التاجر، رقم الفاتورة،
/// التاريخ، العملة، سعر الصرف، الإجمالي المطبوع، وأسطر الأصناف
/// (الاسم، الوحدة، الكمية، سعر الوحدة، الإجمالي).
///
/// **لا يعتمد قالبًا ثابتًا** — فالفواتير تختلف — بل على قواعد عامة:
/// * سطر الصنف = سطر فيه اسمٌ وأرقام؛ وأرقامه تُحلَّل بالتحقق الحسابي
///   (كمية × سعر ≈ إجمالي) فيُعرف أيّها الكمية وأيّها السعر وأيّها الإجمالي
///   حتى لو اختلف ترتيب الأعمدة أو اختلط رقم السطر بها.
/// * السطور ذات كلمات الإجمالي والضريبة والخصم والهاتف لا تُعدّ أصنافًا.
///
/// OCR لا يقرأ بدقة إنسان: يخطئ في الحروف العربية أحيانًا (والأرقام أدقّ)، لذلك
/// تُراجع النتيجة وتُعدَّل قبل الحفظ. ما لا يُعرف يبقى فارغًا ولا يُخمَّن.
class InvoiceTextParser {
  InvoiceTextParser._();

  /// رموز الاتجاه والمسافات الصفرية التي يدسّها OCR في النص العربي (تُبنى بالأكواد لا بحروفها).
  static final _bidi = RegExp('[${String.fromCharCodes([0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x061C, 0x200B, 0x200C, 0x200D, 0xFEFF])}]');

  /// أرقام هندية وفارسية ← لاتينية، وفواصل عربية ← عادية، وتنظيف رموز الاتجاه.
  static String clean(String s) {
    final b = StringBuffer();
    for (final r in s.replaceAll(_bidi, '').runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.write(r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.write(r - 0x06F0);
      } else if (r == 0x066B) {
        b.write('.');
      } else if (r == 0x066C || r == 0x060C) {
        b.write(',');
      } else if (r == 0xA0) {
        b.write(' ');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// تطبيع للمقارنة بالكلمات المفتاحية: ألف/ياء/تاء مربوطة/تشكيل وحروف صغيرة.
  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const _units = {
    'كيس', 'اكياس', 'كرتون', 'كرتونه', 'كراتين', 'كيلو', 'كجم', 'كغم', 'كغ', 'جرام', 'غرام', 'لتر', 'علبه', 'علب', 'حبه', 'حبات',
    'قطعه', 'قطع', 'دزينه', 'باكت', 'باكيت', 'رول', 'حزمه', 'متر', 'طن', 'جالون', 'صندوق', 'قنينه', 'شوال', 'دبه', 'عبوه', 'كيلوجرام',
    'جوال', 'ربطه', 'طقم', 'زوج', 'مجموعه', 'kg', 'g', 'pcs', 'pc', 'box', 'bag', 'l', 'ltr', 'unit', 'carton', 'pack', 'm', 'roll',
  };

  static const _stopWords = [
    'اجمالي', 'مجموع', 'المجموع', 'total', 'subtotal', 'ضريبه', 'vat', 'tax', 'خصم', 'discount', 'المطلوب', 'المستحق', 'فقط', 'لا غير',
    'رقم الفاتوره', 'فاتوره رقم', 'invoice', 'تاريخ', 'date', 'هاتف', 'جوال', 'تلفون', 'tel', 'phone', 'mobile', 'عنوان', 'address',
    'سجل تجاري', 'الرقم الضريبي', 'التوقيع', 'المستلم', 'البائع', 'المشتري', 'شكرا', 'thank', 'سعر الصرف', 'المتبقي', 'المدفوع',
    'الصافي', 'net', 'balance', 'paid', 'cash', 'نقدا', 'اجل',
  ];

  static const _headerWords = ['الصنف', 'الكميه', 'السعر', 'الوحده', 'البيان', 'description', 'qty', 'quantity', 'price', 'item', 'amount', 'المبلغ'];

  static final _numToken = RegExp(r'^\d[\d,]*(?:\.\d+)?$');
  static final _dateToken = RegExp(r'^\d{1,4}[/\-.]\d{1,2}[/\-.]\d{1,4}$');

  static double _val(String t) => double.parse(t.replaceAll(',', ''));

  /// اقرأ النص وأعد الفاتورة (واحدة؛ نص الملف كله فاتورة واحدة).
  static List<ScannedInvoice> parse(String raw) {
    final text = clean(raw);
    final lines = [for (final l in text.split(RegExp(r'[\r\n]+'))) if (l.trim().isNotEmpty) l.trim()];
    if (lines.isEmpty) return const [];
    final normalized = norm(text);

    final items = _items(lines);
    final inv = ScannedInvoice(
      merchant: _merchant(lines),
      invoiceNo: _invoiceNo(lines),
      date: _date(lines),
      currency: _currency(normalized),
      exchangeRate: _rate(normalized),
      printedTotal: _printedTotal(lines),
      items: items,
    );
    return [inv];
  }

  // ───────────── الرأس ─────────────

  static String _currency(String n) {
    final sar = RegExp(r'ريال\s*سعودي|\bsar\b|\bsr\b|ر\.?\s?س\b|saudi').allMatches(n).length;
    final yer = RegExp(r'ريال\s*يمني|\byer\b|\byr\b|ر\.?\s?ي\b|yemeni').allMatches(n).length;
    if (sar > yer) return 'sar';
    if (yer > sar) return 'yer';
    return '';
  }

  static double _rate(String n) {
    final m = RegExp(r'سعر الصرف\s*[:：]?\s*(\d+(?:\.\d+)?)').firstMatch(n);
    return m == null ? 0 : double.parse(m[1]!);
  }

  static String? _toIso(String t) {
    final dmy = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})').firstMatch(t);
    final ymd = RegExp(r'(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(t);
    int? y, m, d;
    if (ymd != null) {
      y = int.parse(ymd[1]!);
      m = int.parse(ymd[2]!);
      d = int.parse(ymd[3]!);
    } else if (dmy != null) {
      d = int.parse(dmy[1]!);
      m = int.parse(dmy[2]!);
      y = int.parse(dmy[3]!);
    } else {
      return null;
    }
    if (y < 1990 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  /// أول تاريخ على سطر فيه «التاريخ/Date»، وإلا أول تاريخ صالح في النص.
  static String _date(List<String> lines) {
    for (final l in lines) {
      final n = norm(l);
      if (n.contains('تاريخ') || n.contains('date')) {
        final d = _toIso(l);
        if (d != null) return d;
      }
    }
    for (final l in lines) {
      final d = _toIso(l);
      if (d != null) return d;
    }
    return '';
  }

  static String _invoiceNo(List<String> lines) {
    final p = RegExp(
      r'(?:رقم\s*الفاتوره|فاتوره\s*رقم|فاتوره\s*#|رقم\s*السند|invoice\s*(?:no\.?|number|num|#)|inv\.?\s*(?:no\.?|#)|bill\s*(?:no\.?|#)|no\.?)\s*[:：#.\-]*\s*\(?\s*([a-z0-9][a-z0-9\-/]*)',
    );
    for (final l in lines) {
      final m = p.firstMatch(norm(l));
      if (m != null && RegExp(r'\d').hasMatch(m[1]!)) return m[1]!.toUpperCase();
    }
    return '';
  }

  /// اسم التاجر: من الأسطر الأولى، أول سطر يشبه اسم محل/مؤسسة/شركة.
  static String _merchant(List<String> lines) {
    final key = RegExp(r'محل|محلات|مؤسس|شركه|شركة|مخازن|مخبز|بقاله|مطعم|تجاره|تجارة|مركز|معرض|store|trading|\bco\b|est\b|market|supplies|shop');
    for (final l in lines.take(8)) {
      final n = norm(l);
      if (!key.hasMatch(n)) continue;
      if (n.contains('فاتوره') && !n.contains('محل')) continue;
      if (RegExp(r'\d{5,}').hasMatch(l)) continue;
      return l.replaceAll(RegExp(r'[|\[\]{}_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return '';
  }

  static double _printedTotal(List<String> lines) {
    var best = 0.0;
    for (final l in lines) {
      final n = norm(l);
      if (!(n.contains('اجمالي') || n.contains('مجموع') || n.contains('total') || n.contains('المطلوب') || n.contains('الصافي'))) continue;
      if (n.contains('ضريبه') || n.contains('vat') || n.contains('subtotal')) continue;
      for (final t in l.split(RegExp(r'\s+'))) {
        final c = t.replaceAll(RegExp(r'[^\d,.]'), '');
        if (c.isNotEmpty && _numToken.hasMatch(c)) {
          final v = _val(c);
          if (v > best) best = v;
        }
      }
    }
    return best;
  }

  // ───────────── الأصناف ─────────────

  static bool _isStop(String n) => _stopWords.any(n.contains);

  static bool _isHeader(String n) => _headerWords.where(n.contains).length >= 2;

  static List<ScannedItem> _items(List<String> lines) {
    final out = <ScannedItem>[];
    for (final line in lines) {
      final n = norm(line);
      if (_isStop(n) || _isHeader(n)) continue;
      final item = _row(line, out.length + 1);
      if (item != null) out.add(item);
    }
    return out;
  }

  static ScannedItem? _row(String line, int expectedIndex) {
    final tokens = [
      for (final t in line.replaceAll(RegExp(r'[|]+'), ' ').split(RegExp(r'\s+')))
        if (t.isNotEmpty) t,
    ];
    // الأرقام بمواضعها في السطر؛ التاريخ لا يُعدّ رقمًا، ولاصقة العملة (2,200ر.س) تُهمل.
    final cores = [for (final t in tokens) t.replaceAll(RegExp(r'^[^\d]+|[^\d]+$'), '')];
    final numIdx = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      final core = cores[i];
      if (core.isEmpty || _dateToken.hasMatch(core) || !_numToken.hasMatch(core)) continue;
      if (tokens[i].length - core.length > 5) continue; // نصٌّ يحوي رقمًا (كود صنف) لا رقمٌ
      numIdx.add(i);
    }
    if (numIdx.isEmpty) return null;
    double v(int i) => _val(cores[i]);

    // رقم السطر في أوله (أو آخره) ⇒ يُهمل إن تبقّى بعده ما يكفي من الأرقام.
    final nums = [...numIdx];
    int? rowIndexToken;
    if (nums.length >= 3) {
      if (nums.first == 0 && v(nums.first) == expectedIndex.toDouble()) {
        rowIndexToken = nums.removeAt(0);
      } else if (nums.last == tokens.length - 1 && v(nums.last) == expectedIndex.toDouble() && nums.length >= 4) {
        rowIndexToken = nums.removeLast();
      }
    }

    int? qi, pi, ti;
    // 1) ثلاثية مرتبة (كمية، سعر، إجمالي) تحقق كمية×سعر≈إجمالي — الأكبر إجمالًا أولًا.
    double bestTotal = -1;
    for (var a = 0; a < nums.length; a++) {
      for (var b = a + 1; b < nums.length; b++) {
        for (var c = b + 1; c < nums.length; c++) {
          final q = v(nums[a]), p = v(nums[b]), t = v(nums[c]);
          if (t > bestTotal && q > 0 && p > 0 && (q * p - t).abs() <= 0.01 * t + 0.01) {
            qi = nums[a];
            pi = nums[b];
            ti = nums[c];
            bestTotal = t;
          }
        }
      }
    }
    // 2) أي ترتيب (إن اختلف ترتيب الأعمدة في قراءة OCR).
    if (ti == null && nums.length >= 3) {
      for (final t in nums) {
        for (final q in nums) {
          for (final p in nums) {
            if (t == q || t == p || q == p) continue;
            final tv = v(t);
            if (tv > bestTotal && v(q) > 0 && v(p) > 0 && (v(q) * v(p) - tv).abs() <= 0.01 * tv + 0.01) {
              qi = q;
              pi = p;
              ti = t;
              bestTotal = tv;
            }
          }
        }
      }
    }

    double qty = 0, price = 0, total = 0;
    final consumed = <int>{};
    if (ti != null) {
      qty = v(qi!);
      price = v(pi!);
      total = v(ti);
      // الثلاثية وُجدت بغير الترتيب المنطقي (كمية، سعر، إجمالي): الكمية هي الأصغر عددًا صحيحًا.
      final ordered = qi < pi && pi < ti;
      if (!ordered && qty > price && price == price.roundToDouble()) {
        final t = qty;
        qty = price;
        price = t;
      }
      consumed.addAll([qi, pi, ti]);
    } else if (nums.length >= 2) {
      // اثنان: الأكبر إجمالي، والآخر الكمية إن كان عددًا صحيحًا صغيرًا وإلا سعر الوحدة.
      final last = nums.last, prev = nums[nums.length - 2];
      total = v(last) >= v(prev) ? v(last) : v(prev);
      final other = v(last) >= v(prev) ? v(prev) : v(last);
      if (other == other.roundToDouble() && other >= 1 && other <= 1000 && other < total) {
        qty = other;
        price = double.parse((total / other).toStringAsFixed(2));
      } else {
        price = other;
      }
      consumed.addAll([last, prev]);
    } else {
      total = v(nums.first);
      consumed.add(nums.first);
    }

    final firstConsumed = consumed.reduce((a, b) => a < b ? a : b);
    // الاسم والوحدة: رموز النص قبل أول رقمٍ مستعمل (الترتيب المنطقي: م، الصنف، الوحدة، الأرقام).
    final nameTokens = <String>[];
    var unit = '';
    for (var i = 0; i < firstConsumed; i++) {
      final raw = tokens[i];
      if (i == rowIndexToken) continue; // رقم السطر لا من الاسم
      final t = raw.replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
      if (t.isEmpty) continue;
      if (_units.contains(norm(t)) && unit.isEmpty) {
        unit = t;
        continue;
      }
      // رمز قصير ليس حرفًا ولا رقمًا ذا معنى (ضجيج OCR).
      if (t.length == 1 && !RegExp(r'\d').hasMatch(t) && !RegExp(r'\p{L}', unicode: true).hasMatch(t)) continue;
      nameTokens.add(t);
    }
    // وحدةٌ بعد الأرقام (فاتورة تضع الوحدة بعد الكمية).
    if (unit.isEmpty) {
      for (var i = firstConsumed; i < tokens.length; i++) {
        final t = tokens[i].replaceAll(RegExp(r'^[^\p{L}]+|[^\p{L}]+$', unicode: true), '');
        if (t.isNotEmpty && _units.contains(norm(t))) {
          unit = t;
          break;
        }
      }
    }
    var name = nameTokens.join(' ').trim();
    // ترتيب أعمدة معكوس: لا اسم قبل الأرقام ⇒ الاسم بعدها.
    if (RegExp(r'\p{L}', unicode: true).allMatches(name).length < 2) {
      final after = <String>[];
      final last = consumed.reduce((a, b) => a > b ? a : b);
      for (var i = last + 1; i < tokens.length; i++) {
        final t = tokens[i].replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
        if (t.isNotEmpty && !_units.contains(norm(t)) && !nums.contains(i)) after.add(t);
      }
      final alt = after.join(' ').trim();
      if (RegExp(r'\p{L}', unicode: true).allMatches(alt).length >= 2) name = alt;
    }
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(name).length;
    // صفّ أرقامه متسقة (كمية×سعر≈إجمالي) يُبقى ولو لم يُقرأ اسمه — يكتبه المستخدم؛ وغير المتسق بلا اسم ضجيج.
    if (letters < 2 && ti == null) return null;
    if (letters < 2) name = '';
    // صفّ أرقامه غير متسقة حسابيًّا: لا يُقبل إلا بوحدةٍ ظاهرة أو اسمٍ واضح مع رقمين فأكثر،
    // وإلا فهو سطر ترويسة/تذييل (هاتف، عنوان، توقيع…) لا صنف.
    if (ti == null && unit.isEmpty && !(nums.length >= 2 && letters >= 4)) return null;
    return ScannedItem(name: name, unit: unit, qty: qty, unitPrice: price, lineTotal: total);
  }
}
