# Reports View — إدارة التقارير (شجرة + فلاتر + جدول).
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QTreeWidget, QTreeWidgetItem, QStackedWidget, QTableWidget,
    QTableWidgetItem, QHeaderView, QPushButton, QComboBox, QDateEdit,
    QMessageBox, QGroupBox, QGridLayout, QCheckBox,
    QFileDialog,
)
from PyQt6.QtCore import Qt, QDate
from PyQt6.QtGui import QTextDocument

try:
    import qtawesome as qta
except Exception:
    qta = None

from api_service import ApiService

REPORT_LIST = (
    ("حركة المخزون اليومية", "fa5s.exchange-alt"),
    ("كشف حساب وحدة مستفيدة", "fa5s.file-invoice"),
    ("تقرير أرصدة المخزون", "fa5s.boxes"),
    ("تحليل الاستهلاك", "fa5s.chart-pie"),
    ("تقرير حصر القوة", "fa5s.users"),
    ("أداء المطابخ والأفران", "fa5s.utensils"),
    ("ملخص توريدات الموردين", "fa5s.truck"),
    ("تقرير المرتجعات", "fa5s.undo"),
    ("تقرير العمل اليومي", "fa5s.clipboard-list"),
)
class ReportsView(QWidget):
    def __init__(self, parent=None, api_service=None):
        super().__init__(parent)
        self.api_service = api_service
        self.main_window = parent
        self.current_report_idx = 0
        self.report_title = None
        self.warehouses_map = {}
        self.units_map = {}
        self.camps_map = {}
        self.categories_map = {}
        self.suppliers_map = {}
        self.facilities_map = {}
        self._init_ui()

    def _init_ui(self):
        # Root layout
        root = QHBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)

        # Left: Report tree
        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setMaximumWidth(280)
        self.tree.setMinimumWidth(220)
        self.tree.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        for name, icon_name in REPORT_LIST:
            item = QTreeWidgetItem([name])
            if qta:
                item.setIcon(0, qta.icon(icon_name, color="#C0392B"))
            self.tree.addTopLevelItem(item)
        self.tree.currentItemChanged.connect(self._on_report_selected)

        # Right: Title + Filters + Table + Actions
        right = QWidget()
        right_lay = QVBoxLayout(right)
        right_lay.setContentsMargins(12, 12, 12, 12)
        right_lay.setSpacing(8)

        # Title
        self.lbl_title = QLabel("مركز التقارير")
        self.lbl_title.setObjectName("reportTitle")
        self.lbl_title.setAlignment(Qt.AlignmentFlag.AlignRight)
        right_lay.addWidget(self.lbl_title)

        # Filter stack
        self.filter_stack = QStackedWidget()
        self.filter_stack.setSizePolicy(
            self.filter_stack.sizePolicy().horizontalPolicy(),
            self.filter_stack.sizePolicy().verticalPolicy()
        )
        right_lay.addWidget(self.filter_stack, stretch=0)

        # Build filter pages for each report
        for idx in range(len(REPORT_LIST)):
            self.filter_stack.addWidget(self._build_filters_for_report(idx))

        # Action buttons
        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        self.btn_run = QPushButton("تنفيذ (عرض التقرير)")
        self.btn_run.setObjectName("primaryBtn")
        self.btn_run.clicked.connect(self._run_report)
        self.btn_print = QPushButton("طباعة")
        self.btn_print.clicked.connect(self._print_report)
        self.btn_export = QPushButton("تصدير إكسيل")
        self.btn_export.clicked.connect(self._export_excel)
        for b in (self.btn_run, self.btn_print, self.btn_export):
            btn_row.addWidget(b)
        right_lay.addLayout(btn_row)

        # Results table
        self.table = QTableWidget(0, 0)
        self.table.setObjectName("reportTable")
        self.table.setAlternatingRowColors(True)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        right_lay.addWidget(self.table, stretch=1)

        root.addWidget(self.tree)
        root.addWidget(right, stretch=1)

    def _build_filters_for_report(self, idx: int) -> QWidget:
        page = QWidget()
        lay = QGridLayout(page)
        lay.setAlignment(Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignRight)
        lay.setHorizontalSpacing(12)
        lay.setVerticalSpacing(8)
        row = 0

        def add_date_row(label_text, attr_from, attr_to):
            nonlocal row
            lbl = QLabel(label_text)
            lbl.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            dt_from = QDateEdit()
            dt_from.setCalendarPopup(True)
            dt_from.setDisplayFormat("yyyy-MM-dd")
            dt_from.setDate(QDate.currentDate().addDays(-30))
            dt_to = QDateEdit()
            dt_to.setCalendarPopup(True)
            dt_to.setDisplayFormat("yyyy-MM-dd")
            dt_to.setDate(QDate.currentDate())
            setattr(self, attr_from, dt_from)
            setattr(self, attr_to, dt_to)
            lay.addWidget(lbl, row, 2)
            lay.addWidget(dt_from, row, 1)
            lay.addWidget(QLabel("إلى"), row, 1, 1, 1, Qt.AlignmentFlag.AlignLeft)
            lay.addWidget(dt_to, row, 0)
            row += 1

        if idx == 0:
            add_date_row("فترة الحركة:", "f1_dt_from", "f1_dt_to")
            self.f1_warehouse = QComboBox(); self.f1_warehouse.addItem("كل المستودعات", None)
            self.f1_category = QComboBox(); self.f1_category.addItem("كل الأصناف", None)
            lay.addWidget(QLabel("المستودع:"), row, 2); lay.addWidget(self.f1_warehouse, row, 1, 1, 2); row += 1
            lay.addWidget(QLabel("الصنف/الفئة:"), row, 2); lay.addWidget(self.f1_category, row, 1, 1, 2); row += 1
        elif idx == 1:
            add_date_row("فترة الكشف:", "f2_dt_from", "f2_dt_to")
            self.f2_unit = QComboBox(); self.f2_unit.addItem("اختر وحدة", None)
            self.f2_warehouse = QComboBox(); self.f2_warehouse.addItem("كل المستودعات", None)
            lay.addWidget(QLabel("الوحدة المستفيدة:"), row, 2); lay.addWidget(self.f2_unit, row, 1, 1, 2); row += 1
            lay.addWidget(QLabel("المستودع:"), row, 2); lay.addWidget(self.f2_warehouse, row, 1, 1, 2); row += 1
        elif idx == 2:
            self.f3_warehouse = QComboBox(); self.f3_warehouse.addItem("كل المستودعات", None)
            self.f3_category = QComboBox(); self.f3_category.addItem("كل الفئات", None)
            self.f3_show_zero = QCheckBox("إظهار الأصناف الصفرية")
            lay.addWidget(QLabel("المستودع:"), row, 2); lay.addWidget(self.f3_warehouse, row, 1, 1, 2); row += 1
            lay.addWidget(QLabel("الفئة:"), row, 2); lay.addWidget(self.f3_category, row, 1, 1, 2); row += 1
            lay.addWidget(self.f3_show_zero, row, 1, 1, 3); row += 1
        elif idx == 3:
            add_date_row("فترة التحليل:", "f4_dt_from", "f4_dt_to")
            self.f4_warehouse = QComboBox(); self.f4_warehouse.addItem("كل المستودعات", None)
            self.f4_category = QComboBox(); self.f4_category.addItem("كل الفئات", None)
            self.f4_unit = QComboBox(); self.f4_unit.addItem("كل الوحدات", None)
            lay.addWidget(QLabel("المستودع:"), row, 2); lay.addWidget(self.f4_warehouse, row, 1, 1, 2); row += 1
            lay.addWidget(QLabel("الفئة:"), row, 2); lay.addWidget(self.f4_category, row, 1, 1, 2); row += 1
            lay.addWidget(QLabel("الوحدة:"), row, 2); lay.addWidget(self.f4_unit, row, 1, 1, 2); row += 1
        elif idx == 4:
            add_date_row("تاريخ الحصر:", "f5_dt_from", "f5_dt_to")
            self.f5_camp = QComboBox(); self.f5_camp.addItem("كل المعسكرات", None)
            lay.addWidget(QLabel("المعسكر:"), row, 2); lay.addWidget(self.f5_camp, row, 1, 1, 2); row += 1
        elif idx == 5:
            add_date_row("فترة التقييم:", "f6_dt_from", "f6_dt_to")
            self.f6_kitchen = QComboBox(); self.f6_kitchen.addItem("كل المطابخ", None)
            lay.addWidget(QLabel("المطبخ/الفرن:"), row, 2); lay.addWidget(self.f6_kitchen, row, 1, 1, 2); row += 1
        elif idx == 6:
            add_date_row("فترة التوريد:", "f7_dt_from", "f7_dt_to")
            self.f7_supplier = QComboBox(); self.f7_supplier.addItem("كل الموردين", None)
            self.f7_warehouse = QComboBox(); self.f7_warehouse.addItem("كل المستودعات", None)
            lay.addWidget(QLabel("المورد:"), row, 2); lay.addWidget(self.f7_supplier, row, 1, 1, 2); row += 1
            lay.addWidget(QLabel("المستودع:"), row, 2); lay.addWidget(self.f7_warehouse, row, 1, 1, 2); row += 1
        elif idx == 7:
            add_date_row("فترة المرتجعات:", "f8_dt_from", "f8_dt_to")
            self.f8_warehouse = QComboBox(); self.f8_warehouse.addItem("كل المستودعات", None)
            self.f8_reason = QComboBox(); self.f8_reason.addItems(["كل الأسباب", "تالف", "منتهي صلاحية", "زيادة", "أخرى"])
            lay.addWidget(QLabel("المستودع:"), row, 2); lay.addWidget(self.f8_warehouse, row, 1, 1, 2); row += 1
            lay.addWidget(QLabel("السبب:"), row, 2); lay.addWidget(self.f8_reason, row, 1, 1, 2); row += 1
        elif idx == 8:
            add_date_row("يوم العمل:", "f9_dt_from", "f9_dt_to")
            self.f9_warehouse = QComboBox(); self.f9_warehouse.addItem("كل المستودعات", None)
            lay.addWidget(QLabel("المستودع:"), row, 2); lay.addWidget(self.f9_warehouse, row, 1, 1, 2); row += 1
        lay.setRowStretch(row, 1)
        return page

    def _on_report_selected(self, current, previous):
        if not current:
            return
        idx = self.tree.indexOfTopLevelItem(current)
        if idx < 0:
            return
        self.current_report_idx = idx
        self.report_title = current.text(0)
        self.lbl_title.setText(self.report_title)
        self.filter_stack.setCurrentIndex(idx)
        self._clear_table()
        if self.api_service and idx == 1:
            self._load_units_combo()

    def _load_data(self):
        if not self.api_service:
            return
        ok, data = self.api_service.get_warehouses()
        if ok and data:
            self.warehouses_map = {d.get('id'): d.get('name') for d in data}
            for wid, wname in data:
                self.f1_warehouse.addItem(wname, wid)
                self.f3_warehouse.addItem(wname, wid)
                self.f4_warehouse.addItem(wname, wid)
                self.f7_warehouse.addItem(wname, wid)
                self.f8_warehouse.addItem(wname, wid)
                self.f9_warehouse.addItem(wname, wid)
        ok, data = self.api_service.get_units()
        if ok and data:
            self.units_map = {d.get('id'): d.get('name') for d in data}
            for uid, uname in data:
                self.f2_unit.addItem(uname, uid)
                self.f4_unit.addItem(uname, uid)
        ok, data = self.api_service.get_categories(limit=500)
        if ok and data:
            self.categories_map = {d.get('id'): d.get('name') for d in data}
            for cid, cname in data:
                self.f1_category.addItem(cname, cid)
                self.f3_category.addItem(cname, cid)
                self.f4_category.addItem(cname, cid)
        ok, data = self.api_service.get_suppliers()
        if ok and data:
            self.suppliers_map = {d.get('id'): d.get('name') for d in data}
            for sid, sname in data:
                self.f7_supplier.addItem(sname, sid)
        # Load camps for strength report (idx=4)
        ok, data = self.api_service.get_camps()
        if ok and data:
            self.camps_map = {d.get('id'): d.get('name') for d in data}
            for cid, cname in data:
                self.f5_camp.addItem(cname, cid)
        # Load facilities for kitchen performance report (idx=5)
        ok, data = self.api_service.get_facilities()
        if ok and data:
            self.facilities_map = {d.get('id'): d.get('name') for d in data}
            for fid, fname in data:
                self.f6_kitchen.addItem(fname, fid)

    def _load_units_combo(self):
        if not self.api_service:
            return
        ok, data = self.api_service.get_units()
        if ok and data:
            self.units_map = {d.get('id'): d.get('name') for d in data}
            for uid, uname in self.units_map.items():
                self.f2_unit.addItem(uname, uid)

    def _get_date_range(self, from_widget, to_widget):
        return (from_widget.dateTime().toString("yyyy-MM-dd"),
                to_widget.dateTime().toString("yyyy-MM-dd"))

    def _format_number(self, val):
        if val is None:
            return "-"
        try:
            return f"{float(val):,.2f}" if isinstance(val, (int, float)) else str(val)
        except (ValueError, TypeError):
            return str(val)

    def _clear_table(self):
        self.table.setRowCount(0)
        self.table.setColumnCount(0)
        self._results = []

    def _display_results(self, data: list, headers: list):
        if not data:
            QMessageBox.information(self, "تقرير فارغ", "لا توجد بيانات للعرض.")
            self._clear_table()
            return
        self._results = data
        self.table.setColumnCount(len(headers))
        self.table.setHorizontalHeaderLabels(headers)
        self.table.setRowCount(len(data))
        for r, row_data in enumerate(data):
            for c, val in enumerate(row_data):
                item = QTableWidgetItem(self._format_number(val))
                item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(r, c, item)
        self.table.resizeColumnsToContents()

    def _run_report(self):
        if not self.api_service:
            QMessageBox.warning(self, "خطأ", "الخدمة غير متوفرة.")
            return
        idx = self.current_report_idx
        if idx < 0 or idx >= len(REPORT_LIST):
            return
        self._load_data()
        params = {}
        dt_from = getattr(self, f"f{idx+1}_dt_from", None)
        dt_to = getattr(self, f"f{idx+1}_dt_to", None)
        if dt_from and dt_to:
            from_str, to_str = self._get_date_range(dt_from, dt_to)
            params['date_from'] = from_str
            params['date_to'] = to_str
        ok, data = self._execute_api(idx, params)
        if ok and data:
            headers = list(data[0].keys()) if isinstance(data[0], dict) else ["العمود 1", "العمود 2"]
            rows = [list(row.values()) if isinstance(row, dict) else [row] for row in data]
            self._display_results(rows, headers)
        else:
            self._clear_table()
            msg = "حدث خطأ أثناء جلب البيانات." if not ok else "لا توجد بيانات لهذا التقرير."
            QMessageBox.information(self, "نتيجة التقرير", msg)

    def _execute_api(self, report_idx, params):
        """تنفيذ استعلام API حسب نوع التقرير."""
        try:
            if report_idx == 0:
                return self.api_service.report_daily_movements(params)
            elif report_idx == 1:
                unit_id = self.f2_unit.currentData() if self.f2_unit.count() > 1 else None
                if not unit_id:
                    return (False, [])
                return self.api_service.report_unit_account(unit_id, params)
            elif report_idx == 2:
                wh_id = self.f3_warehouse.currentData() if self.f3_warehouse else None
                params['warehouse_id'] = wh_id if wh_id else None
                if getattr(self, 'f3_show_zero', None) and self.f3_show_zero.isChecked():
                    params['show_zero'] = True
                return self.api_service.report_current_stock(params)
            elif report_idx == 3:
                wh_id = self.f4_warehouse.currentData() if self.f4_warehouse else None
                cat_id = self.f4_category.currentData() if self.f4_category else None
                unit_id = self.f4_unit.currentData() if self.f4_unit else None
                params['warehouse_id'] = wh_id if wh_id else None
                params['category_id'] = cat_id if cat_id else None
                params['unit_id'] = unit_id if unit_id else None
                return self.api_service.report_consumption(params)
            elif report_idx == 4:
                camp_id = self.f5_camp.currentData() if self.f5_camp else None
                params['camp_id'] = camp_id if camp_id else None
                return self.api_service.report_strength(params)
            elif report_idx == 5:
                kitchen_id = self.f6_kitchen.currentData() if self.f6_kitchen else None
                params['facility_id'] = kitchen_id if kitchen_id else None
                return self.api_service.report_kitchen_performance(params)
            elif report_idx == 6:
                sup_id = self.f7_supplier.currentData() if self.f7_supplier else None
                params['supplier_id'] = sup_id if sup_id else None
                return self.api_service.report_supplier_summary(params)
            elif report_idx == 7:
                wh_id = self.f8_warehouse.currentData() if self.f8_warehouse else None
                params['warehouse_id'] = wh_id if wh_id else None
                reason = self.f8_reason.currentText() if self.f8_reason else ""
                if reason not in ("كل الأسباب", ""):
                    params['reason'] = reason
                return self.api_service.report_returns(params)
            elif report_idx == 8:
                wh_id = self.f9_warehouse.currentData() if self.f9_warehouse else None
                params['warehouse_id'] = wh_id if wh_id else None
                return self.api_service.report_transfers_history(params)
            else:
                return (False, [])
        except Exception as e:
            QMessageBox.critical(self, "خطأ", f"فشل استدعاء التقرير: {e}")
            return (False, [])

    def _export_excel(self):
        if self._results:
            from excel_helper import export_table_to_excel
            export_table_to_excel(self.table, self, 'report.xlsx')
        else:
            QMessageBox.information(self, "تصدير البيانات", "لا توجد بيانات للتصدير.")

    def _print_report(self):
        """Print the selected report as an HTML document."""
        # Get table headers from the first row (header row)
        headers = []
        for j in range(self.table.columnCount()):
            h = self.table.horizontalHeaderItem(j)
            headers.append(h.text() if h else f"عمود {j+1}")

        # Get data rows (all rows)
        rows = []
        for i in range(self.table.rowCount()):
            row = []
            for j in range(self.table.columnCount()):
                item = self.table.item(i, j)
                row.append(item.text() if item else '')
            rows.append(row)

        # Build HTML content with RTL support
        header_cells = ''.join(f'<th>{h}</th>' for h in headers)
        body_rows = ''
        for row in rows:
            cells = ''.join(f'<td>{c}</td>' for c in row)
            body_rows += f'<tr>{cells}</tr>'

        title_text = self.report_title or "تقرير"

        html_content = f"""<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
    body {{ font-family: 'Arial', 'Tahoma', sans-serif; font-size: 11pt; }}
    h2 {{ text-align: center; color: #C0392B; margin-bottom: 20px; }}
    table {{ width: 100%; border-collapse: collapse; margin: 10px 0; }}
    th, td {{ border: 1px solid #333; padding: 6px 10px; text-align: center; }}
    th {{ background-color: #f0f0f0; font-weight: bold; }}
    tr:nth-child(even) {{ background-color: #fafafa; }}
    .footer {{ margin-top: 30px; text-align: center; font-size: 10pt; color: #777; }}
</style>
</head>
<body>
    <h2>{title_text}</h2>
    <table>
        <thead>
            <tr>{header_cells}</tr>
        </thead>
        <tbody>
            {body_rows}
        </tbody>
    </table>
    <div class="footer">تاريخ الطباعة: {__import__('datetime').date.today()}</div>
</body>
</html>"""

        from print_helper import _print_html
        _print_html(self, html_content)
