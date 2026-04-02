# Capital Markets Database — Volume Test Data Generator
# Generates realistic financial trading data at scale for index testing
#
# Requirements:
#   pip install faker pandas mysql-connector-python
#
# Usage:
#   python data_generation/generate_data.py
#
# Targets: 10,000 traders, 100,000+ orders, ~500,000 ledger entries
# Seed: 42 (reproducible results)

import math
import os
import random
import time
from datetime import timedelta
from decimal import Decimal

import mysql.connector
from faker import Faker

# ============================================================
# SECTION 1: CONFIG
# ============================================================

DB_HOST = os.environ.get("MYSQL_HOST", "127.0.0.1")
DB_PORT = int(os.environ.get("MYSQL_PORT", "3306"))
DB_USER = os.environ.get("MYSQL_USER", "root")
DB_PASS = os.environ.get("MYSQL_PASSWORD", "")
DB_NAME = os.environ.get("MYSQL_DATABASE", "capital_markets_db")

BATCH_SIZE   = 1000     # Rows per executemany() call
NUM_TRADERS  = 10000
NUM_ORDERS   = 100000
RANDOM_SEED  = 42

# ============================================================
# SECTION 2: SETUP
# ============================================================

fake = Faker()
Faker.seed(RANDOM_SEED)
random.seed(RANDOM_SEED)

start_time = time.time()


# ============================================================
# SECTION 3: DATABASE CONNECTION
# ============================================================

def get_connection():
    return mysql.connector.connect(
        host=DB_HOST, port=DB_PORT, user=DB_USER,
        password=DB_PASS, database=DB_NAME, autocommit=False
    )


def fetch_column(conn, sql):
    """Execute a scalar-column SELECT and return all values as a list."""
    cursor = conn.cursor()
    cursor.execute(sql)
    result = [row[0] for row in cursor.fetchall()]
    cursor.close()
    return result


# ============================================================
# SECTION 4: GENERATOR FUNCTIONS
# ============================================================

def generate_traders(n):
    """Generate n trader dicts. 70% INDIVIDUAL, 30% INSTITUTIONAL.
    Status: 95% ACTIVE, 3% SUSPENDED, 2% CLOSED."""
    rows = []
    for _ in range(n):
        rows.append({
            'first_name':        fake.first_name(),
            'last_name':         fake.last_name(),
            'email':             f"{fake.uuid4()}@example.com",
            'phone':             None,
            'trader_type':       random.choices(
                                     ['INDIVIDUAL', 'INSTITUTIONAL'],
                                     weights=[70, 30])[0],
            'trader_status':     random.choices(
                                     ['ACTIVE', 'SUSPENDED', 'CLOSED'],
                                     weights=[95, 3, 2])[0],
            # All historical → satisfies CHECK (registration_date <= created_at date)
            'registration_date': fake.date_between(start_date='-5y', end_date='today'),
        })
    return rows


def generate_portfolios(trader_ids):
    """Each trader gets 1–3 portfolios named A/B/C.
    UNIQUE (trader_id, portfolio_name) is naturally satisfied."""
    names = ['Portfolio A', 'Portfolio B', 'Portfolio C']
    rows = []
    for tid in trader_ids:
        count = random.randint(1, 3)
        for name in names[:count]:
            rows.append({
                'trader_id':      tid,
                'portfolio_name': name,
                'description':    None,
            })
    return rows


def generate_orders(trader_ids, asset_ids, portfolio_ids, n):
    """Generate n orders with realistic financial distributions.
    MARKET orders have limit_price=NULL per schema constraint."""
    cancel_reasons = [
        'Limit price not reached within session',
        'Customer requested cancellation',
        'Risk limit exceeded',
    ]
    rows = []
    for _ in range(n):
        status     = random.choices(['FILLED','PENDING','CANCELLED','REJECTED'],
                                    weights=[60, 25, 10, 5])[0]
        order_type = random.choices(['LIMIT','MARKET','STOP'],
                                    weights=[50, 30, 20])[0]
        side       = random.choices(['BUY','SELL'], weights=[55, 45])[0]
        quantity   = random.randint(1, 500)

        # limit_price: NULL for MARKET, Decimal for LIMIT/STOP
        if order_type == 'MARKET':
            limit_price = None
        else:
            limit_price = Decimal(str(round(random.uniform(10, 900), 4)))

        # Fill data — only meaningful for FILLED orders
        if status == 'FILLED':
            filled_qty         = quantity
            average_fill_price = Decimal(str(round(random.uniform(10, 900), 4)))
        else:
            filled_qty         = 0
            average_fill_price = None

        order_time = fake.date_time_between(start_date='-365d', end_date='now')

        if status == 'CANCELLED':
            cancelled_at  = order_time + timedelta(minutes=random.randint(1, 60))
            cancel_reason = random.choice(cancel_reasons)
        else:
            cancelled_at  = None
            cancel_reason = None

        rows.append({
            'trader_id':          random.choice(trader_ids),
            'asset_id':           random.choice(asset_ids),
            'portfolio_id':       random.choice(portfolio_ids),
            'order_type':         order_type,
            'order_side':         side,
            'quantity':           quantity,
            'limit_price':        limit_price,
            'filled_quantity':    filled_qty,
            'average_fill_price': average_fill_price,
            'order_status':       status,
            'order_time':         order_time,
            'cancelled_at':       cancelled_at,
            'cancel_reason':      cancel_reason,
        })
    return rows


