import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/stocktake_scan.dart';
import 'imd_icon.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

/// ماسح الباركود بالكاميرا — مقابل `scanWithCamera(input)` وزر 📷 الذي يُضاف بجوار حقول الباركود في الويب.
class ImdScanner {
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// يفتح الكاميرا ويُرجع أول قيمة مقروءة.
  static Future<String?> scan(BuildContext context) async {
    if (!supported) {
      showImdToast(context, '✖ الماسح غير متاح: الكاميرا غير مدعومة على هذا الجهاز — استخدم قارئ باركود USB');
      return null;
    }
    return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
  }

  /// مسح متواصل: الكاميرا تبقى مفتوحة وكل قراءة تُمرَّر إلى [onCode]، التي
  /// تُرجع سطر النتيجة المعروض أسفل الشاشة (وما يبدأ بـ ✖ يُعرض خطأً).
  /// تكرار الباركود نفسه وهو ما زال أمام الكاميرا لا يُحتسب ([ScanDebouncer]).
  static Future<void> scanMany(BuildContext context, {required Future<String> Function(String code) onCode}) async {
    if (!supported) {
      showImdToast(context, '✖ الماسح غير متاح: الكاميرا غير مدعومة على هذا الجهاز — استخدم قارئ باركود USB');
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => _ScanManyPage(onCode: onCode)));
  }
}

class _ScanManyPage extends StatefulWidget {
  const _ScanManyPage({required this.onCode});

  final Future<String> Function(String code) onCode;

  @override
  State<_ScanManyPage> createState() => _ScanManyPageState();
}

class _ScanManyPageState extends State<_ScanManyPage> {
  final _ctrl = MobileScannerController();
  final _debounce = ScanDebouncer();
  String _last = 'وجّه الكاميرا نحو باركود الصنف — كل مسحة قطعة واحدة';
  bool _error = false;
  int _count = 0;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (v == null || v.isEmpty || _busy || !_debounce.accept(v)) return;
    _busy = true;
    try {
      final msg = await widget.onCode(v);
      if (!mounted) return;
      final err = msg.startsWith('✖');
      if (!err) HapticFeedback.selectionClick();
      setState(() {
        _last = msg;
        _error = err;
        if (!err) _count++;
      });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: _error ? c.danger : c.accent, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                ImdButton(label: 'إنهاء ($_count)', icon: 'check', onPressed: () => Navigator.of(context).pop()),
                const Spacer(),
                IconButton(
                  onPressed: () => _ctrl.toggleTorch(),
                  icon: const ImdIcon('zap', size: 22, color: Colors.white),
                ),
              ]),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (_error ? c.danger : Colors.black).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_last,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// زر 📷 (`btn btn-o btn-sm`) يملأ الحقل بالقيمة الممسوحة.
class ImdScanButton extends StatelessWidget {
  const ImdScanButton({super.key, required this.controller, this.onScanned});

  final TextEditingController controller;
  final ValueChanged<String>? onScanned;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'مسح الباركود بالكاميرا',
      child: ImdButton.outline(
        label: '',
        icon: 'camera',
        small: true,
        onPressed: () async {
          final v = await ImdScanner.scan(context);
          if (v == null || v.isEmpty) return;
          controller.text = v;
          onScanned?.call(v);
        },
      ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _ctrl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: (cap) {
              if (_done) return;
              final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (v == null || v.isEmpty) return;
              _done = true;
              Navigator.of(context).pop(v);
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: c.accent, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                ImdButton.outline(label: 'إغلاق', icon: 'x', onPressed: () => Navigator.of(context).pop()),
                const Spacer(),
                IconButton(
                  onPressed: () => _ctrl.toggleTorch(),
                  icon: const ImdIcon('zap', size: 22, color: Colors.white),
                ),
              ]),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text('وجّه الكاميرا نحو الباركود',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
