import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/export/excel_export.dart';
import '../../core/ui/imd_widgets.dart';

/// تصدير قائمة الارتباطات إلى Excel — مساعدٌ واحد تشاركه كل تبويبات
/// الشاشة: بناء الملف من `ExcelExport` في المشروع (الأرقام تُكتب أرقامًا
/// لا نصًّا)، ثم حفظه بمسارٍ يختاره المستخدم من منتقي النظام.
///
/// صلاحية `export` تُفحص عند المستدعي قبل النداء.
Future<void> linkExportExcel(
  BuildContext context, {
  required String sheetName,
  required String fileName,
  required List<String> headers,
  required List<List<String>> rows,
  Set<int> numericColumns = const {},
}) async {
  try {
    final bytes = Uint8List.fromList(ExcelExport.build(
      sheetName: sheetName,
      headers: headers,
      rows: rows,
      numericColumns: numericColumns,
    ));
    final path = await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
    if (path == null) return;
    // على بعض المنصات يعيد المسار بلا كتابةٍ — نضمن الملف مكتوبًا.
    final out = File(path);
    if (!await out.exists() || await out.length() == 0) {
      await out.writeAsBytes(bytes, flush: true);
    }
    if (!context.mounted) return;
    showImdToast(context, '✔ صُدِّر الملف: ${p.basename(path)}');
  } catch (e) {
    if (!context.mounted) return;
    showImdToast(context, '✖ تعذّر التصدير: $e', error: true);
  }
}
