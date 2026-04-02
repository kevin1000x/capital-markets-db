# Run with: pytest tests/ -v
# Requirements: pip install pytest mysql-connector-python
# The database must be running with all V1-V4 migrations applied.

import os
import threading

import mysql.connector
import pytest


def test_cancel_valid_pending_order(db_conn, test_setup):
    """Cancelling a valid PENDING order should succeed with correct outputs."""
    cursor = db_conn.cursor()
    order_id = test_setup['order_id']
    trader_id = test_setup['trader_id']

    result = cursor.callproc('sp_cancel_order_refund',
                             [order_id, trader_id, 0, 0.0, ''])
    p_success = result[2]
    p_refund_amount = result[3]
    p_message = result[4]

    assert p_success == 1
    assert p_refund_amount == 0.0
    assert 'cancelled' in p_message.lower()

    # Verify DB state: order is now CANCELLED
    cursor.execute("SELECT order_status FROM orders WHERE order_id = %s",
                   (order_id,))
    assert cursor.fetchone()[0] == 'CANCELLED'

    # Verify audit trail: AFTER UPDATE trigger fired
    cursor.execute(
        "SELECT COUNT(*) FROM order_history "
        "WHERE order_id = %s AND change_type = 'UPDATE'", (order_id,))
    assert cursor.fetchone()[0] == 1
    cursor.close()


def test_cancel_already_cancelled_order(db_conn, test_setup):
    """Cancelling an already-cancelled order should fail gracefully."""
    cursor = db_conn.cursor()
    order_id = test_setup['order_id']
    trader_id = test_setup['trader_id']

    # First call: cancel the order (valid)
    cursor.callproc('sp_cancel_order_refund',
                     [order_id, trader_id, 0, 0.0, ''])

    # Second call: attempt to cancel again
    result = cursor.callproc('sp_cancel_order_refund',
                             [order_id, trader_id, 0, 0.0, ''])
    p_success = result[2]
    p_message = result[4]

    assert p_success == 0
    assert 'CANCELLED' in p_message or 'cannot be cancelled' in p_message
    cursor.close()


def test_cancel_wrong_trader_rejected(db_conn, test_setup):
    """An attempt to cancel another trader's order must be rejected."""
    cursor = db_conn.cursor()
    order_id = test_setup['order_id']

    result = cursor.callproc('sp_cancel_order_refund',
                             [order_id, 99999, 0, 0.0, ''])
    p_success = result[2]
    p_message = result[4]

    assert p_success == 0
    assert 'not found' in p_message.lower() or 'unauthorized' in p_message.lower()

    # Verify no state change: order is still PENDING
    cursor.execute("SELECT order_status FROM orders WHERE order_id = %s",
                   (order_id,))
    assert cursor.fetchone()[0] == 'PENDING'
    cursor.close()


def test_rollback_on_nonexistent_order(db_conn):
    """Calling the procedure with a nonexistent order_id should fail cleanly."""
    cursor = db_conn.cursor()

    result = cursor.callproc('sp_cancel_order_refund',
                             [999999, 999999, 0, 0.0, ''])
    p_success = result[2]
    p_message = result[4]

    assert p_success == 0
    assert len(p_message) > 0

    # Verify no orphaned ledger entries
    cursor.execute(
        "SELECT COUNT(*) FROM accounting_ledgers WHERE reference_id = 999999")
    assert cursor.fetchone()[0] == 0

    # Verify no phantom order rows
    cursor.execute("SELECT COUNT(*) FROM orders WHERE order_id = 999999")
    assert cursor.fetchone()[0] == 0
    cursor.close()


def test_concurrent_cancellation_locking(db_conn, test_setup):
    """Only one of two concurrent cancel requests on the same order should succeed.
    This test verifies that SELECT...FOR UPDATE prevents double-processing."""
    order_id = test_setup['order_id']
    trader_id = test_setup['trader_id']
    results = []

    def attempt_cancel(oid, tid):
        conn = None
        try:
            conn = mysql.connector.connect(
                host=os.environ.get('MYSQL_HOST', '127.0.0.1'),
                port=int(os.environ.get('MYSQL_PORT', '3306')),
                user=os.environ.get('MYSQL_USER', 'root'),
                password=os.environ.get('MYSQL_PASSWORD', ''),
                database=os.environ.get('MYSQL_DATABASE', 'capital_markets_db'),
                autocommit=False
            )
            cur = conn.cursor()
            cur.execute("SET SESSION innodb_lock_wait_timeout = 5")
            res = cur.callproc('sp_cancel_order_refund',
                               [oid, tid, 0, 0.0, ''])
            conn.commit()
            results.append({'success': bool(res[2]), 'message': res[4]})
            cur.close()
        except Exception as e:
            results.append({'success': False, 'error': str(e)})
        finally:
            if conn:
                conn.close()

    t1 = threading.Thread(target=attempt_cancel, args=(order_id, trader_id))
    t2 = threading.Thread(target=attempt_cancel, args=(order_id, trader_id))
    t1.start()
    t2.start()
    t1.join(timeout=15)
    t2.join(timeout=15)

    # Exactly one thread should have succeeded
    success_count = sum(1 for r in results if r.get('success'))
    assert success_count == 1, f"Expected 1 success, got {success_count}: {results}"

    # Order was cancelled exactly once
    cursor = db_conn.cursor()
    cursor.execute("SELECT order_status FROM orders WHERE order_id = %s",
                   (order_id,))
    assert cursor.fetchone()[0] == 'CANCELLED'

    # No double-processing: 0 ledger entries (PENDING order has no fills)
    cursor.execute(
        "SELECT COUNT(*) FROM accounting_ledgers WHERE reference_id = %s",
        (order_id,))
    ledger_count = cursor.fetchone()[0]
    assert ledger_count in (0, 2), \
        f"Expected 0 or 2 ledger entries, got {ledger_count}"
    cursor.close()
