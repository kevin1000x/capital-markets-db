import os
import mysql.connector


def run():
    conn = mysql.connector.connect(
        host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        user=os.environ.get("MYSQL_USER", "root"),
        password=os.environ.get("MYSQL_PASSWORD", ""),
        database=os.environ.get("MYSQL_DATABASE", "capital_markets_db"),
    )
    cursor = conn.cursor()

    with open("docs/output/database_schema.txt", "w") as f:
        cursor.execute("SHOW TABLES")
        f.write("=== SHOW TABLES ===\n")
        titles = [i[0] for i in cursor.description]
        f.write("\t".join(titles) + "\n")
        f.write("-" * 40 + "\n")
        for row in cursor.fetchall():
            f.write("\t".join(str(r) for r in row) + "\n")

        f.write("\n=== DESCRIBE orders ===\n")
        cursor.execute("DESCRIBE orders")
        titles = [i[0] for i in cursor.description]
        f.write("\t".join(titles) + "\n")
        f.write("-" * 80 + "\n")
        for row in cursor.fetchall():
            f.write("\t".join(str(r) for r in row) + "\n")

        f.write("\n=== DESCRIBE positions ===\n")
        cursor.execute("DESCRIBE positions")
        titles = [i[0] for i in cursor.description]
        f.write("\t".join(titles) + "\n")
        f.write("-" * 80 + "\n")
        for row in cursor.fetchall():
            f.write("\t".join(str(r) for r in row) + "\n")

    with open("docs/output/data_generation_log.txt", "w") as f:
        # Just write out table counts to prove data was generated
        f.write("=== DATABASE ROW COUNTS ===\n")
        for table in ["traders", "assets", "portfolios", "orders", "positions", "settlements", "accounting_ledgers"]:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            f.write(f"{table}: {cursor.fetchone()[0]:,}\n")

    with open("docs/output/sp_test_output.txt", "w") as f:
        f.write("=== CALL sp_cancel_order_refund ===\n")
        cursor.execute("SELECT order_id, trader_id FROM orders WHERE order_status IN ('PENDING', 'PARTIALLY_FILLED') LIMIT 1")
        row = cursor.fetchone()
        if row:
            order_id, trader_id = row
            cursor.callproc('sp_cancel_order_refund', [order_id, trader_id, 0, 0.0, ''])
            cursor.execute("SELECT @_sp_cancel_order_refund_2, @_sp_cancel_order_refund_3, @_sp_cancel_order_refund_4")
            result = cursor.fetchone()
            f.write(f"Parameters: order_id={order_id}, trader_id={trader_id}\n")
            f.write(f"Success: {result[0]}\n")
            f.write(f"Refund:  {result[1]}\n")
            f.write(f"Message: {result[2]}\n")
            conn.commit()
        else:
            f.write("No PENDING orders found to cancel.\n")

    with open("docs/output/security_grants.txt", "w") as f:
        f.write("=== SHOW GRANTS FOR 'spring_app'@'localhost' ===\n")
        cursor.execute("SHOW GRANTS FOR 'spring_app'@'localhost'")
        for row in cursor.fetchall():
            f.write(str(row[0]) + "\n")

        f.write("\n=== SHOW GRANTS FOR 'auditor'@'10.0.0.%' ===\n")
        try:
            cursor.execute("SHOW GRANTS FOR 'auditor'@'10.0.0.%'")
            for row in cursor.fetchall():
                f.write(str(row[0]) + "\n")
        except Exception as e:
            f.write(str(e) + "\n")

    cursor.close()
    conn.close()
    print("Queries executed successfully.")


if __name__ == '__main__':
    run()
