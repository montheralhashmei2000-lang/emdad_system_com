import sqlite3
from pathlib import Path

db_path = Path(__file__).parent / 'data' / 'logistics.db'
conn = sqlite3.connect(str(db_path))
cursor = conn.cursor()

print('=== Tables ===')
cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = cursor.fetchall()
for table in tables:
    tname = table[0]
    print(f'\nTable: {tname}')
    cursor.execute(f"PRAGMA table_info({tname})")
    columns = cursor.fetchall()
    for col in columns:
        print(f'  {col[1]} ({col[2]})')

conn.close()