def generate_settlements(filled_orders):
    """One settlement per FILLED order. All settle at SETTLED status.
    gross = trade_price × quantity; net = gross ± commission (BUY adds, SELL subtracts)."""
    commission = Decimal('9.9900')
    rows = []
    for o in filled_orders:
        trade_price  = Decimal(str(o['average_fill_price']))
        gross_amount = trade_price * Decimal(str(o['quantity']))
        if o['order_side'] == 'BUY':
            net_amount = gross_amount + commission
        else:
            net_amount = gross_amount - commission
        rows.append({
            'order_id':          o['order_id'],
            'trade_price':       trade_price,
            'quantity':          o['quantity'],
            'gross_amount':      gross_amount,
            'commission':        commission,
            'net_amount':        net_amount,
            'settlement_date':   o['order_time'].date() + timedelta(days=2),
            'settlement_status': 'SETTLED',
        })
    return rows


def generate_ledger_entries(filled_orders):
    """Two double-entry rows per FILLED order (debit leg + credit leg).
    BUY:  CASH → TRADING_ACCOUNT; TRADING_ACCOUNT → SECURITIES
    SELL: SECURITIES → TRADING_ACCOUNT; TRADING_ACCOUNT → CASH
    Both rows in a pair carry identical amounts (net settlement value)."""
    commission = Decimal('9.9900')
    rows = []
    for o in filled_orders:
        # Re-derive net_amount (same formula as generate_settlements)
        trade_price  = Decimal(str(o['average_fill_price']))
        gross_amount = trade_price * Decimal(str(o['quantity']))
        net_amount   = (gross_amount + commission if o['order_side'] == 'BUY'
                        else gross_amount - commission)

        if o['order_side'] == 'BUY':
            debit1, credit1 = 'CASH',            'TRADING_ACCOUNT'
            debit2, credit2 = 'TRADING_ACCOUNT', 'SECURITIES'
        else:
            debit1, credit1 = 'SECURITIES',      'TRADING_ACCOUNT'
            debit2, credit2 = 'TRADING_ACCOUNT', 'CASH'

        rows.append({
            'transaction_date': o['order_time'],
            'debit_account':    debit1,
            'credit_account':   credit1,
            'amount':           net_amount,
            'reference_type':   'ORDER',
            'reference_id':     o['order_id'],
            'description':      f"Order {o['order_id']} {o['order_side']} — asset leg",
        })
        rows.append({
            'transaction_date': o['order_time'],
            'debit_account':    debit2,
            'credit_account':   credit2,
            'amount':           net_amount,
            'reference_type':   'ORDER',
            'reference_id':     o['order_id'],
            'description':      f"Order {o['order_id']} {o['order_side']} — settlement leg",
        })
    return rows


# ============================================================
# SECTION 5: BATCH INSERT
# ============================================================

def batch_insert(conn, table, rows, columns):
    """Insert rows into table using executemany() in BATCH_SIZE chunks.
    Commits after each successful batch; rolls back and re-raises on error."""
    if not rows:
        print(f"  Skipping {table}: no rows to insert")
        return
    cursor = conn.cursor()
    col_list     = ', '.join(columns)
    placeholders = ', '.join(['%s'] * len(columns))
    sql          = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders})"
    total_batches = math.ceil(len(rows) / BATCH_SIZE)

    for i in range(0, len(rows), BATCH_SIZE):
        batch     = rows[i:i + BATCH_SIZE]
        batch_num = i // BATCH_SIZE + 1
        # Build tuples — convert Decimal and date objects; map None → None
        data = [tuple(row[c] for c in columns) for row in batch]
        try:
            cursor.executemany(sql, data)
            conn.commit()
            print(f"  Inserted batch {batch_num}/{total_batches} into {table}...")
        except Exception as e:
            conn.rollback()
            print(f"  ERROR in batch {batch_num} of {table}: {e}")
            raise
    cursor.close()


