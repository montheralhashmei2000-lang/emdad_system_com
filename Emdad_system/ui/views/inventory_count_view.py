"""Inventory Count View - إدارة جرد المخزون (5 تبويبات)."""
from __future__ import annotations
from PyQt6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QComboBox, QDateEdit, QLineEdit, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QMessageBox, QFrame, QGridLayout,
    QTabWidget, QTextEdit, QAbstractItemView, QGroupBox, QFormLayout,
    QFileDialog)
from PyQt6.QtCore import Qt, QDate, QUrl as QtCoreQUrl
from PyQt6.QtGui import QColor, QDesktopServices
from ui.api_service import ApiService
from ui.theme import make_header_label, COLORS
from ..print_helper import print_inventory_count_form, print_inventory_count_variances


def _api(api, fn, *args, **kwargs):
    """Normalize backend responses: they return (success, data)."""
    try:
        return fn(*args, **kwargs)
    except Exception:
        return False, {}


class InventoryCountView(QWidget):
    """/screen جرد المخزون - خمسة تبويبات: إنشاء، قائمة، أصناف، مرفقات، تقارير."""

    def __init__(self, parent=None, api_service=None):
        super().__init__(parent)
        self.api = api_service or ApiService()
        self.setLayoutDirection(Qt.LayoutDirection.RightToLeft)
        self._init_ui()
        self._load_warehouses()
        self._load_items()
        self._load_counts()

    def _init_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(16, 16, 16, 16)
        root.setSpacing(14)
        root.addWidget(make_header_label("📦 جرد المخزون"))

        self.tabs = QTabWidget()
        self.tabs.setStyleSheet(_tab_style())
        root.addWidget(self.tabs)

        self._tab_create = QWidget()
        self._tab_list = QWidget()
        self._tab_items = QWidget()
        self._tab_attachments = QWidget()
        self._tab_reports = QWidget()

        self.tabs.addTab(self._tab_create, "➕ إنشاء جرد جديد")
        self.tabs.addTab(self._tab_list, "📋 قائمة الجرد")
        self.tabs.addTab(self._tab_items, "📦 أصناف الجرد")
        self.tabs.addTab(self._tab_attachments, "🗂️ المرفقات")
        self.tabs.addTab(self._tab_reports, "📊 التقارير")

        self._build_create_tab()
        self._build_list_tab()
        self._build_items_tab()
        self._build_attachments_tab()
        self._build_reports_tab()
        self._tab_list_current()

    def _card(self):
        f = QFrame()
        f.setStyleSheet(f"QFrame{{background:{COLORS['bg_card']};border:1px solid {COLORS['border']};border-radius:10px;padding:12px;}}")
        return f

    @staticmethod
    def _line_style():
        return (f"QLineEdit{{background:white;border:1px solid {COLORS['border']};"
                f"border-radius:6px;padding:6px 10px;color:{COLORS['text']};}}"
                f"QLineEdit:hover{{border-color:{COLORS['PRIMARY']};}}"
                f"QLineEdit:focus{{border-color:{COLORS['PRIMARY']};background:#f0fff4;}}")

    @staticmethod
    def _combo_style():
        return (f"QComboBox{{background:white;border:1px solid {COLORS['border']};"
                f"border-radius:6px;padding:6px 10px;color:{COLORS['text']};}}"
                f"QComboBox:hover{{border-color:{COLORS['PRIMARY']};}}"
                f"QComboBox::drop-down{{border:none;}}")

    @staticmethod
    def _btn(text, color):
        btn = QPushButton(text)
        btn.setStyleSheet(f"""
            QPushButton {{
                background-color: {color};
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 6px;
                font-weight: bold;
            }}
            QPushButton:hover {{
                background-color: {color}dd;
            }}
            QPushButton:pressed {{
                background-color: {color}bb;
            }}
        """)
        return btn

    @staticmethod
    def _tab_style():
        return """
            QTabWidget::pane {
                border: 1px solid #E5E7EB;
                border-radius: 8px;
                background: white;
                margin-top: -1px;
            }
            QTabBar::tab {
                background: #F3F4F6;
                color: #6B7280;
                border: 1px solid #E5E7EB;
                border-bottom: none;
                border-top-left-radius: 6px;
                border-top-right-radius: 6px;
                padding: 10px 16px;
                margin-right: 2px;
            }
            QTabBar::tab:selected {
                background: white;
                color: #10B981;
                border-color: #E5E7EB;
                border-bottom: 2px solid #10B981;
            }
            QTabBar::tab:!selected:hover {
                background: #E5E7EB;
            }
        """

    # ----------------------------------------------------------- CREATE TAB
    def _build_create_tab(self):
        lay = QVBoxLayout(self._tab_create)
        lay.setSpacing(14)
        card = self._card()
        form = QFormLayout(card)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        form.setFormAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        form.setHorizontalSpacing(12)
        form.setVerticalSpacing(10)

        self.wh_cb_create = QComboBox()
        self.wh_cb_create.setStyleSheet(self._combo_style())
        self.wh_cb_create.addItem("— اختر المستودع —", None)
        form.addRow(QLabel("🏭 المستودع:"), self.wh_cb_create)

        self.date_cb_create = QDateEdit()
        self.date_cb_create.setCalendarPopup(True)
        self.date_cb_create.setDate(QDate.currentDate())
        self.date_cb_create.setStyleSheet(self._line_style())
        form.addRow(QLabel("📅 تاريخ الجرد:"), self.date_cb_create)

        self.reason_le_create = QLineEdit()
        self.reason_le_create.setPlaceholderText("سبب الجرد (اختياري)")
        self.reason_le_create.setStyleSheet(self._line_style())
        form.addRow(QLabel("📝 سبب الجرد:"), self.reason_le_create)

        lay.addWidget(card)

        btn_row = QHBoxLayout()
        self.btn_save = self._btn("حفظ الجرد", COLORS['PRIMARY'])
        self.btn_save.clicked.connect(self._save_count)
        self.btn_clear = self._btn("مسح النموذج", COLORS['DANGER'])
        self.btn_clear.clicked.connect(self._clear_create_form)
        btn_row.addWidget(self.btn_save)
        btn_row.addWidget(self.btn_clear)
        btn_row.addStretch()
        lay.addLayout(btn_row)
        lay.addStretch()

    # ----------------------------------------------------------- LIST TAB
    def _build_list_tab(self):
        lay = QVBoxLayout(self._tab_list)
        lay.setSpacing(12)
        card = self._card()
        cl = QGridLayout(card)
        cl.setHorizontalSpacing(10)
        cl.setVerticalSpacing(8)

        self.wh_cb_filter = QComboBox()
        self.wh_cb_filter.setStyleSheet(self._combo_style())
        self.wh_cb_filter.addItem("— جميع المستودعات —", None)
        self.wh_cb_filter.currentIndexChanged.connect(self._load_counts)
        cl.addWidget(QLabel("🏭 المستودع:"), 0, 0)
        cl.addWidget(self.wh_cb_filter, 0, 1)

        self.status_cb_filter = QComboBox()
        self.status_cb_filter.setStyleSheet(self._combo_style())
        self.status_cb_filter.addItems(["— جميع الحالات —", "مسودة", "مكتمل", "معتمد", "ملغي"])
        self.status_cb_filter.currentIndexChanged.connect(self._load_counts)
        cl.addWidget(QLabel("📋 الحالة:"), 0, 2)
        cl.addWidget(self.status_cb_filter, 0, 3)

        self.search_le = QLineEdit()
        self.search_le.setPlaceholderText("ابحث برقم الجرد أو الملاحظات...")
        self.search_le.setStyleSheet(self._line_style())
        self.search_le.returnPressed.connect(self._load_counts)
        cl.addWidget(QLabel("🔍 البحث:"), 1, 0)
        cl.addWidget(self.search_le, 1, 1, 1, 3)

        lay.addWidget(card)

        self.tbl_counts = QTableWidget()
        self.tbl_counts.setAlternatingRowColors(True)
        self.tbl_counts.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.tbl_counts.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.tbl_counts.setColumnCount(5)
        self.tbl_counts.setHorizontalHeaderLabels(["#", "رقم الجرد", "التاريخ", "المستودع", "الحالة"])
        self.tbl_counts.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        self.tbl_counts.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.tbl_counts.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        self.tbl_counts.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.tbl_counts.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        self.tbl_counts.doubleClicked.connect(self._open_items)
        lay.addWidget(self.tbl_counts, 1)

        btn_row = QHBoxLayout()
        self.btn_refresh = self._btn("تحديث", "#6B7280")
        self.btn_refresh.clicked.connect(self._load_counts)
        btn_row.addWidget(self.btn_refresh)
        btn_row.addStretch()
        lay.addLayout(btn_row)

    # ----------------------------------------------------------- ITEMS TAB
    def _build_items_tab(self):
        lay = QVBoxLayout(self._tab_items)
        lay.setSpacing(12)
        card = self._card()
        form = QFormLayout(card)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        form.setFormAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        form.setHorizontalSpacing(12)
        form.setVerticalSpacing(10)

        self.item_cb = QComboBox()
        self.item_cb.setStyleSheet(self._combo_style())
        form.addRow(QLabel("📦 الصنف:"), self.item_cb)

        self.qty_le = QLineEdit()
        self.qty_le.setPlaceholderText("الكمية الفعلية")
        self.qty_le.setStyleSheet(self._line_style())
        form.addRow(QLabel("🔢 الكمية الفعلية:"), self.qty_le)

        self.reason_le_items = QLineEdit()
        self.reason_le_items.setPlaceholderText("سبب الفرق (اختياري)")
        self.reason_le_items.setStyleSheet(self._line_style())
        form.addRow(QLabel("📝 سبب الفرق:"), self.reason_le_items)

        lay.addWidget(card)

        btn_row = QHBoxLayout()
        self.btn_save_items = self._btn("حفظ التعديلات", COLORS['PRIMARY'])
        self.btn_save_items.clicked.connect(self._save_items)
        self.btn_approve = self._btn("اعتماد الجرد", "#10B981")
        self.btn_approve.clicked.connect(self._approve)
        self.btn_cancel = self._btn("إلغاء الجرد", COLORS['DANGER'])
        self.btn_cancel.clicked.connect(self._cancel)
        btn_row.addWidget(self.btn_save_items)
        btn_row.addWidget(self.btn_approve)
        btn_row.addWidget(self.btn_cancel)
        btn_row.addStretch()
        lay.addLayout(btn_row)

        self.tbl_items = QTableWidget()
        self.tbl_items.setAlternatingRowColors(True)
        self.tbl_items.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.tbl_items.setColumnCount(4)
        self.tbl_items.setHorizontalHeaderLabels(["#", "الصنف", "الكمية المسجلة", "الكمية الفعلية"])
        self.tbl_items.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        self.tbl_items.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.tbl_items.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        self.tbl_items.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        lay.addWidget(self.tbl_items, 1)

        self.lbl_items_status = QLabel()
        self.lbl_items_status.setStyleSheet(f"color:{COLORS['text']};font-size:13px;")
        lay.addWidget(self.lbl_items_status)

    # ----------------------------------------------------------- ATTACHMENTS TAB
    def _build_attachments_tab(self):
        lay = QVBoxLayout(self._tab_attachments)
        lay.setSpacing(12)
        card = self._card()
        cl = QGridLayout(card); cl.setHorizontalSpacing(14)
        lbl = QLabel("📎 مرفقات الجرد #:"); lbl.setStyleSheet("font-weight:bold;")
        self.lbl_attach_count = QLabel("لم يُحدَّد جرد")
        self.btn_upload = self._btn("⬆️ رفع مرفق", "#6366F1")
        self.btn_upload.clicked.connect(self._upload_attachment)
        cl.addWidget(lbl, 0, 0); cl.addWidget(self.lbl_attach_count, 0, 1)
        cl.addWidget(self.btn_upload, 0, 2)
        lay.addWidget(card)
        self.tbl_attach = QTableWidget()
        self.tbl_attach.setAlternatingRowColors(True)
        self.tbl_attach.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.tbl_attach.setColumnCount(4)
        self.tbl_attach.setHorizontalHeaderLabels(["#", "المرفق", "التاريخ", "الإجراء"])
        lay.addWidget(self.tbl_attach, 1)

    # ----------------------------------------------------------- REPORTS TAB
    def _build_reports_tab(self):
        lay = QVBoxLayout(self._tab_reports)
        lay.setSpacing(14)
        card = self._card()
        gl = QGridLayout(card); gl.setHorizontalSpacing(18)
        r = 0
        lbl1 = QLabel("🏭 المستودع:"); lbl1.setStyleSheet("font-weight:bold;")
        self.cb_wh_report = QComboBox(); self.cb_wh_report.setStyleSheet(self._combo_style())
        self.cb_wh_report.addItem("— اختر المستودع —", "")
        gl.addWidget(lbl1, r, 0); gl.addWidget(self.cb_wh_report, r, 1); r += 1
        lbl2 = QLabel("📋 رقم أمر الجرد:"); lbl2.setStyleSheet("font-weight:bold;")
        self.le_count_no = QLineEdit(); self.le_count_no.setPlaceholderText("أو اضغط لاختيار جرد")
        self.le_count_no.setStyleSheet(self._line_style())
        gl.addWidget(lbl2, r, 0); gl.addWidget(self.le_count_no, r, 1); r += 1
        lay.addWidget(card)

        row = QHBoxLayout()
        self.btn_form = self._btn("🖨️ اطبع استمارة الجرد", "#2563EB")
        self.btn_variance = self._btn("📊 اطبع فروقات الجرد", "#DC2626")
        self.btn_form.clicked.connect(self._print_form)
        self.btn_variance.clicked.connect(self._print_variance)
        row.addWidget(self.btn_form)
        row.addWidget(self.btn_variance)
        row.addStretch()
        lay.addLayout(row)
        self.lbl_report_status = QLabel()
        self.lbl_report_status.setStyleSheet(f"color:{COLORS['text']};font-size:13px;")
        lay.addWidget(self.lbl_report_status)
        lay.addStretch()

    # ----------------------------------------------------------- ACTIONS
    def _save_count(self):
        wh_id = self.wh_cb_create.currentData()
        if wh_id is None:
            QMessageBox.warning(self, "خطأ", "يرجى اختيار المستودع")
            return

        date = self.date_cb_create.date().toString("yyyy-MM-dd")
        reason = self.reason_le_create.text().strip()

        success, data = _api(self.api, self.api.create_inventory_count, {
            "warehouse_id": wh_id,
            "count_date": date,
            "reason": reason
        })
        if success and data:
            QMessageBox.information(self, "نجاح", "تم حفظ الجرد بنجاح")
            self._clear_create_form()
            self._load_counts()
            self.tabs.setCurrentIndex(1)
        else:
            QMessageBox.critical(self, "خطأ", "فشل حفظ الجرد")

    def _clear_create_form(self):
        self.wh_cb_create.setCurrentIndex(0)
        self.date_cb_create.setDate(QDate.currentDate())
        self.reason_le_create.clear()

    def _load_warehouses(self):
        success, data = _api(self.api, self.api.get_warehouses)
        if success and isinstance(data, list):
            self.wh_cb_create.clear()
            self.wh_cb_create.addItem("— اختر المستودع —", None)
            for wh in data:
                self.wh_cb_create.addItem(wh.get("name", ""), wh.get("id"))
            self.wh_cb_filter.clear()
            self.wh_cb_filter.addItem("— جميع المستودعات —", None)
            for wh in data:
                self.wh_cb_filter.addItem(wh.get("name", ""), wh.get("id"))
        else:
            QMessageBox.warning(self, "تحذير", "فشل تحميل قائمة المستودعات")

    def _load_items(self):
        success, data = _api(self.api, self.api.get_items)
        if success and isinstance(data, list):
            self.item_cb.clear()
            for item in data:
                self.item_cb.addItem(item.get("name", ""), item.get("id"))
        else:
            QMessageBox.warning(self, "تحذير", "فشل تحميل قائمة الأصناف")

    def _load_counts(self):
        wh_id = self.wh_cb_filter.currentData()
        status_text = self.status_cb_filter.currentText()
        status = None
        if status_text == "مسودة":
            status = "draft"
        elif status_text == "مكتمل":
            status = "completed"
        elif status_text == "معتمد":
            status = "approved"
        elif status_text == "ملغي":
            status = "cancelled"

        success, data = _api(self.api, self.api.get_inventory_counts, wh_id, status)
        if success and isinstance(data, list):
            self.tbl_counts.setRowCount(len(data))
            for row, count in enumerate(data):
                self.tbl_counts.setItem(row, 0, QTableWidgetItem(str(count.get("id", ""))))
                self.tbl_counts.setItem(row, 1, QTableWidgetItem(count.get("count_number", "")))
                self.tbl_counts.setItem(row, 2, QTableWidgetItem(count.get("count_date", "")))
                self.tbl_counts.setItem(row, 3, QTableWidgetItem(count.get("warehouse_name", "")))
                self.tbl_counts.setItem(row, 4, QTableWidgetItem(count.get("status", "")))
        else:
            self.tbl_counts.setRowCount(0)

    def _open_items(self):
        selected = self.tbl_counts.selectedItems()
        if not selected:
            return
        row = selected[0].row()
        count_id = int(self.tbl_counts.item(row, 0).text())
        self._load_count_details(count_id)
        self.tabs.setCurrentIndex(2)

    def _load_count_details(self, count_id):
        self.current_count_id = count_id
        success, data = _api(self.api, self.api.get_inventory_count_detail, count_id)
        if success and data:
            self.lbl_items_status.setText(f"عرض جرد رقم: {data.get('count_number', '')}")
            self.qty_le.clear()
            self.reason_le_items.clear()
            self.tbl_items.setRowCount(0)
            items = data.get("items", [])
            for row, item in enumerate(items):
                self.tbl_items.insertRow(row)
                self.tbl_items.setItem(row, 0, QTableWidgetItem(str(item.get("id", ""))))
                self.tbl_items.setItem(row, 1, QTableWidgetItem(item.get("item_name", "")))
                self.tbl_items.setItem(row, 2, QTableWidgetItem(str(item.get("recorded_quantity", 0))))
                self.tbl_items.setItem(row, 3, QTableWidgetItem(""))
        else:
            QMessageBox.warning(self, "خطأ", "فشل تحميل تفاصيل الجرد")

    def _save_items(self):
        if not hasattr(self, 'current_count_id'):
            QMessageBox.warning(self, "خطأ", "لم يتم اختيار جرد")
            return

        items = []
        for row in range(self.tbl_items.rowCount()):
            item_id = int(self.tbl_items.item(row, 0).text())
            actual_qty_text = self.tbl_items.item(row, 3).text()
            try:
                actual_qty = float(actual_qty_text) if actual_qty_text else 0
            except ValueError:
                actual_qty = 0
            reason = self.reason_le_items.text().strip()
            items.append({
                "item_id": item_id,
                "actual_quantity": actual_qty,
                "reason": reason
            })

        success, _ = _api(self.api, self.api.update_inventory_count_items, self.current_count_id, items)
        if success:
            QMessageBox.information(self, "نجاح", "تم حفظ التعديلات بنجاح")
            self._load_count_details(self.current_count_id)
        else:
            QMessageBox.critical(self, "خطأ", "فشل حفظ التعديلات")

    def _approve(self):
        if not hasattr(self, 'current_count_id'):
            QMessageBox.warning(self, "خطأ", "لم يتم اختيار جرد")
            return
        reply = QMessageBox.question(self, "تأكيد الاعتماد", "هل أنت متأكد من اعتماد هذا الجرد؟",
                                     QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            success, _ = _api(self.api, self.api.approve_inventory_count, self.current_count_id)
            if success:
                QMessageBox.information(self, "نجاح", "تم اعتماد الجرد بنجاح")
                self._load_counts()
                self.tabs.setCurrentIndex(1)
            else:
                QMessageBox.critical(self, "خطأ", "فشل اعتماد الجرد")

    def _cancel(self):
        if not hasattr(self, 'current_count_id'):
            QMessageBox.warning(self, "خطأ", "لم يتم اختيار جرد")
            return
        reply = QMessageBox.question(self, "تأكيد الإلغاء", "هل أنت متأكد من إلغاء هذا الجرد؟",
                                     QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            success, _ = _api(self.api, self.api.cancel_inventory_count, self.current_count_id)
            if success:
                QMessageBox.information(self, "نجاح", "تم إلغاء الجرد بنجاح")
                self._load_counts()
                self.tabs.setCurrentIndex(1)
            else:
                QMessageBox.critical(self, "خطأ", "فشل إلغاء الجرد")

    def _upload_attachment(self):
        if not hasattr(self, 'current_count_id'):
            QMessageBox.warning(self, "خطأ", "يرجى اختيار جرد أولًا من قائمة الجرد")
            return
        file_path, _ = QFileDialog.getOpenFileName(self, "اختر ملف المرفق", "", "All files (*.*)")
        if file_path:
            try:
                with open(file_path, "rb") as f:
                    import base64
                    b64 = base64.b64encode(f.read()).decode()
                success, _ = _api(self.api, self.api.upload_inventory_count_attachment,
                                  self.current_count_id, b64)
                if success:
                    QMessageBox.information(self, "نجاح", "تم رفع المرفق بنجاح")
                    self._load_attachments()
                else:
                    QMessageBox.critical(self, "خطأ", "فشل رفع المرفق")
            except Exception as e:
                QMessageBox.critical(self, "خطأ", f"خطأ في قراءة الملف: {str(e)}")

    def _load_attachments(self):
        if not hasattr(self, 'current_count_id'):
            self.lbl_attach_count.setText("لم يُحدَّد جرد")
            self.tbl_attach.setRowCount(0)
            return
        success, data = _api(self.api, self.api.get_inventory_count_detail, self.current_count_id)
        if success and data:
            attachments = data.get("attachments", [])
            self.lbl_attach_count.setText(f"المرفقات ({len(attachments)})")
            self.tbl_attach.setRowCount(len(attachments))
            for row, att in enumerate(attachments):
                self.tbl_attach.setItem(row, 0, QTableWidgetItem(str(row + 1)))
                self.tbl_attach.setItem(row, 1, QTableWidgetItem(att.get("file_name", "")))
                self.tbl_attach.setItem(row, 2, QTableWidgetItem(att.get("uploaded_at", "")))
                btn_view = self._btn("عرض", "#6366F1")
                btn_view.clicked.connect(lambda _, path=att.get("file_path"): QDesktopServices.openUrl(QtCoreQUrl.fromLocalFile(path)))
                self.tbl_attach.setCellWidget(row, 3, btn_view)
        else:
            self.lbl_attach_count.setText("فشل تحميل المرفقات")
            self.tbl_attach.setRowCount(0)

    def _print_form(self):
        if not hasattr(self, 'current_count_id'):
            QMessageBox.warning(self, "خطأ", "يرجى اختيار جرد أولًا من قائمة الجرد")
            return
        success, data = _api(self.api, self.api.get_inventory_count_detail, self.current_count_id)
        if success and data:
            print_inventory_count_form(self, data)
            self.lbl_report_status.setText("تم إرسال الاستمارة للطباعة")
        else:
            QMessageBox.critical(self, "خطأ", "فشل تحميل تفاصيل الجرد للطباعة")

    def _print_variance(self):
        if not hasattr(self, 'current_count_id'):
            QMessageBox.warning(self, "خطأ", "يرجى اختيار جرد أولًا من قائمة الجرد")
            return
        success, data = _api(self.api, self.api.get_inventory_count_detail, self.current_count_id)
        if success and data:
            print_inventory_count_variances(self, data)
            self.lbl_report_status.setText("تم إرسال تقرير الفروقات للطباعة")
        else:
            QMessageBox.critical(self, "خطأ", "فشل تحميل تفاصيل الجرد للتقرير")

    def _tab_list_current(self):
        self.tabs.setCurrentIndex(1)