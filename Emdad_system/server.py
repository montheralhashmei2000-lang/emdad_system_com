"""Local REST server used by the Emdad desktop application.

The server uses only Python's standard library so it can be packaged as a
standalone executable without a separately installed web framework.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import secrets
import socket
import sqlite3
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlsplit


def app_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


ROOT = app_root()
DB_PATH = Path(os.environ.get("EMDAD_DB_PATH", ROOT / "data" / "logistics.db"))
MAX_BODY_SIZE = 16 * 1024 * 1024
_SCHEMA_LOCK = threading.Lock()
_SESSION_LOCK = threading.Lock()
_SESSIONS: dict[str, tuple[str, float]] = {}
SESSION_TTL_SECONDS = 8 * 60 * 60


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def connect_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=15000")
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def ensure_schema() -> None:
    """Create the app's existing ORM schema when the database is new."""
    with _SCHEMA_LOCK:
        DB_PATH.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(DB_PATH))
        try:
            exists = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='users'"
            ).fetchone()
        finally:
            conn.close()
        if not exists:
            # Import lazily so the server's request loop remains usable when
            # launched as a frozen PyInstaller application.
            try:
                os.environ["EMDAD_DB_PATH"] = str(DB_PATH)
                if str(ROOT) not in sys.path:
                    sys.path.insert(0, str(ROOT))
                from data.database import init_database
                init_database()
            except Exception as exc:
                raise RuntimeError(f"تعذر إنشاء قاعدة البيانات المحلية: {exc}") from exc
        with connect_db() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS system_settings ("
                "key TEXT PRIMARY KEY, value TEXT, updated_at TEXT DEFAULT (datetime('now'))"
                ")"
            )


def _jsonable(value: Any) -> Any:
    if isinstance(value, sqlite3.Row):
        return {key: _jsonable(value[key]) for key in value.keys()}
    if isinstance(value, dict):
        return {str(key): _jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(item) for item in value]
    if isinstance(value, bytes):
        return base64.b64encode(value).decode("ascii")
    return value