# ============================================================
# SECTION 6: MAIN
# ============================================================

if __name__ == '__main__':
    print("Connecting to database...")
    conn = get_connection()

    # ----------------------------------------------------------
    # Traders
    # ----------------------------------------------------------
    print(f"\nGenerating {NUM_TRADERS:,} traders...")
    traders = generate_traders(NUM_TRADERS)
    batch_insert(conn, 'traders', traders, [
        'first_name', 'last_name', 'email', 'phone',
        'trader_type', 'trader_status', 'registration_date',
    ])
    # Fetch all trader IDs (includes any previously seeded rows)
    trader_ids = fetch_column(conn, "SELECT trader_id FROM traders")
    print(f"  Total traders in DB: {len(trader_ids):,}")

    # ----------------------------------------------------------
    # Portfolios
    # ----------------------------------------------------------
    print(f"\nGenerating portfolios (1–3 per trader)...")
    portfolios = generate_portfolios(trader_ids)
    batch_insert(conn, 'portfolios', portfolios, [
        'trader_id', 'portfolio_name', 'description',
    ])
    portfolio_ids = fetch_column(conn, "SELECT portfolio_id FROM portfolios")
    print(f"  Total portfolios in DB: {len(portfolio_ids):,}")

    # ----------------------------------------------------------
    # Assets — fetched from DB; seeded by V5 migration
    # ----------------------------------------------------------
    asset_ids = fetch_column(conn, "SELECT asset_id FROM assets")
    if not asset_ids:
        print("  ERROR: No assets found — apply V5 migration before running this script.")
        conn.close()
        raise SystemExit(1)
    print(f"\nFound {len(asset_ids)} assets in DB (seeded by V5).")

    # ----------------------------------------------------------
    # Orders
    # ----------------------------------------------------------
    print(f"\nGenerating {NUM_ORDERS:,} orders...")
    orders = generate_orders(trader_ids, asset_ids, portfolio_ids, NUM_ORDERS)
    batch_insert(conn, 'orders', orders, [
        'trader_id', 'asset_id', 'portfolio_id',
        'order_type', 'order_side', 'quantity', 'limit_price',
        'filled_quantity', 'average_fill_price', 'order_status',
        'order_time', 'cancelled_at', 'cancel_reason',
    ])

    # Fetch FILLED orders from DB to get their auto-assigned order_ids
    cursor = conn.cursor()
    cursor.execute(
        "SELECT o.order_id, o.order_side, o.quantity, o.average_fill_price, o.order_time "
        "FROM orders o "
        "LEFT JOIN settlements s ON s.order_id = o.order_id "
        "WHERE o.order_status = 'FILLED' "
        "AND s.order_id IS NULL"
    )
    cols = ['order_id', 'order_side', 'quantity', 'average_fill_price', 'order_time']
    filled_orders = [dict(zip(cols, row)) for row in cursor.fetchall()]
    cursor.close()
    print(f"  FILLED orders: {len(filled_orders):,}")

    # ----------------------------------------------------------
    # Settlements (one per FILLED order)
    # ----------------------------------------------------------
    print(f"\nGenerating {len(filled_orders):,} settlements...")
    settlements = generate_settlements(filled_orders)
    batch_insert(conn, 'settlements', settlements, [
        'order_id', 'trade_price', 'quantity',
        'gross_amount', 'commission', 'net_amount',
        'settlement_date', 'settlement_status',
    ])

    # ----------------------------------------------------------
    # Accounting ledger (2 entries per FILLED order)
    # ----------------------------------------------------------
    print(f"\nGenerating {len(filled_orders) * 2:,} ledger entries...")
    ledger_entries = generate_ledger_entries(filled_orders)
    batch_insert(conn, 'accounting_ledgers', ledger_entries, [
        'transaction_date', 'debit_account', 'credit_account',
        'amount', 'reference_type', 'reference_id', 'description',
    ])

    conn.close()

    # ----------------------------------------------------------
    # Summary
    # ----------------------------------------------------------
    elapsed = time.time() - start_time
    print(f"\n{'=' * 50}")
    print(f"Generation complete in {elapsed:.1f} seconds")
    print(f"Traders:         {NUM_TRADERS:,}")
    print(f"Orders:          {NUM_ORDERS:,}")
    print(f"Settlements:     {len(settlements):,}")
    print(f"Ledger entries:  {len(ledger_entries):,}")
    print(f"{'=' * 50}")
