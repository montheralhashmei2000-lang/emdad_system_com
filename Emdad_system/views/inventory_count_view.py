"""شاشات الجرد المخزني فقط."""
from __future__ import annotations

import base64

from PyQt6.QtCore import Qt, QDate
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QComboBox, QDateEdit,
    QLineEdit, QPushButton, QTableWidget, QTableWidgetItem, QHeaderView,
    QMessageBox, QFrame, QGridLayout, QTabWidget, QAbstractItemView,
    QFormLayout, QTextEdit, QFileDialog, QCheckBox,
)
from api_service import ApiService
from theme import make_header_label, COLORS
from print_helper import print_inventory_count_form, print_inventory_count_variances


def _call(api, method, *args, **kwargs):
    try:
        return method(*args, **kwargs)
    except Exception:
        return False, {}


class InventoryCountView(QWidget):
    """واجهة إدارة الجرد: إنشاء الأمر، العد، الفروقات، الاعتماد، والسجل."""

    TAB_TITLES = ("إنشاء أمر جرد", "العد الفعلي", "تحليل الفروقات", "التسوية والاعتماد", "سجل الجرد")

    def __init__(self, parent=None, api_service=None):
        super().__init__(parent)
        self.api = api_service or ApiService()
        self.current_count_id = None
        self.current_detail = {}
        self.setLayoutDirection(Qt.LayoutDirection.RightToLeft)
        self._build()
        self._load_warehouses()
        self._load_items()
        self._load_counts()

    def _build(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(16, 16, 16, 16)
        root.setSpacing(10)
        root.addWidget(make_header_label("إدارة الجرد المخزني (Stocktaking)"))
        self.tabs = QTabWidget()
        self.tabs.setLayoutDirection(Qt.LayoutDirection.RightToLeft)
        self.tabs.setStyleSheet("""
            QTabWidget::pane{border:1px solid #c9c7b9;background:#f5f4ef;}
            QTabBar::tab{background:#eeede7;color:#314333;padding:10px 18px;margin-left:2px;border-top-left-radius:8px;border-top-right-radius:8px;}
            QTabBar::tab:selected{background:#2e7039;color:white;font-weight:bold;}
            QTableWidget{background:white;gridline-color:#e5e2d8;}
            QHeaderView::section{background:#2e7039;color:white;padding:10px;font-weight:bold;border:0;}
        """)
        root.addWidget(self.tabs, 1)
        self.pages = [QWidget() for _ in self.TAB_TITLES]
        for page, title in zip(self.pages, self.TAB_TITLES):
            self.tabs.addTab(page, title)
        self._build_create()
        self._build_count()
        self._build_variance()
        self._build_approval()
        self._build_log()

    @staticmethod
    def _button(text, color="#2e7039"):
        b = QPushButton(text)
        b.setMinimumHeight(42)
        b.setStyleSheet(f"QPushButton{{background:{color};color:white;border:0;border-radius:7px;padding:8px 16px;font-weight:bold}} QPushButton:hover{{background:{color}dd}}")
        return b

    @staticmethod
    def _table(headers, stretch_cols=()):
        t = QTableWidget(0, len(headers))
        t.setHorizontalHeaderLabels(headers)
        t.setAlternatingRowColors(True)
        t.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        t.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        t.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.ResizeToContents)
        for col in stretch_cols:
            t.horizontalHeader().setSectionResizeMode(col, QHeaderView.ResizeMode.Stretch)
        t.verticalHeader().setVisible(False)
        return t

    @staticmethod
    def _put(table, row, col, value):
        table.setItem(row, col, QTableWidgetItem("" if value is None else str(value)))

    def _count_picker(self, layout, slot):
        row = QHBoxLayout()
        row.addWidget(QLabel("أمر الجرد المفتوح:"))
        combo = QComboBox()
        combo.setMinimumWidth(350)
        combo.currentIndexChanged.connect(lambda _=0: self._select_count(combo))
        setattr(self, slot, combo)
        row.addWidget(combo)
        layout.addLayout(row)
        return combo

    def _build_create(self):
        layout = QHBoxLayout(self.pages[0])
        formbox = QFrame(); formbox.setStyleSheet("QFrame{background:#f5f4ef;border:1px solid #d0cec2;border-radius:6px;padding:8px}")
        form = QFormLayout(formbox); form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        self.wh_create = QComboBox()
        self.type_create = QComboBox(); self.type_create.addItem("جرد كامل (FULL)", "FULL"); self.type_create.addItem("جرد جزئي (PARTIAL)", "PARTIAL")
        self.category_create = QComboBox(); self.category_create.addItem("جميع الأصناف", None)
        self.date_create = QDateEdit(QDate.currentDate()); self.date_create.setCalendarPopup(True); self.date_create.setDisplayFormat("yyyy/MM/dd")
        self.committee_create = QLineEdit(); self.committee_create.setPlaceholderText("أسماء أعضاء اللجنة (مفصولين بفاصلة)")
        self.freeze_create = QCheckBox("تجميد المستودع (منع الحركات حتى الاعتماد)"); self.freeze_create.setChecked(True)
        self.notes_create = QLineEdit(); self.notes_create.setPlaceholderText("ملاحظات")
        for label, widget in (("المستودع:", self.wh_create), ("نوع الجرد:", self.type_create), ("التصنيف (للجرد الجزئي):", self.category_create), ("تاريخ البدء:", self.date_create), ("أعضاء اللجنة:", self.committee_create), ("تجميد المخزون:", self.freeze_create), ("ملاحظات:", self.notes_create)):
            form.addRow(QLabel(label), widget)
        self.btn_create = self._button("✅ إنشاء أمر الجرد وسحب الأرصدة الدفترية")
        self.btn_create.clicked.connect(self._create_count)
        form.addRow(self.btn_create)
        layout.addWidget(formbox, 1)
        pending = QVBoxLayout()
        pending.addWidget(QLabel("أوامر الجرد قيد التنفيذ:"))
        self.tbl_pending = self._table(["رقم الأمر", "المستودع", "النوع", "التاريخ", "الحالة"], (1,))
        self.tbl_pending.doubleClicked.connect(lambda: self._open_row(self.tbl_pending))
        pending.addWidget(self.tbl_pending, 1)
        layout.addLayout(pending, 1)

    def _build_count(self):
        layout = QVBoxLayout(self.pages[1]); self._count_picker(layout, "count_picker")
        actions = QHBoxLayout()
        self.btn_print_form = self._button("🖨️ طباعة استمارة الجرد (فارغة)")
        self.btn_attach = self._button("📷 إرفاق صورة الجرد اليومي")
        self.btn_add_item = self._button("➕ إضافة صنف مكتشف", "#c69f20")
        self.item_picker = QComboBox()
        self.btn_print_form.clicked.connect(self._print_form)
        self.btn_attach.clicked.connect(self._upload_attachment)
        self.btn_add_item.clicked.connect(self._add_item)
        actions.addWidget(self.btn_print_form); actions.addWidget(self.btn_attach); actions.addStretch(); actions.addWidget(self.item_picker); actions.addWidget(self.btn_add_item)
        layout.addLayout(actions)
        self.search_count = QLineEdit(); self.search_count.setPlaceholderText("🔍 بحث في الجدول برقم أو اسم الصنف...")
        self.search_count.textChanged.connect(self._filter_count_rows)
        layout.addWidget(self.search_count)
        self.tbl_actual = self._table(["الكود", "الصنف", "الوحدة 1", "الفعلي 1", "الوحدة 2", "الفعلي 2", "الوحدة 3", "الفعلي 3"], (1,))
        self.tbl_actual.setEditTriggers(QAbstractItemView.EditTrigger.DoubleClicked | QAbstractItemView.EditTrigger.EditKeyPressed)
        layout.addWidget(self.tbl_actual, 1)
        row = QHBoxLayout(); row.addStretch()
        self.btn_save_actual = self._button("💾 حفظ العد الفعلي")
        self.btn_save_actual.clicked.connect(self._save_actual)
        row.addWidget(self.btn_save_actual); layout.addLayout(row)

    def _build_variance(self):
        layout = QVBoxLayout(self.pages[2]); self._count_picker(layout, "variance_picker")
        row = QHBoxLayout(); row.addStretch()
        self.btn_print_variance = self._button("🖨️ تقرير الفروقات")
        self.btn_print_variance.clicked.connect(self._print_variance); row.addWidget(self.btn_print_variance); layout.addLayout(row)
        self.tbl_variance = self._table(["الصنف", "دفتر 1", "فعلي 1", "فرق 1", "دفتر 2", "فعلي 2", "فرق 2", "دفتر 3", "فعلي 3", "فرق 3", "السبب", "القرار"], (0, 10, 11))
        self.tbl_variance.setEditTriggers(QAbstractItemView.EditTrigger.DoubleClicked | QAbstractItemView.EditTrigger.EditKeyPressed)
        layout.addWidget(self.tbl_variance, 1)
        row = QHBoxLayout(); row.addStretch()
        self.btn_save_variance = self._button("💾 حفظ الأسباب والقرارات")
        self.btn_save_variance.clicked.connect(self._save_reasons); row.addWidget(self.btn_save_variance); layout.addLayout(row)

    def _build_approval(self):
        layout = QVBoxLayout(self.pages[3]); self._count_picker(layout, "approval_picker")
        self.summary = QFrame(); self.summary.setFrameShape(QFrame.Shape.StyledPanel)
        grid = QGridLayout(self.summary); grid.setColumnStretch(1, 1)
        self.summary_values = {}
        for r, key, label in ((0, "count_number", "رقم الأمر:"), (1, "warehouse_name", "المستودع:"), (2, "total", "إجمالي الأصناف:"), (3, "counted", "تم جردها:"), (4, "variances", "أصناف بها فروقات:")):
            grid.addWidget(QLabel(label), r, 1); value = QLabel("—"); grid.addWidget(value, r, 0); self.summary_values[key] = value
        layout.addWidget(self.summary)
        row = QHBoxLayout(); row.addStretch()
        self.btn_cancel = self._button("❌ إلغاء أمر الجرد (رفع التجميد)", "#bd372b")
        self.btn_approve = self._button("✅ اعتماد التسوية وإغلاق الجرد")
        self.btn_cancel.clicked.connect(self._cancel); self.btn_approve.clicked.connect(self._approve)
        row.addWidget(self.btn_cancel); row.addWidget(self.btn_approve); layout.addLayout(row); layout.addStretch()

    def _build_log(self):
        layout = QVBoxLayout(self.pages[4]); row = QHBoxLayout(); row.addStretch()
        self.btn_refresh = self._button("🔄 تحديث")
        self.btn_refresh.clicked.connect(self._load_counts); row.addWidget(self.btn_refresh); layout.addLayout(row)
        self.tbl_log = self._table(["رقم الأمر", "المستودع", "النوع", "تاريخ البدء", "تاريخ الإغلاق", "الأصناف", "الفروقات", "الحالة"], (1,))
        self.tbl_log.doubleClicked.connect(lambda: self._open_row(self.tbl_log))
        layout.addWidget(self.tbl_log, 1)

    def _load_warehouses(self):
        ok, data = _call(self.api, self.api.get_warehouses)
        if ok and isinstance(data, list):
            for combo in (self.wh_create,):
                combo.addItem("— اختر المستودع —", None)
                for wh in data: combo.addItem(wh.get("name", ""), wh.get("id"))

    def _load_items(self):
        ok, data = _call(self.api, self.api.get_items)
        if ok and isinstance(data, list):
            self.category_create.addItem("جميع الأصناف", None)
            for item in data:
                self.category_create.addItem(item.get("name", ""), item.get("id"))
                self.item_picker.addItem(item.get("name", ""), item.get("id"))
        # remove duplicate initial category placeholder
        if self.category_create.count() > 1 and self.category_create.itemText(0) == "جميع الأصناف":
            self.category_create.removeItem(0)
            self.category_create.insertItem(0, "جميع الأصناف", None)

    def _load_counts(self):
        ok, data = _call(self.api, self.api.get_inventory_counts, None, None)
        counts = data if ok and isinstance(data, list) else []
        self.count_picker.blockSignals(True); self.variance_picker.blockSignals(True); self.approval_picker.blockSignals(True)
        combos = (self.count_picker, self.variance_picker, self.approval_picker)
        for c in combos: c.clear(); c.addItem("--- اختر أمر الجرد ---", None)
        for t in (self.tbl_log, self.tbl_pending): t.setRowCount(len(counts))
        for row, item in enumerate(counts):
            cid = item.get("id"); text = f"{item.get('count_number', cid)} - {item.get('warehouse_name', '')}"
            for c in combos: c.addItem(text, cid)
            cols = [item.get("count_number", cid), item.get("warehouse_name", ""), item.get("count_type", "FULL"), item.get("start_date", item.get("count_date", "")), item.get("close_date", ""), item.get("items_count", ""), item.get("variance_count", ""), item.get("status", "")]
            for col, val in enumerate(cols): self._put(self.tbl_log, row, col, val)
            for col, val in enumerate((cols[0], cols[1], cols[2], cols[3], cols[7])): self._put(self.tbl_pending, row, col, val)
            self.tbl_log.item(row, 0).setData(Qt.ItemDataRole.UserRole, cid)
            self.tbl_pending.item(row, 0).setData(Qt.ItemDataRole.UserRole, cid)
        for c in combos: c.blockSignals(False)
        self._load_selected_if_any()

    def _load_selected_if_any(self):
        # Preserve the selected order across refreshes where possible.
        for combo in (self.count_picker, self.variance_picker, self.approval_picker):
            if combo.currentData() is not None:
                self._select_count(combo); return

    def _select_count(self, combo):
        count_id = combo.currentData()
        if count_id is None: return
        self.current_count_id = count_id
        ok, data = _call(self.api, self.api.get_inventory_count_detail, count_id)
        if not ok or not isinstance(data, dict): return
        self.current_detail = data
        self._populate_detail(data)

    def _populate_detail(self, data):
        items = data.get("items", []) or []
        self.tbl_actual.setRowCount(len(items)); self.tbl_variance.setRowCount(len(items))
        variance_count = 0; counted = 0
        for row, item in enumerate(items):
            self._put(self.tbl_actual, row, 0, item.get("item_code", item.get("code", item.get("item_id", ""))))
            self._put(self.tbl_actual, row, 1, item.get("item_name", item.get("name", "")))
            units = item.get("units", [])
            for unit in range(3):
                u = units[unit] if len(units) > unit else {}
                record = u.get("recorded_quantity", item.get("recorded_quantity", 0)) if isinstance(u, dict) else 0
                actual = u.get("actual_quantity", "") if isinstance(u, dict) else ""
                uname = u.get("unit_name", "") if isinstance(u, dict) else ""
                self._put(self.tbl_actual, row, 2 + unit * 2, uname)
                cell = QTableWidgetItem(str(actual if actual is not None else "")); cell.setFlags(cell.flags() | Qt.ItemFlag.ItemIsEditable)
                self.tbl_actual.setItem(row, 3 + unit * 2, cell)
                if unit == 0:
                    # Retain backend row identity and book value as user data.
                    self.tbl_actual.item(row, 0).setData(Qt.ItemDataRole.UserRole, item.get("id", item.get("item_id")))
                    self.tbl_actual.item(row, 0).setData(Qt.ItemDataRole.UserRole + 1, record)
            for col, key in ((1, "recorded_quantity"), (2, "actual_quantity")):
                self._put(self.tbl_variance, row, col, item.get(key, ""))
            diff = item.get("variance", "")
            self._put(self.tbl_variance, row, 3, diff)
            for unit in range(1, 4):
                self._put(self.tbl_variance, row, 4 + (unit - 1) * 3, item.get(f"recorded_quantity_{unit}", ""))
                self._put(self.tbl_variance, row, 5 + (unit - 1) * 3, item.get(f"actual_quantity_{unit}", ""))
                self._put(self.tbl_variance, row, 6 + (unit - 1) * 3, item.get(f"variance_{unit}", ""))
            self._put(self.tbl_variance, row, 0, item.get("item_name", item.get("name", "")))
            for col, val in ((10, item.get("reason", "")), (11, item.get("decision", ""))):
                cell = QTableWidgetItem(str(val)); cell.setFlags(cell.flags() | Qt.ItemFlag.ItemIsEditable); self.tbl_variance.setItem(row, col, cell)
            if item.get("actual_quantity") is not None: counted += 1
            try: variance_count += int(float(diff) != 0)
            except (TypeError, ValueError): pass
        self.summary_values["count_number"].setText(str(data.get("count_number", data.get("id", "—"))))
        self.summary_values["warehouse_name"].setText(str(data.get("warehouse_name", "—")))
        self.summary_values["total"].setText(str(len(items))); self.summary_values["counted"].setText(str(counted)); self.summary_values["variances"].setText(str(variance_count))

    def _create_count(self):
        warehouse_id = self.wh_create.currentData()
        if warehouse_id is None:
            QMessageBox.warning(self, "تنبيه", "يرجى اختيار المستودع")
            return
        payload = {"warehouse_id": warehouse_id, "count_date": self.date_create.date().toString("yyyy-MM-dd"), "reason": self.notes_create.text().strip(), "count_type": self.type_create.currentData(), "category_id": self.category_create.currentData(), "committee_members": self.committee_create.text().strip(), "freeze_warehouse": self.freeze_create.isChecked()}
        ok, _ = _call(self.api, self.api.create_inventory_count, payload)
        if ok:
            QMessageBox.information(self, "نجاح", "تم إنشاء أمر الجرد")
            self._load_counts(); self.tabs.setCurrentIndex(4)
        else: QMessageBox.critical(self, "خطأ", "تعذر إنشاء أمر الجرد")

    def _open_row(self, table):
        row = table.currentRow()
        if row < 0: return
        count_id = self.tbl_log.item(row, 0).data(Qt.ItemDataRole.UserRole) if table is self.tbl_log else self.tbl_pending.item(row, 0).data(Qt.ItemDataRole.UserRole)
        # Fallback: resolve ID from the displayed order number.
        if count_id is None:
            number = table.item(row, 0).text()
            count_id = next((self.count_picker.itemData(i) for i in range(self.count_picker.count()) if self.count_picker.itemText(i).startswith(number)), None)
        combo = self.count_picker
        idx = combo.findData(count_id)
        if idx >= 0: combo.setCurrentIndex(idx)
        self.tabs.setCurrentIndex(4 if table is self.tbl_log else 1)

    def _save_actual(self):
        if self.current_count_id is None: return self._need_count()
        values = []
        for row in range(self.tbl_actual.rowCount()):
            first = self.tbl_actual.item(row, 0); item_id = first.data(Qt.ItemDataRole.UserRole) if first else None
            if item_id is None: item_id = first.text() if first else None
            entry = {"item_id": item_id}
            for unit in range(3):
                cell = self.tbl_actual.item(row, 3 + unit * 2)
                text = cell.text().strip() if cell else ""
                if text:
                    try: entry["actual_quantity" if unit == 0 else f"actual_quantity_{unit + 1}"] = float(text)
                    except ValueError: QMessageBox.warning(self, "تنبيه", "تأكد من إدخال كميات صحيحة"); return
            values.append(entry)
        ok, _ = _call(self.api, self.api.update_inventory_count_items, self.current_count_id, values)
        if ok: QMessageBox.information(self, "نجاح", "تم حفظ العد الفعلي"); self._refresh_detail()
        else: QMessageBox.critical(self, "خطأ", "تعذر حفظ العد الفعلي")

    def _save_reasons(self):
        if self.current_count_id is None: return self._need_count()
        values = []
        for row in range(self.tbl_variance.rowCount()):
            first = self.tbl_actual.item(row, 0)
            values.append({"item_id": first.data(Qt.ItemDataRole.UserRole) if first else None, "reason": self.tbl_variance.item(row, 10).text() if self.tbl_variance.item(row, 10) else "", "decision": self.tbl_variance.item(row, 11).text() if self.tbl_variance.item(row, 11) else ""})
        ok, _ = _call(self.api, self.api.update_inventory_count_reasons, self.current_count_id, values)
        if ok: QMessageBox.information(self, "نجاح", "تم حفظ الأسباب والقرارات"); self._refresh_detail()
        else: QMessageBox.critical(self, "خطأ", "تعذر حفظ الأسباب والقرارات")

    def _add_item(self):
        if self.current_count_id is None: return self._need_count()
        item_id = self.item_picker.currentData()
        if item_id is None: return
        ok, _ = _call(self.api, self.api.add_item_to_inventory_count, self.current_count_id, item_id)
        if ok: self._refresh_detail()
        else: QMessageBox.critical(self, "خطأ", "تعذر إضافة الصنف")

    def _refresh_detail(self):
        if self.current_count_id is not None:
            ok, data = _call(self.api, self.api.get_inventory_count_detail, self.current_count_id)
            if ok and isinstance(data, dict): self.current_detail = data; self._populate_detail(data)

    def _need_count(self): QMessageBox.warning(self, "تنبيه", "اختر أمر الجرد أولاً")

    def _approve(self):
        if self.current_count_id is None: return self._need_count()
        ok, _ = _call(self.api, self.api.approve_inventory_count, self.current_count_id)
        if ok: QMessageBox.information(self, "نجاح", "تم اعتماد التسوية وإغلاق الجرد"); self._load_counts()
        else: QMessageBox.critical(self, "خطأ", "تعذر اعتماد الجرد")

    def _cancel(self):
        if self.current_count_id is None: return self._need_count()
        ok, _ = _call(self.api, self.api.cancel_inventory_count, self.current_count_id)
        if ok: QMessageBox.information(self, "نجاح", "تم إلغاء أمر الجرد"); self._load_counts()
        else: QMessageBox.critical(self, "خطأ", "تعذر إلغاء الجرد")

    def _upload_attachment(self):
        if self.current_count_id is None: return self._need_count()
        path, _ = QFileDialog.getOpenFileName(self, "إرفاق صورة الجرد", "", "Images (*.png *.jpg *.jpeg *.bmp);;All files (*.*)")
        if not path: return
        try:
            with open(path, "rb") as f: encoded = base64.b64encode(f.read()).decode("ascii")
            ok, _ = _call(self.api, self.api.upload_inventory_count_attachment, self.current_count_id, encoded)
            if not ok: QMessageBox.critical(self, "خطأ", "تعذر إرفاق الصورة")
        except OSError as exc: QMessageBox.critical(self, "خطأ", str(exc))

    def _print_form(self):
        if self.current_count_id is None: return self._need_count()
        self._refresh_detail(); print_inventory_count_form(self, self.current_detail)

    def _print_variance(self):
        if self.current_count_id is None: return self._need_count()
        self._refresh_detail(); print_inventory_count_variances(self, self.current_detail)

    def _filter_count_rows(self, text):
        needle = text.strip().casefold()
        for row in range(self.tbl_actual.rowCount()):
            item = self.tbl_actual.item(row, 1)
            code = self.tbl_actual.item(row, 0)
            shown = not needle or needle in (item.text() if item else "").casefold() or needle in (code.text() if code else "").casefold()
            self.tbl_actual.setRowHidden(row, not shown)