def _columns(conn: sqlite3.Connection, table: str) -> set[str]:
    if not re.fullmatch(r"[a-z_]+", table):
        raise ValueError("اسم الجدول غير صالح")
    return {row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')}


def _clean_table_rows(conn: sqlite3.Connection, table: str, limit: int = 1000) -> list[dict]:
    if table not in _columns(conn, table):
        return []
    cols = _columns(conn, table)
    where = " WHERE COALESCE(is_deleted, 0)=0" if "is_deleted" in cols else ""
    order = " ORDER BY created_at DESC" if "created_at" in cols else ""
    rows = conn.execute(f'SELECT * FROM "{table}"{where}{order} LIMIT ?', (limit,)).fetchall()
    return [_jsonable(row) for row in rows]


ENTITY_TABLES = {
    "items": "items",
    "warehouses": "warehouses",
    "units": "units_of_measure",
    "categories": "item_categories",
    "suppliers": "suppliers",
    "camps": "camps",
    "users": "users",
}


class ApiError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status = status
        self.detail = detail


class RequestHandler(BaseHTTPRequestHandler):
    server_version = "EmdadLocalServer/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        message = fmt % args
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {self.client_address[0]} {message}", flush=True)

    def _send(self, status: int, payload: Any) -> None:
        body = json.dumps(_jsonable(payload), ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> Any:
        length = int(self.headers.get("Content-Length", "0"))
        if length > MAX_BODY_SIZE:
            raise ApiError(413, "حجم الطلب أكبر من المسموح")
        if length == 0:
            return None
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise ApiError(400, "محتوى الطلب ليس JSON صالحًا")

    def _send_error(self, status: int, detail: str) -> None:
        self._send(status, {"detail": detail})

    def do_GET(self) -> None:
        self._dispatch("GET")

    def do_POST(self) -> None:
        self._dispatch("POST")

    def do_PUT(self) -> None:
        self._dispatch("PUT")

    def do_DELETE(self) -> None:
        self._dispatch("DELETE")

    def _dispatch(self, method: str) -> None:
        try:
            split = urlsplit(self.path)
            path = unquote(split.path.rstrip("/") or "/")
            query = {key: values[-1] for key, values in parse_qs(split.query).items()}
            body = self._body() if method in ("POST", "PUT") else None
            if path in ("/health", "/healthz") and method == "GET":
                self._send(200, {"status": "ok", "service": "emdat-local", "database": str(DB_PATH)})
                return
            if path == "/login" and method == "POST":
                self._send(200, self._login(body or {}))
                return

            self._authorize()
            with connect_db() as conn:
                status, result = self._route(conn, method, path, query, body)
            self._send(status, result)
        except ApiError as exc:
            self._send_error(exc.status, exc.detail)
        except sqlite3.IntegrityError as exc:
            self._send_error(409, f"تعذر حفظ البيانات بسبب التكرار أو ارتباط غير صالح: {exc}")
        except Exception as exc:
            print(f"[ERROR] {type(exc).__name__}: {exc}", flush=True)
            self._send_error(500, "حدث خطأ داخلي في خادم الإمداد")

    def _authorize(self) -> None:
        user_id = self.headers.get("X-User-ID")
        authorization = self.headers.get("Authorization", "")
        token = authorization[7:].strip() if authorization.lower().startswith("bearer ") else ""
        if not user_id or not token:
            raise ApiError(401, "يلزم تسجيل الدخول")
        with _SESSION_LOCK:
            session = _SESSIONS.get(token)
            if session and session[1] <= time.time():
                _SESSIONS.pop(token, None)
                session = None
        if not session or session[0] != user_id:
            raise ApiError(401, "انتهت جلسة الدخول؛ سجّل الدخول مجددًا")
        with connect_db() as conn:
            user = conn.execute(
                "SELECT id FROM users WHERE id=? AND is_active=1 AND COALESCE(is_deleted,0)=0",
                (user_id,),
            ).fetchone()
        if not user:
            raise ApiError(401, "جلسة المستخدم غير صالحة؛ سجّل الدخول مجددًا")

    def _login(self, data: dict) -> dict:
        username = str(data.get("username", "")).strip()
        password = str(data.get("password", ""))
        if not username or not password:
            raise ApiError(422, "أدخل اسم المستخدم وكلمة المرور")
        with connect_db() as conn:
            row = conn.execute(
                "SELECT id, username, full_name, role, password_hash FROM users "
                "WHERE username=? AND is_active=1 AND COALESCE(is_deleted,0)=0",
                (username,),
            ).fetchone()
        if not row or not _verify_password(password, row["password_hash"]):
            raise ApiError(401, "اسم المستخدم أو كلمة المرور غير صحيحة")
        token = secrets.token_urlsafe(32)
        with _SESSION_LOCK:
            _SESSIONS[token] = (row["id"], time.time() + SESSION_TTL_SECONDS)
        return {
            "id": row["id"], "username": row["username"],
            "full_name": row["full_name"], "role": str(row["role"] or "viewer").upper(),
            "permissions": {}, "offline_mode": False, "session_token": token,
        }

    def _route(self, conn: sqlite3.Connection, method: str, path: str, q: dict, body: Any):
        if path == "/system-settings":
            if method == "GET":
                return 200, {r["key"]: r["value"] for r in conn.execute("SELECT key,value FROM system_settings")}
            if method == "PUT":
                for key, value in (body or {}).items():
                    conn.execute(
                        "INSERT INTO system_settings(key,value,updated_at) VALUES(?,?,?) "
                        "ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at",
                        (str(key), str(value), utc_now()),
                    )
                return 200, body or {}

        if path == "/dashboard/stats" and method == "GET":
            return 200, self._dashboard(conn)

        entity_match = re.fullmatch(r"/(items|warehouses|units|categories|suppliers|camps|users)(?:/([^/]+))?", path)
        if entity_match:
            route, entity_id = entity_match.groups()
            table = ENTITY_TABLES[route]
            if route == "users":
                if method == "GET" and entity_id is None:
                    return 200, self._users(conn)
                if method == "POST" and entity_id is None:
                    return 201, self._create_user(conn, body or {})
                if method == "PUT" and entity_id:
                    return 200, self._update_row(conn, table, entity_id, body or {}, hide_password=True)
                if method == "DELETE" and entity_id:
                    return 200, self._soft_delete(conn, table, entity_id)
            if method == "GET" and entity_id is None:
                return 200, self._list_entity(conn, route, q)
            if method == "POST" and entity_id is None:
                return 201, self._create_row(conn, table, body or {})
            if method == "PUT" and entity_id:
                return 200, self._update_row(conn, table, entity_id, body or {})
            if method == "DELETE" and entity_id:
                return 200, self._soft_delete(conn, table, entity_id)

        if path == "/stock/balance" and method == "GET":
            return 200, self._stock_balance(conn, q)
        if path == "/stock/low-stock" and method == "GET":
            return 200, self._low_stock(conn)
        if path == "/stock/movements" and method == "GET":
            return 200, self._movements(conn, q)
        if path.startswith("/inventory-counts"):
            return self._stocktake_route(conn, method, path, q, body)
        if path.startswith("/stock/") and path in ("/stock/receive", "/stock/issue", "/stock/transfer") and method == "POST":
            return 201, self._create_transaction(conn, path.rsplit("/", 1)[-1], body or {})
        if path == "/roles" and method == "GET":
            return 200, [{"name": role, "code": role.upper()} for role in ("admin", "manager", "storekeeper", "viewer")]
        if path == "/audit-logs" and method == "GET":
            return 200, self._audit_logs(conn, q)
        if path == "/activity/recent" and method == "GET":
            return 200, self._audit_logs(conn, q)
        if path == "/facilities" and method == "GET":
            return 200, self._list_entity(conn, "camps", q)
        if path == "/facilities" and method == "POST":
            return 201, self._create_row(conn, "camps", body or {})

        raise ApiError(404, f"المسار غير موجود في الخادم: {method} {path}")

    def _list_entity(self, conn: sqlite3.Connection, route: str, q: dict) -> list[dict]:
        table = ENTITY_TABLES[route]
        limit = min(max(int(q.get("limit", 1000)), 1), 5000)
        where = []
        args: list[Any] = []
        cols = _columns(conn, table)
        if "is_deleted" in cols:
            where.append("COALESCE(is_deleted,0)=0")
        if "is_active" in cols:
            where.append("COALESCE(is_active,1)=1")
        if route == "items" and "is_active" in cols and q.get("include_inactive"):
            where = [term for term in where if "is_active" not in term]
        if route == "items":
            sql = (
                "SELECT i.*, c.name AS category_name, u.name AS base_uom_name, "
                "COALESCE((SELECT SUM(sb.quantity) FROM stock_balances sb WHERE sb.item_id=i.id AND COALESCE(sb.is_deleted,0)=0),0) AS current_stock "
                "FROM items i LEFT JOIN item_categories c ON c.id=i.category_id "
                "LEFT JOIN units_of_measure u ON u.id=i.base_uom_id"
            )
            if where:
                sql += " WHERE " + " AND ".join(term.replace("is_deleted", "i.is_deleted").replace("is_active", "i.is_active") for term in where)
            sql += " ORDER BY i.name LIMIT ?"
        elif route == "warehouses":
            sql = "SELECT * FROM warehouses" + (" WHERE " + " AND ".join(where) if where else "") + " ORDER BY name LIMIT ?"
        else:
            sql = f'SELECT * FROM "{table}"' + (" WHERE " + " AND ".join(where) if where else "") + " ORDER BY name LIMIT ?"
        args.append(limit)
        return [_jsonable(row) for row in conn.execute(sql, args)]

    def _create_row(self, conn: sqlite3.Connection, table: str, data: dict) -> dict:
        cols = _columns(conn, table)
        now = utc_now()
        payload = {key: value for key, value in data.items() if key in cols and key != "id"}
        payload.setdefault("id", str(uuid.uuid4()))
        if "created_at" in cols:
            payload.setdefault("created_at", now)
        if "updated_at" in cols:
            payload.setdefault("updated_at", now)
        if "is_deleted" in cols:
            payload.setdefault("is_deleted", 0)
        if "sync_status" in cols:
            payload.setdefault("sync_status", "pending")
        if table == "warehouses" and "camp_id" in cols and not payload.get("camp_id"):
            camp = conn.execute("SELECT id FROM camps WHERE is_active=1 ORDER BY created_at LIMIT 1").fetchone()
            payload["camp_id"] = data.get("camp_id") or (camp["id"] if camp else "local")
        names = list(payload)
        sql = f'INSERT INTO "{table}" (' + ",".join(f'"{name}"' for name in names) + ") VALUES (" + ",".join("?" for _ in names) + ")"
        conn.execute(sql, [payload[name] for name in names])
        row = conn.execute(f'SELECT * FROM "{table}" WHERE id=?', (payload["id"],)).fetchone()
        return _jsonable(row)

    def _update_row(self, conn: sqlite3.Connection, table: str, row_id: str, data: dict, hide_password: bool = False) -> dict:
        cols = _columns(conn, table)
        payload = {key: value for key, value in data.items() if key in cols and key not in ("id", "created_at")}
        if "updated_at" in cols:
            payload["updated_at"] = utc_now()
        if not payload:
            raise ApiError(400, "لا توجد حقول صالحة للتحديث")
        assignments = ",".join(f'"{key}"=?' for key in payload)
        cursor = conn.execute(f'UPDATE "{table}" SET {assignments} WHERE id=?', [*payload.values(), row_id])
        if cursor.rowcount == 0:
            raise ApiError(404, "السجل غير موجود")
        row = _jsonable(conn.execute(f'SELECT * FROM "{table}" WHERE id=?', (row_id,)).fetchone())
        if hide_password:
            row.pop("password_hash", None)
        return row

    def _soft_delete(self, conn: sqlite3.Connection, table: str, row_id: str) -> dict:
        cols = _columns(conn, table)
        if "is_deleted" in cols:
            conn.execute(f'UPDATE "{table}" SET is_deleted=1, updated_at=? WHERE id=?', (utc_now(), row_id))
        else:
            conn.execute(f'DELETE FROM "{table}" WHERE id=?', (row_id,))
        return {"ok": True, "id": row_id}

    def _users(self, conn: sqlite3.Connection) -> list[dict]:
        rows = conn.execute("SELECT id,username,full_name,role,is_active,camp_id,created_at FROM users WHERE COALESCE(is_deleted,0)=0 ORDER BY full_name").fetchall()
        return [_jsonable(row) for row in rows]

    def _create_user(self, conn: sqlite3.Connection, data: dict) -> dict:
        username = str(data.get("username", "")).strip()
        password = str(data.get("password", data.get("password_hash", "")))
        if not username or not password:
            raise ApiError(422, "اسم المستخدم وكلمة المرور مطلوبان")
        try:
            import bcrypt
            password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("ascii")
        except Exception:
            password_hash = hashlib.sha256(password.encode("utf-8")).hexdigest()
        row = self._create_row(conn, "users", {**data, "username": username, "password_hash": password_hash})
        row.pop("password_hash", None)
        return row

    def _dashboard(self, conn: sqlite3.Connection) -> dict:
        def scalar(sql: str) -> int:
            return int(conn.execute(sql).fetchone()[0] or 0)
        cards = {
            "total_items": scalar("SELECT COUNT(*) FROM items WHERE COALESCE(is_deleted,0)=0 AND COALESCE(is_active,1)=1"),
            "total_units": scalar("SELECT COUNT(*) FROM camps WHERE COALESCE(is_deleted,0)=0 AND COALESCE(is_active,1)=1"),
            "total_moves_today": scalar("SELECT COUNT(*) FROM transactions WHERE date(transaction_date)=date('now','localtime') AND COALESCE(is_deleted,0)=0"),
            "low_stock_count": scalar("SELECT COUNT(*) FROM items i WHERE COALESCE(i.is_deleted,0)=0 AND COALESCE(i.is_active,1)=1 AND COALESCE(i.min_stock_level,0)>COALESCE((SELECT SUM(b.quantity) FROM stock_balances b WHERE b.item_id=i.id AND COALESCE(b.is_deleted,0)=0),0)"),
        }
        low_stock = self._low_stock(conn)
        trend = conn.execute(
            "SELECT date(t.transaction_date) AS date, COALESCE(SUM(ti.quantity),0) AS qty "
            "FROM transactions t JOIN transaction_items ti ON ti.transaction_id=t.id "
            "WHERE t.transaction_type IN ('issue','ISSUE','صرف') AND date(t.transaction_date)>=date('now','-29 day') "
            "GROUP BY date(t.transaction_date) ORDER BY date"
        ).fetchall()
        return {"cards": cards, "low_stock": low_stock, "trend": [_jsonable(x) for x in trend], "top_units": []}

    def _stock_balance(self, conn: sqlite3.Connection, q: dict) -> list[dict]:
        clauses = ["COALESCE(sb.is_deleted,0)=0"]
        args: list[Any] = []
        if q.get("warehouse_id"):
            clauses.append("sb.warehouse_id=?")
            args.append(q["warehouse_id"])
        if q.get("item_id"):
            clauses.append("sb.item_id=?")
            args.append(q["item_id"])
        sql = (
            "SELECT sb.*, i.code AS item_code, i.name AS item_name, i.name, i.min_stock_level, "
            "w.name AS warehouse_name, u.name AS unit_name FROM stock_balances sb "
            "JOIN items i ON i.id=sb.item_id LEFT JOIN warehouses w ON w.id=sb.warehouse_id "
            "LEFT JOIN units_of_measure u ON u.id=sb.uom_id WHERE " + " AND ".join(clauses) + " ORDER BY i.name"
        )
        return [_jsonable(row) for row in conn.execute(sql, args)]

    def _low_stock(self, conn: sqlite3.Connection) -> list[dict]:
        sql = (
            "SELECT i.code AS item_code,i.name,i.min_stock_level AS min_limit,"
            "COALESCE(SUM(sb.quantity),0) AS balance FROM items i "
            "LEFT JOIN stock_balances sb ON sb.item_id=i.id AND COALESCE(sb.is_deleted,0)=0 "
            "WHERE COALESCE(i.is_deleted,0)=0 AND COALESCE(i.is_active,1)=1 "
            "GROUP BY i.id HAVING balance < COALESCE(i.min_stock_level,0) ORDER BY i.name"
        )
        return [_jsonable(row) for row in conn.execute(sql)]

    def _movements(self, conn: sqlite3.Connection, q: dict) -> list[dict]:
        clauses = ["COALESCE(t.is_deleted,0)=0"]
        args: list[Any] = []
        if q.get("movement_type"):
            clauses.append("t.transaction_type=?")
            args.append(q["movement_type"])
        if q.get("item_id"):
            clauses.append("ti.item_id=?")
            args.append(q["item_id"])
        if q.get("warehouse_id"):
            clauses.append("(t.warehouse_from_id=? OR t.warehouse_to_id=?)")
            args.extend([q["warehouse_id"], q["warehouse_id"]])
        limit = min(max(int(q.get("limit", 500)), 1), 5000)
        sql = (
            "SELECT t.*, t.transaction_type AS movement_type, t.transaction_date AS created_date, "
            "w1.name AS warehouse_from_name,w2.name AS warehouse_to_name,s.name AS supplier_name, "
            "ti.item_id, i.code AS item_code,i.name AS item_name,ti.quantity,ti.uom_id,u.name AS unit_name "
            "FROM transactions t LEFT JOIN transaction_items ti ON ti.transaction_id=t.id "
            "LEFT JOIN items i ON i.id=ti.item_id LEFT JOIN units_of_measure u ON u.id=ti.uom_id "
            "LEFT JOIN warehouses w1 ON w1.id=t.warehouse_from_id LEFT JOIN warehouses w2 ON w2.id=t.warehouse_to_id "
            "LEFT JOIN suppliers s ON s.id=t.supplier_id WHERE " + " AND ".join(clauses) +
            " ORDER BY t.transaction_date DESC LIMIT ?"
        )
        return [_jsonable(row) for row in conn.execute(sql, [*args, limit])]

    def _create_transaction(self, conn: sqlite3.Connection, kind: str, data: dict) -> dict:
        now = utc_now()
        tid = str(uuid.uuid4())
        raw_items = data.get("items") or data.get("details") or []
        if isinstance(raw_items, dict):
            raw_items = raw_items.get("items", [])
        if not raw_items:
            raise ApiError(422, "أضف صنفًا واحدًا على الأقل للحركة")
        txn_type = {"receive": "IN", "issue": "OUT", "transfer": "TRANSFER"}[kind]
        payload = {
            "id": tid, "transaction_no": data.get("transaction_no") or data.get("reference_no") or f"{txn_type}-{datetime.now():%Y%m%d%H%M%S}",
            "transaction_type": txn_type, "transaction_date": data.get("transaction_date") or data.get("date") or now,
            "warehouse_from_id": data.get("warehouse_from_id") or data.get("source_warehouse_id") or (data.get("warehouse_id") if kind in ("issue", "transfer") else None),
            "warehouse_to_id": data.get("warehouse_to_id") or data.get("target_warehouse_id") or (data.get("warehouse_id") if kind == "receive" else None),
            "supplier_id": data.get("supplier_id"), "recipient_name": data.get("recipient_name"),
            "user_id": self.headers.get("X-User-ID"), "status": "posted", "notes": data.get("notes"),
            "camp_id": data.get("camp_id"), "created_at": now, "updated_at": now,
            "sync_status": "pending", "is_deleted": 0,
        }
        names = list(payload)
        conn.execute("INSERT INTO transactions (" + ",".join(names) + ") VALUES (" + ",".join("?" for _ in names) + ")", [payload[n] for n in names])
        for raw in raw_items:
            item_id = raw.get("item_id") or raw.get("id")
            qty = float(raw.get("quantity", raw.get("qty", 0)) or 0)
            if not item_id or qty <= 0:
                raise ApiError(422, "بيانات الصنف والكمية غير صالحة")
            item = conn.execute("SELECT base_uom_id FROM items WHERE id=?", (item_id,)).fetchone()
            if not item:
                raise ApiError(404, "الصنف المحدد غير موجود")
            uom = raw.get("uom_id") or raw.get("unit_id") or item["base_uom_id"]
            iid = str(uuid.uuid4())
            conn.execute(
                "INSERT INTO transaction_items (id,camp_id,created_at,updated_at,sync_status,is_deleted,transaction_id,item_id,uom_id,quantity,unit_price,notes) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (iid, payload["camp_id"], now, now, "pending", 0, tid, item_id, uom, qty, raw.get("unit_price"), raw.get("notes")),
            )
            warehouse_id = payload["warehouse_to_id"] if kind == "receive" else payload["warehouse_from_id"]
            if kind != "transfer":
                self._adjust_balance(conn, item_id, warehouse_id, uom, qty if kind == "receive" else -qty, payload["camp_id"])
            else:
                self._adjust_balance(conn, item_id, payload["warehouse_from_id"], uom, -qty, payload["camp_id"])
                self._adjust_balance(conn, item_id, payload["warehouse_to_id"], uom, qty, payload["camp_id"])
        return {"id": tid, "transaction_no": payload["transaction_no"], "status": "posted"}

    @staticmethod
    def _adjust_balance(conn: sqlite3.Connection, item_id: str, warehouse_id: str | None, uom_id: str, delta: float, camp_id: str | None) -> None:
        if not warehouse_id:
            raise ApiError(422, "المستودع مطلوب للحركة")
        row = conn.execute("SELECT id,quantity FROM stock_balances WHERE item_id=? AND warehouse_id=? AND uom_id=? AND COALESCE(is_deleted,0)=0", (item_id, warehouse_id, uom_id)).fetchone()
        if row:
            new_qty = float(row["quantity"] or 0) + delta
            if new_qty < -0.000001:
                raise ApiError(409, "الرصيد غير كافٍ لإتمام الحركة")
            conn.execute("UPDATE stock_balances SET quantity=?,last_movement_at=?,updated_at=?,sync_status='pending' WHERE id=?", (max(0, new_qty), utc_now(), utc_now(), row["id"]))
        else:
            if delta < 0:
                raise ApiError(409, "لا يوجد رصيد كافٍ في المستودع")
            now = utc_now()
            conn.execute("INSERT INTO stock_balances(id,camp_id,created_at,updated_at,sync_status,is_deleted,item_id,warehouse_id,uom_id,quantity,last_movement_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)", (str(uuid.uuid4()), camp_id, now, now, "pending", 0, item_id, warehouse_id, uom_id, delta, now))

    def _stocktake_route(self, conn: sqlite3.Connection, method: str, path: str, q: dict, body: Any):
        base = "/inventory-counts"
        if path == base and method == "GET":
            clauses = ["COALESCE(s.is_deleted,0)=0"]
            args: list[Any] = []
            if q.get("warehouse_id"):
                clauses.append("s.warehouse_id=?"); args.append(q["warehouse_id"])
            if q.get("status"):
                clauses.append("s.status=?"); args.append(q["status"])
            rows = conn.execute(
                "SELECT s.*,w.name AS warehouse_name,(SELECT COUNT(*) FROM stocktake_items si WHERE si.stocktake_id=s.id AND COALESCE(si.is_deleted,0)=0) AS item_count "
                "FROM stocktakes s LEFT JOIN warehouses w ON w.id=s.warehouse_id WHERE " + " AND ".join(clauses) + " ORDER BY s.created_at DESC", args
            ).fetchall()
            return 200, [_jsonable(row) for row in rows]
        if path == base and method == "POST":
            data = body or {}
            wh_id = data.get("warehouse_id") or data.get("warehouse_id_selected")
            if not wh_id:
                raise ApiError(422, "المستودع مطلوب لإنشاء أمر الجرد")
            now = utc_now(); count_id = str(uuid.uuid4())
            no = data.get("stocktake_no") or data.get("order_no") or f"ST-{datetime.now():%Y%m%d%H%M%S}"
            conn.execute(
                "INSERT INTO stocktakes(id,camp_id,created_at,updated_at,sync_status,is_deleted,stocktake_no,warehouse_id,stocktake_date,user_id,status,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                (count_id, data.get("camp_id"), now, now, "pending", 0, no, wh_id, data.get("stocktake_date") or data.get("start_date") or now, self.headers.get("X-User-ID"), "open", data.get("notes")),
            )
            rows = conn.execute("SELECT item_id,uom_id,quantity FROM stock_balances WHERE warehouse_id=? AND COALESCE(is_deleted,0)=0", (wh_id,)).fetchall()
            for row in rows:
                conn.execute("INSERT INTO stocktake_items(id,camp_id,created_at,updated_at,sync_status,is_deleted,stocktake_id,item_id,uom_id,system_qty,counted_qty,difference_qty) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (str(uuid.uuid4()), data.get("camp_id"), now, now, "pending", 0, count_id, row["item_id"], row["uom_id"], row["quantity"] or 0, 0, -(row["quantity"] or 0)))
            return 201, {"id": count_id, "stocktake_no": no, "status": "open"}

        match = re.fullmatch(re.escape(base) + r"/([^/]+)(?:/(items|reasons|approve|cancel|attachment|add-item))?", path)
        if not match:
            raise ApiError(404, "مسار الجرد غير موجود")
        count_id, action = match.groups()
        head = conn.execute("SELECT * FROM stocktakes WHERE id=? AND COALESCE(is_deleted,0)=0", (count_id,)).fetchone()
        if not head:
            raise ApiError(404, "أمر الجرد غير موجود")
        if action is None and method == "GET":
            rows = conn.execute("SELECT si.*,i.code AS item_code,i.name AS item_name,u.name AS unit_name FROM stocktake_items si LEFT JOIN items i ON i.id=si.item_id LEFT JOIN units_of_measure u ON u.id=si.uom_id WHERE si.stocktake_id=? AND COALESCE(si.is_deleted,0)=0 ORDER BY i.name", (count_id,)).fetchall()
            result = _jsonable(head); result["items"] = [_jsonable(r) for r in rows]
            return 200, result
        if action in ("items", "reasons") and method == "PUT":
            items = (body or {}).get("items", []) if isinstance(body, dict) else body or []
            for item in items:
                row = conn.execute("SELECT id,system_qty FROM stocktake_items WHERE stocktake_id=? AND item_id=? AND COALESCE(is_deleted,0)=0", (count_id, item.get("item_id"))).fetchone()
                if not row:
                    continue
                counted = item.get("counted_qty", item.get("actual_qty"))
                reason = item.get("reason") or item.get("notes")
                if counted is not None:
                    system_qty = float(row["system_qty"] or 0); counted = float(counted)
                    conn.execute("UPDATE stocktake_items SET counted_qty=?,difference_qty=?,notes=COALESCE(?,notes),updated_at=?,sync_status='pending' WHERE id=?", (counted, counted-system_qty, reason, utc_now(), row["id"]))
                elif reason is not None:
                    conn.execute("UPDATE stocktake_items SET notes=?,updated_at=?,sync_status='pending' WHERE id=?", (str(reason), utc_now(), row["id"]))
            return 200, {"ok": True}
        if action == "add-item" and method == "POST":
            item_id = (body or {}).get("item_id")
            item = conn.execute("SELECT id,base_uom_id FROM items WHERE id=?", (item_id,)).fetchone()
            if not item:
                raise ApiError(404, "الصنف غير موجود")
            now=utc_now()
            conn.execute("INSERT INTO stocktake_items(id,camp_id,created_at,updated_at,sync_status,is_deleted,stocktake_id,item_id,uom_id,system_qty,counted_qty,difference_qty) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (str(uuid.uuid4()), head["camp_id"], now, now, "pending", 0, count_id, item_id, item["base_uom_id"], 0, 0, 0))
            return 201, {"ok": True}
        if action == "approve" and method == "POST":
            conn.execute("UPDATE stocktakes SET status='approved',updated_at=?,sync_status='pending' WHERE id=?", (utc_now(), count_id))
            return 200, {"ok": True, "status": "approved"}
        if action == "cancel" and method == "POST":
            conn.execute("UPDATE stocktakes SET status='cancelled',updated_at=?,sync_status='pending' WHERE id=?", (utc_now(), count_id))
            return 200, {"ok": True, "status": "cancelled"}
        if action == "attachment" and method == "POST":
            raise ApiError(501, "المرفقات غير مفعلة بعد في الخادم المحلي")
        raise ApiError(405, "طريقة الطلب غير مدعومة لمسار الجرد")

    def _audit_logs(self, conn: sqlite3.Connection, q: dict) -> list[dict]:
        limit=min(max(int(q.get("limit", 50)),1),1000)
        rows=conn.execute("SELECT * FROM audit_logs WHERE COALESCE(is_deleted,0)=0 ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        return [_jsonable(row) for row in rows]


def _verify_password(password: str, stored: str) -> bool:
    if not stored:
        return False
    if stored.startswith(("$2b$", "$2a$", "$2y$")):
        try:
            import bcrypt
            return bcrypt.checkpw(password.encode("utf-8"), stored.encode("ascii"))
        except Exception:
            return False
    if len(stored) == 64:
        return secrets.compare_digest(hashlib.sha256(password.encode("utf-8")).hexdigest(), stored)
    return secrets.compare_digest(password, stored)


class ReusableThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    parser = argparse.ArgumentParser(description="خادم نظام الإمداد والتموين")
    parser.add_argument("--host", default=os.environ.get("EMDAD_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("EMDAD_PORT", "8000")))
    parser.add_argument("--db", default=os.environ.get("EMDAD_DB_PATH", str(ROOT / "data" / "logistics.db")))
    args = parser.parse_args()
    global DB_PATH
    DB_PATH = Path(args.db).expanduser().resolve()
    try:
        ensure_schema()
        server = ReusableThreadingHTTPServer((args.host, args.port), RequestHandler)
    except OSError as exc:
        print(f"تعذر تشغيل الخادم على {args.host}:{args.port}: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"تعذر تهيئة الخادم: {exc}", file=sys.stderr)
        return 2

    print("=" * 56, flush=True)
    print("خادم نظام الإمداد والتموين جاهز", flush=True)
    print(f"العنوان: http://{args.host}:{args.port}", flush=True)
    print(f"قاعدة البيانات: {DB_PATH}", flush=True)
    print("فحص الحالة: /health", flush=True)
    print("لإيقاف الخادم اضغط Ctrl+C", flush=True)
    print("=" * 56, flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        print("إيقاف الخادم...", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
