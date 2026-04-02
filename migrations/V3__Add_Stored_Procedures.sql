-- ============================================================
-- Flyway Migration: V3__Add_Stored_Procedures.sql
-- Description:     Core business logic stored procedures
-- Procedures:      sp_cancel_order_refund
-- Depends on:      V1__Create_Core_Tables.sql, V2__Add_Indexes_And_Views.sql
-- Author:          system
-- Date:            2026-03-09
-- LOCKING STRATEGY: This procedure uses SELECT ... FOR UPDATE to acquire
--   row-level pessimistic locks before validating or modifying any financial
--   data. This prevents TOCTOU race conditions in concurrent cancellation
--   requests. See MySQL InnoDB locking documentation for details.
-- ============================================================

USE capital_markets_db;

DELIMITER $$

CREATE PROCEDURE sp_cancel_order_refund(
    IN  p_order_id       BIGINT,
    IN  p_trader_id      BIGINT,
    OUT p_success        BOOLEAN,
    OUT p_refund_amount  DECIMAL(15,4),
    OUT p_message        VARCHAR(255)
)
COMMENT 'Cancels an order and processes a refund. Uses pessimistic locking to prevent race conditions.'
proc: BEGIN

    -- --------------------------------------------------------
    -- DECLARE ALL VARIABLES FIRST (MySQL requirement)
    -- --------------------------------------------------------
    DECLARE v_order_status      ENUM('PENDING','PARTIALLY_FILLED','FILLED','CANCELLED','REJECTED');
    DECLARE v_order_side        ENUM('BUY','SELL');
    DECLARE v_asset_id          BIGINT;
    DECLARE v_portfolio_id      BIGINT;
    DECLARE v_quantity          INT;
    DECLARE v_filled_quantity   INT;
    DECLARE v_fill_price        DECIMAL(15,4);
    DECLARE v_refund_calc       DECIMAL(15,4) DEFAULT 0.0000;
    DECLARE v_position_id       BIGINT;
    DECLARE v_position_qty      INT;
    DECLARE v_settlement_id     BIGINT DEFAULT NULL;
    DECLARE v_settlement_status ENUM('PENDING','SETTLED','FAILED','REVERSED');

    -- --------------------------------------------------------
    -- ERROR HANDLER — must be declared before any logic
    -- If ANY SQL error occurs, roll back everything and report failure.
    -- This handler fires on: constraint violations, deadlocks, lock timeouts,
    -- arithmetic errors, and any other SQL exception.
    -- --------------------------------------------------------
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success       = FALSE;
        SET p_refund_amount = 0.0000;
        SET p_message       = 'Transaction failed — all changes rolled back. Check MySQL error log.';
    END;

    -- --------------------------------------------------------
    -- INITIALISE OUTPUT PARAMETERS
    -- --------------------------------------------------------
    SET p_success       = FALSE;
    SET p_refund_amount = 0.0000;
    SET p_message       = '';

    -- --------------------------------------------------------
    -- START TRANSACTION — all operations below are atomic
    -- --------------------------------------------------------
    START TRANSACTION;

    -- --------------------------------------------------------
    -- PHASE 1: ACQUIRE ROW-LEVEL LOCKS (BEFORE reading any values)
    --
    -- CRITICAL: We must lock the target rows BEFORE checking their
    -- values. If we read-then-lock, another concurrent transaction
    -- could modify the row between our read and our lock acquisition,
    -- leading to a TOCTOU race condition and potential double-refund.
    --
    -- SELECT ... FOR UPDATE acquires an exclusive row lock.
    -- Any other transaction attempting to read these rows with FOR UPDATE
    -- will BLOCK until this transaction COMMITs or ROLLBACKs.
    -- --------------------------------------------------------

    -- Lock the order row and read its current values atomically
    SELECT
        order_status, order_side, asset_id, portfolio_id,
        quantity, filled_quantity, average_fill_price
    INTO
        v_order_status, v_order_side, v_asset_id, v_portfolio_id,
        v_quantity, v_filled_quantity, v_fill_price
    FROM orders
    WHERE order_id = p_order_id
      AND trader_id = p_trader_id   -- Authorization check built into the lock
    FOR UPDATE;                     -- Acquire exclusive row lock

    -- Check if the order was found (SELECT INTO sets variables to NULL if no row)
    IF v_order_status IS NULL THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Order not found or unauthorized. Cancellation rejected.';
        LEAVE proc;  -- Exit the BEGIN...END block (MySQL label syntax)
    END IF;

    -- --------------------------------------------------------
    -- PHASE 2: PRE-CHECKS (validated while holding the lock)
    -- Safe to check values now — no other transaction can change them.
    -- --------------------------------------------------------

    -- Check 1: Is the order in a cancellable state?
    IF v_order_status NOT IN ('PENDING', 'PARTIALLY_FILLED') THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = CONCAT('Order cannot be cancelled. Current status: ', v_order_status);
        LEAVE proc;
    END IF;

    -- Lock the position row (if it exists) for BUY orders that modified positions
    IF v_order_side = 'BUY' AND v_filled_quantity > 0 THEN
        SELECT position_id, quantity
        INTO v_position_id, v_position_qty
        FROM positions
        WHERE portfolio_id = v_portfolio_id AND asset_id = v_asset_id
        FOR UPDATE;  -- Lock the position row
    END IF;

    -- Check if a settlement already exists for this order
    SELECT settlement_id, settlement_status
    INTO v_settlement_id, v_settlement_status
    FROM settlements
    WHERE order_id = p_order_id
    FOR UPDATE;  -- Lock the settlement row if it exists

    -- Check 2: If fully settled, cannot cancel
    IF v_settlement_status = 'SETTLED' THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Order has already been settled. Contact compliance to reverse.';
        LEAVE proc;
    END IF;

    -- --------------------------------------------------------
    -- PHASE 3: EXECUTE THE CANCELLATION (all under the same transaction)
    -- --------------------------------------------------------

    -- Step 3.1: Mark the order as cancelled
    UPDATE orders
    SET
        order_status = 'CANCELLED',
        cancelled_at = NOW(),
        cancel_reason = 'Customer requested cancellation',
        updated_at = NOW()
    WHERE order_id = p_order_id;

    -- Step 3.2: Process refund for filled portion (if any)
    IF v_filled_quantity > 0 THEN
        SET v_refund_calc = v_filled_quantity * v_fill_price;

        IF v_order_side = 'BUY' THEN
            -- Reverse the position change for the filled quantity
            IF v_position_id IS NOT NULL THEN
                IF v_position_qty <= v_filled_quantity THEN
                    -- Position would be zero or negative — delete it
                    DELETE FROM positions WHERE position_id = v_position_id;
                ELSE
                    -- Reduce the position
                    UPDATE positions
                    SET quantity = quantity - v_filled_quantity,
                        updated_at = NOW()
                    WHERE position_id = v_position_id;
                END IF;
            END IF;

            -- Refund ledger entry pair (debit TRADING_ACCOUNT, credit CASH)
            INSERT INTO accounting_ledgers
                (transaction_date, debit_account, credit_account, amount,
                 reference_type, reference_id, description)
            VALUES
                (NOW(6), 'TRADING_ACCOUNT', 'CASH', v_refund_calc,
                 'ORDER', p_order_id,
                 CONCAT('Refund for cancelled BUY order #', p_order_id));

            INSERT INTO accounting_ledgers
                (transaction_date, debit_account, credit_account, amount,
                 reference_type, reference_id, description)
            VALUES
                (NOW(6), 'CASH', 'TRADING_ACCOUNT', v_refund_calc,
                 'ORDER', p_order_id,
                 CONCAT('Offset entry for BUY refund order #', p_order_id));

        ELSE -- SELL order
            -- Restore the shares to the position
            IF v_position_id IS NOT NULL THEN
                UPDATE positions
                SET quantity = quantity + v_filled_quantity,
                    updated_at = NOW()
                WHERE position_id = v_position_id;
            END IF;

            -- Reverse ledger entries for SELL cancellation
            INSERT INTO accounting_ledgers
                (transaction_date, debit_account, credit_account, amount,
                 reference_type, reference_id, description)
            VALUES
                (NOW(6), 'SECURITIES', 'CASH', v_refund_calc,
                 'ORDER', p_order_id,
                 CONCAT('Reversal for cancelled SELL order #', p_order_id)),
                (NOW(6), 'CASH', 'SECURITIES', v_refund_calc,
                 'ORDER', p_order_id,
                 CONCAT('Offset entry for SELL reversal order #', p_order_id));
        END IF;
    END IF;

    -- Step 3.3: Reverse any pending settlement
    IF v_settlement_id IS NOT NULL AND v_settlement_status = 'PENDING' THEN
        UPDATE settlements
        SET settlement_status = 'REVERSED', updated_at = NOW()
        WHERE settlement_id = v_settlement_id;
    END IF;

    -- --------------------------------------------------------
    -- COMMIT — releases all locks acquired with FOR UPDATE
    -- --------------------------------------------------------
    COMMIT;

    -- --------------------------------------------------------
    -- SUCCESS OUTPUT
    -- --------------------------------------------------------
    SET p_success       = TRUE;
    SET p_refund_amount = v_refund_calc;
    SET p_message       = CONCAT('Order #', p_order_id,
                          ' cancelled successfully. Refund: $',
                          FORMAT(v_refund_calc, 2));

END proc$$

DELIMITER ;


-- ============================================================
-- Test calls (uncomment to run manually in MySQL Workbench):
-- ============================================================

-- CALL sp_cancel_order_refund(1, 1, @ok, @refund, @msg);
-- SELECT @ok AS success, @refund AS refund_amount, @msg AS message;
--
-- Test authorization failure (wrong trader):
-- CALL sp_cancel_order_refund(1, 99, @ok, @refund, @msg);
-- SELECT @ok, @refund, @msg;
--
-- Test already-cancelled:
-- CALL sp_cancel_order_refund(1, 1, @ok, @refund, @msg);  -- cancel it
-- CALL sp_cancel_order_refund(1, 1, @ok, @refund, @msg);  -- try again
-- SELECT @ok, @msg;
