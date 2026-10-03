import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../repos/settings_repo.dart';

/// صنفٌ مسحوب من فاتورة — كما طُبع فيها (المسميات عند التجار قد تخالف مسميات النظام).
class ScannedItem {
  const ScannedItem({this.name = '', this.unit = '', this.qty = 0, this.unitPrice = 0, this.lineTotal = 0});

  final String name;
  final String unit;
  final double qty;
  final double unitPrice;
  final double lineTotal;

  bool get isEmpty => name.trim().isEmpty && qty == 0 && unitPrice == 0 && lineTotal == 0;
}

/// فاتورة مسحوبة. الحقل الغائب في الفاتورة يبقى فارغًا (نصًّا) أو صفرًا (رقمًا) —
/// لا يُخمَّن شيء لم يُطبع فيها.
class ScannedInvoice {
  const ScannedInvoice({
    this.merchant = '',
    this.invoiceNo = '',
    this.date = '',
    this.currency = '',
    this.exchangeRate = 0,
    this.printedTotal = 0,
    this.notes = '',
    this.items = const [],
  });

  final String merchant;
  final String invoiceNo;

  /// تاريخ الفاتورة `YYYY-MM-DD` أو فارغ.
  final String date;

  /// `sar` | `yer` | فارغ إن لم تذكر الفاتورة عملتها.
  final String currency;
  final double exchangeRate;

  /// الإجمالي المطبوع على الفاتورة (للمطابقة فقط؛ إجمالي العقد يُحسب من الأصناف).
  final double printedTotal;
  final String notes;
  final List<ScannedItem> items;
}

/// خطأ مسح بمعنًى يُعرض للمستخدم.
class InvoiceScanException implements Exception {
  InvoiceScanException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// إعدادات مسح الفواتير. **محلية لا تُزامَن** (`SettingsRepo.localOnlyKeys`) لأن
/// فيها مفتاح الخدمة.
class InvoiceAiSettings {
  const InvoiceAiSettings({this.apiKey = '', this.model = defaultModel});

  static const String key = 'invoiceAi';
  static const String defaultModel = 'claude-opus-5-5';

  /// النماذج المعروضة للاختيار: الأدقّ افتراضيًّا، والأرخص بديلًا.
  static const Map<String, String> models = {
    'claude-opus-5-5': 'Claude Opus 5.5 — الأدق (افتراضي)',
    'claude-sonnet-5-5': 'Claude Sonnet 5.5 — أرخص وأسرع',
  };

  final String apiKey;
  final String model;

  bool get ready => apiKey.trim().isNotEmpty;

  static Future<InvoiceAiSettings> load(SettingsRepo repo) async {
    final m = await repo.read(key);
    final model = '${m['model'] ?? defaultModel}';
    return InvoiceAiSettings(apiKey: '${m['apiKey'] ?? ''}', model: model.isEmpty ? defaultModel : model);
  }

  Future<void> save(SettingsRepo repo) => repo.write(key, {'apiKey': apiKey.trim(), 'model': model});
}

typedef InvoiceTransport = Future<(int, String)> Function(Uri url, Map<String, String> headers, String body);

/// يستخرج بيانات الفواتير (أصنافًا ووحداتٍ وكمياتٍ وأسعارًا وإجماليات ورقم الفاتورة
/// وتاريخها وعملتها واسم التاجر) من **صورة أو PDF** لأي تنسيق فاتورة، عبر واجهة
/// Claude الرؤيوية. لا قوالب ثابتة: النموذج يقرأ الفاتورة كما يقرؤها إنسان ويعبّئ
/// حقول المخطط المحدّد.
///
/// تُرسل الصورة إلى الإنترنت (خدمة Anthropic) عند طلب المسح وحده.
class InvoiceScanner {
  InvoiceScanner({required this.apiKey, this.model = InvoiceAiSettings.defaultModel, InvoiceTransport? transport})
      : _transport = transport ?? _httpPost;

  final String apiKey;
  final String model;
  final InvoiceTransport _transport;

  static final Uri endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  static const String _system =
      'You read purchase invoices (Arabic, English, or mixed; printed, photographed, or scanned) and return their data as JSON.\n'
      'Rules:\n'
      '- Copy item names exactly as printed, in the original language. Do not translate, correct, or merge items.\n'
      '- Numbers are plain numbers: convert Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩) to ASCII, drop thousands separators and currency symbols.\n'
      '- unit: the unit of measure as printed for that line (كيس، كرتون، كيلو، حبة…); empty string if none is printed.\n'
      '- qty / unit_price / line_total: take them from the line itself. If a value is not printed, use 0. Never compute or guess a missing value.\n'
      '- currency: "sar" for Saudi riyal (ريال سعودي, SAR, SR, ر.س), "yer" for Yemeni rial (ريال يمني, YER, ر.ي); "unknown" if the invoice does not say.\n'
      '- exchange_rate: only if the invoice prints one, else 0.\n'
      '- date: the invoice date as YYYY-MM-DD (read dd/mm/yyyy as day/month/year; Hijri dates are not converted — leave empty if only Hijri is printed).\n'
      '- invoice_no: the invoice number as printed; merchant: the seller/shop name as printed; empty strings when absent.\n'
      '- printed_total: the grand total printed on the invoice, else 0.\n'
      '- If the image holds several invoices, return one entry per invoice. Include every line item, in order.\n'
      '- notes: anything notable and not captured elsewhere (illegible parts, handwritten changes, stamps). Keep it short, or empty.';

