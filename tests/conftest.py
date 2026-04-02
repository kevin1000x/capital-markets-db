# Run with: pytest tests/ -v
# Requirements: pip install pytest mysql-connector-python
# The database must be running with all V1-V4 migrations applied.

import os

import pytest
import mysql.connector


@pytest.fixture(scope='function')
def db_conn():
    """Provides a fresh database connection for each test.
    Rolls back any uncommitted changes after the test."""
    conn = mysql.connector.connect(
        host=os.environ.get('MYSQL_HOST', '127.0.0.1'),
        port=int(os.environ.get('MYSQL_PORT', '3306')),
        user=os.environ.get('MYSQL_USER', 'root'),
        password=os.environ.get('MYSQL_PASSWORD', ''),
        database=os.environ.get('MYSQL_DATABASE', 'capital_markets_db'),
        autocommit=False
    )
    yield conn
    conn.rollback()
    conn.close()


@pytest.fixture(scope='function')
def test_setup(db_conn):
    """Inserts minimal test data for one complete order scenario.
    Returns a dict with all inserted IDs.
    Cleans up (DELETE) all inserted rows after each test."""
    cursor = db_conn.cursor()
    trader_id = portfolio_id = order_id = None
    try:
        # Idempotent cleanup — safe if previous teardown failed
        cursor.execute("SET FOREIGN_KEY_CHECKS = 0")
        cursor.execute("DELETE FROM traders WHERE email = 'test.trader.pytest@example.com'")
        cursor.execute("SET FOREIGN_KEY_CHECKS = 1")
        db_conn.commit()

        # Insert test trader
        cursor.execute(
            "INSERT INTO traders (first_name, last_name, email, trader_type) "
            "VALUES ('Test', 'Trader', 'test.trader.pytest@example.com', 'INDIVIDUAL')"
        )
        trader_id = cursor.lastrowid

        # Use first existing asset (from V5 seed data)
        cursor.execute("SELECT asset_id FROM assets LIMIT 1")
        asset_id = cursor.fetchone()[0]

        # Insert test portfolio
        cursor.execute(
            "INSERT INTO portfolios (trader_id, portfolio_name) VALUES (%s, 'Test Portfolio')",
            (trader_id,)
        )
        portfolio_id = cursor.lastrowid

        # Insert test PENDING BUY order
        cursor.execute(
            "INSERT INTO orders (trader_id, asset_id, portfolio_id, order_type, "
            "order_side, quantity, limit_price, order_status) "
            "VALUES (%s, %s, %s, 'LIMIT', 'BUY', 100, 150.0000, 'PENDING')",
            (trader_id, asset_id, portfolio_id)
        )
        order_id = cursor.lastrowid

        db_conn.commit()

        yield {
            'trader_id': trader_id,
            'asset_id': asset_id,
            'portfolio_id': portfolio_id,
            'order_id': order_id
        }
    finally:
        try:
            cursor.execute("SET FOREIGN_KEY_CHECKS = 0")
            if order_id is not None:
                cursor.execute("DELETE FROM accounting_ledgers WHERE reference_id = %s", (order_id,))
                cursor.execute("DELETE FROM settlements WHERE order_id = %s", (order_id,))
                cursor.execute("DELETE FROM order_history WHERE order_id = %s", (order_id,))
                cursor.execute("DELETE FROM orders WHERE order_id = %s", (order_id,))
            if portfolio_id is not None:
                cursor.execute("DELETE FROM portfolios WHERE portfolio_id = %s", (portfolio_id,))
            if trader_id is not None:
                cursor.execute("DELETE FROM traders WHERE trader_id = %s", (trader_id,))
            cursor.execute("SET FOREIGN_KEY_CHECKS = 1")
            db_conn.commit()
        except Exception as cleanup_err:
            print(f"Cleanup error (non-fatal): {cleanup_err}")
            cursor.execute("SET FOREIGN_KEY_CHECKS = 1")
        finally:
            cursor.close()