  /// مخطط الإخراج المنظَّم. كل الحقول مطلوبة (الغائب نصٌّ فارغ أو صفر).
  static Map<String, dynamic> get schema => {
        'type': 'object',
        'additionalProperties': false,
        'required': ['invoices'],
        'properties': {
          'invoices': {
            'type': 'array',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['merchant', 'invoice_no', 'date', 'currency', 'exchange_rate', 'printed_total', 'notes', 'items'],
              'properties': {
                'merchant': {'type': 'string'},
                'invoice_no': {'type': 'string'},
                'date': {'type': 'string'},
                'currency': {
                  'type': 'string',
                  'enum': ['sar', 'yer', 'unknown'],
                },
                'exchange_rate': {'type': 'number'},
                'printed_total': {'type': 'number'},
                'notes': {'type': 'string'},
                'items': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'additionalProperties': false,
                    'required': ['name', 'unit', 'qty', 'unit_price', 'line_total'],
                    'properties': {
                      'name': {'type': 'string'},
                      'unit': {'type': 'string'},
                      'qty': {'type': 'number'},
                      'unit_price': {'type': 'number'},
                      'line_total': {'type': 'number'},
                    },
                  },
                },
              },
            },
          },
        },
      };

  /// نوع الملف من بصمته (لا من امتداده): jpeg/png/webp/gif/pdf، أو null.
  static String? mediaTypeOf(Uint8List b) {
    if (b.length < 12) return null;
    if (b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    if (b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) return 'application/pdf';
    return null;
  }

  /// حد الخدمة للصورة الواحدة ٥ ميغابايت، وللطلب ٣٢. الصور الكبيرة تُصغَّر قبل الإرسال.
  static const int _maxImageBytes = 3500000;
  static const int _maxSide = 1700;

  /// يصغّر الصورة الكبيرة (بعدًا أو حجمًا) إلى PNG بضلعٍ أقصى [_maxSide]؛ والصغيرة كما هي.
  static Future<(Uint8List, String)> prepareImage(Uint8List bytes, String mediaType) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width, h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (bytes.length <= _maxImageBytes && w <= 2400 && h <= 2400) return (bytes, mediaType);
    final scale = _maxSide / (w > h ? w : h);
    final c2 = await ui.instantiateImageCodec(bytes, targetWidth: scale < 1 ? (w * scale).round() : w, targetHeight: scale < 1 ? (h * scale).round() : h);
    final f2 = await c2.getNextFrame();
    final data = await f2.image.toByteData(format: ui.ImageByteFormat.png);
    f2.image.dispose();
    c2.dispose();
    if (data == null) throw InvoiceScanException('تعذّر تصغير الصورة');
    final out = data.buffer.asUint8List();
    if (out.length > 5000000) throw InvoiceScanException('الصورة كبيرة جدًّا حتى بعد التصغير — صوّرها بدقة أقل');
    return (out, 'image/png');
  }

  /// جسم الطلب لصورة أو PDF جاهز. معزولٌ ليُختبر دون شبكة.
  Map<String, dynamic> buildRequest(Uint8List bytes, String mediaType) {
    final isPdf = mediaType == 'application/pdf';
    return {
      'model': model,
      'max_tokens': 16000,
      'system': _system,
      // الاستخراج مهمة قراءة لا استدلال: جهد منخفض يكفي ويوفّر الكلفة والزمن.
      'output_config': {
        'effort': 'low',
        'format': {'type': 'json_schema', 'schema': schema},
      },
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': isPdf ? 'document' : 'image',
              'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Encode(bytes)},
            },
            {'type': 'text', 'text': 'Extract every invoice in this file following the rules.'},
          ],
        },
      ],
    };
  }

  /// يمسح ملفًا واحدًا (صورة أو PDF) ويعيد فواتيره.
  Future<List<ScannedInvoice>> scan(Uint8List bytes) async {
    if (apiKey.trim().isEmpty) throw InvoiceScanException('أدخل مفتاح الخدمة أولًا من «إعداد المسح»');
    final detected = mediaTypeOf(bytes);
    if (detected == null) throw InvoiceScanException('نوع الملف غير مدعوم — استعمل صورة (jpg/png/webp) أو PDF');
    String type = detected;
    var data = bytes;
    if (type != 'application/pdf') {
      try {
        (data, type) = await prepareImage(bytes, type);
      } on InvoiceScanException {
        rethrow;
      } catch (_) {
        // صورة لا تُفكّ محليًّا (gif مثلًا) تُرسل كما هي إن كانت ضمن الحد.
        if (bytes.length > 5000000) throw InvoiceScanException('الصورة كبيرة جدًّا');
      }
    } else if (bytes.length > 30000000) {
      throw InvoiceScanException('ملف PDF أكبر من ٣٠ ميغابايت');
    }
    final body = jsonEncode(buildRequest(data, type));
    final (status, text) = await _transport(
      endpoint,
      {'content-type': 'application/json', 'x-api-key': apiKey.trim(), 'anthropic-version': '2023-06-01'},
      body,
    );
    return parseResponse(status, text);
  }

  /// يحلّل ردّ الخدمة. معزولٌ ليُختبر دون شبكة.
  static List<ScannedInvoice> parseResponse(int status, String text) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw InvoiceScanException('ردٌّ غير مفهوم من الخدمة (رمز $status)');
    }
    if (status != 200) {
      final err = json['error'];
      final msg = err is Map ? '${err['message'] ?? ''}' : '';
      throw InvoiceScanException(switch (status) {
        401 || 403 => 'مفتاح الخدمة غير صالح أو غير مصرَّح — راجع «إعداد المسح»',
        413 => 'الملف كبير جدًّا للخدمة',
        429 => 'تجاوزت حد الطلبات — أعد المحاولة بعد قليل',
        529 || 500 || 502 || 503 => 'الخدمة مشغولة حاليًّا — أعد المحاولة',
        _ => 'رفضت الخدمة الطلب ($status)${msg.isEmpty ? '' : ': $msg'}',
      });
    }
    final stop = json['stop_reason'];
    if (stop == 'refusal') throw InvoiceScanException('رفضت الخدمة قراءة هذا الملف');
    if (stop == 'max_tokens') throw InvoiceScanException('الفاتورة أطول من أن تُقرأ دفعة واحدة — قسّمها إلى صفحات');
    final blocks = json['content'];
    String? payload;
    if (blocks is List) {
      for (final b in blocks) {
        if (b is Map && b['type'] == 'text') {
          payload = '${b['text']}';
          break;
        }
      }
    }
    if (payload == null) throw InvoiceScanException('لم تُرجع الخدمة بيانات');
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      throw InvoiceScanException('تعذّرت قراءة بيانات الفاتورة المُرجَعة');
    }
    return [
      for (final inv in (data['invoices'] as List? ?? const []))
        if (inv is Map) _invoice(inv.cast<String, dynamic>()),
    ];
  }

  static double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  /// تاريخ بصيغة `YYYY-MM-DD` أو فارغ — يقبل أيضًا `dd/mm/yyyy` احتياطًا.
  static String normalizeDate(String raw) {
    final t = raw.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    int? y, m, d;
    if (iso != null) {
      y = int.parse(iso[1]!);
      m = int.parse(iso[2]!);
      d = int.parse(iso[3]!);
    } else {
      final dmy = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(t);
      if (dmy == null) return '';
      d = int.parse(dmy[1]!);
      m = int.parse(dmy[2]!);
      y = int.parse(dmy[3]!);
    }
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900) return '';
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  static ScannedInvoice _invoice(Map<String, dynamic> m) {
    final cur = '${m['currency'] ?? ''}';
    return ScannedInvoice(
      merchant: '${m['merchant'] ?? ''}'.trim(),
      invoiceNo: '${m['invoice_no'] ?? ''}'.trim(),
      date: normalizeDate('${m['date'] ?? ''}'),
      currency: cur == 'sar' || cur == 'yer' ? cur : '',
      exchangeRate: _d(m['exchange_rate']),
      printedTotal: _d(m['printed_total']),
      notes: '${m['notes'] ?? ''}'.trim(),
      items: [
        for (final it in (m['items'] as List? ?? const []))
          if (it is Map)
            ScannedItem(
              name: '${it['name'] ?? ''}'.trim(),
              unit: '${it['unit'] ?? ''}'.trim(),
              qty: _d(it['qty']),
              unitPrice: _d(it['unit_price']),
              lineTotal: _d(it['line_total']),
            ),
      ].where((i) => !i.isEmpty).toList(),
    );
  }

  static Future<(int, String)> _httpPost(Uri url, Map<String, String> headers, String body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(url);
      headers.forEach(req.headers.set);
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 180));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 180));
      return (res.statusCode, text);
    } on SocketException {
      throw InvoiceScanException('لا اتصال بالإنترنت — المسح يحتاج اتصالًا');
    } on TimeoutException {
      throw InvoiceScanException('انتهت مهلة الخدمة — أعد المحاولة');
    } on HandshakeException {
      throw InvoiceScanException('تعذّر الاتصال الآمن بالخدمة');
    } finally {
      client.close(force: true);
    }
  }
}
