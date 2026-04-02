-- ============================================================
-- V4: Add Audit Triggers
-- Author: system
-- Date: 2026-03-08
-- Description: Creates INSERT-only history tables for orders,
--              positions, accounting_ledgers, and settlements,
--              then attaches AFTER UPDATE and AFTER DELETE
--              triggers to capture before-images into those
--              tables for compliance auditing.
-- NOTE: This file depends on V1 core tables and must not be
--       applied before V1 succeeds.
-- ============================================================

USE capital_markets_db;

-- ============================================================
-- Drop old triggers (previous domain model: clients/accounts/
-- instruments/trades). Idempotent — safe to re-run.
-- ============================================================

DROP TRIGGER IF EXISTS trg_clients_after_insert;
DROP TRIGGER IF EXISTS trg_clients_after_update;
DROP TRIGGER IF EXISTS trg_clients_after_delete;
DROP TRIGGER IF EXISTS trg_accounts_after_insert;
DROP TRIGGER IF EXISTS trg_accounts_after_update;
DROP TRIGGER IF EXISTS trg_orders_after_insert;
DROP TRIGGER IF EXISTS trg_orders_after_update;
DROP TRIGGER IF EXISTS trg_trades_after_insert;
DROP TRIGGER IF EXISTS trg_trades_after_update;
DROP TRIGGER IF EXISTS trg_positions_after_update;

-- ============================================================
-- PART 1: History Tables
-- Each table mirrors ALL columns of its source table
-- (source PK: NOT NULL, no AUTO_INCREMENT; all other source
-- columns: NULL), followed by 4 audit columns at end.
-- These tables are INSERT-ONLY — no role should hold
-- UPDATE or DELETE on them (FR-AUD-003).
-- ============================================================

CREATE TABLE IF NOT EXISTS order_history (
    -- Mirrored source columns (from orders)
    order_id            BIGINT          NOT NULL,
    trader_id           BIGINT          NULL,
    asset_id            BIGINT          NULL,
    portfolio_id        BIGINT          NULL,
    order_type          ENUM('MARKET','LIMIT','STOP','STOP_LIMIT')                          NULL,
    order_side          ENUM('BUY','SELL')                                                   NULL,
    quantity            INT             NULL,
    limit_price         DECIMAL(15,4)   NULL,
    filled_quantity     INT             NULL,
    average_fill_price  DECIMAL(15,4)   NULL,
    order_status        ENUM('PENDING','PARTIALLY_FILLED','FILLED','CANCELLED','REJECTED')   NULL,
    order_time          DATETIME(6)     NULL,
    cancelled_at        DATETIME        NULL,
    cancel_reason       VARCHAR(255)    NULL,
    created_at          DATETIME        NULL,
    updated_at          DATETIME        NULL,
    -- Audit metadata
    history_id          BIGINT          NOT NULL AUTO_INCREMENT,
    changed_at          DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    changed_by          VARCHAR(100)    NOT NULL DEFAULT (CURRENT_USER()),
    change_type         ENUM('UPDATE','DELETE') NOT NULL,

    PRIMARY KEY (history_id),
    CONSTRAINT fk_order_history_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_order_history_order_id   (order_id),
    INDEX idx_order_history_changed_at (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable audit history for orders. INSERT-ONLY.';


CREATE TABLE IF NOT EXISTS position_history (
    -- Mirrored source columns (from positions)
    position_id     BIGINT          NOT NULL,
    portfolio_id    BIGINT          NULL,
    asset_id        BIGINT          NULL,
    quantity        INT             NULL,
    average_cost    DECIMAL(15,4)   NULL,
    current_value   DECIMAL(15,4)   NULL,
    unrealized_pnl  DECIMAL(15,4)   NULL,
    created_at      DATETIME        NULL,
    updated_at      DATETIME        NULL,
    -- Audit metadata
    history_id      BIGINT          NOT NULL AUTO_INCREMENT,
    changed_at      DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    changed_by      VARCHAR(100)    NOT NULL DEFAULT (CURRENT_USER()),
    change_type     ENUM('UPDATE','DELETE') NOT NULL,

    PRIMARY KEY (history_id),
    CONSTRAINT fk_position_history_position FOREIGN KEY (position_id)
        REFERENCES positions(position_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_position_history_position_id (position_id),
    INDEX idx_position_history_changed_at  (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable audit history for positions. INSERT-ONLY.';


CREATE TABLE IF NOT EXISTS ledger_audit (
    -- Mirrored source columns (from accounting_ledgers)
    ledger_id           BIGINT          NOT NULL,
    transaction_date    DATETIME(6)     NULL,
    debit_account       VARCHAR(50)     NULL,
    credit_account      VARCHAR(50)     NULL,
    amount              DECIMAL(15,4)   NULL,
    reference_type      ENUM('ORDER','SETTLEMENT','ADJUSTMENT') NULL,
    reference_id        BIGINT          NULL,
    description         TEXT            NULL,
    created_at          DATETIME        NULL,
    updated_at          DATETIME        NULL,
    -- Audit metadata
    history_id          BIGINT          NOT NULL AUTO_INCREMENT,
    changed_at          DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    changed_by          VARCHAR(100)    NOT NULL DEFAULT (CURRENT_USER()),
    change_type         ENUM('UPDATE','DELETE') NOT NULL,

    PRIMARY KEY (history_id),
    CONSTRAINT fk_ledger_audit_ledger FOREIGN KEY (ledger_id)
        REFERENCES accounting_ledgers(ledger_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_ledger_audit_ledger_id  (ledger_id),
    INDEX idx_ledger_audit_changed_at (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable audit history for accounting_ledgers. INSERT-ONLY.';


CREATE TABLE IF NOT EXISTS settlement_history (
    -- Mirrored source columns (from settlements)
    settlement_id       BIGINT          NOT NULL,
    order_id            BIGINT          NULL,
    trade_price         DECIMAL(15,4)   NULL,
    quantity            INT             NULL,
    gross_amount        DECIMAL(15,4)   NULL,
    commission          DECIMAL(15,4)   NULL,
    net_amount          DECIMAL(15,4)   NULL,
    settlement_date     DATE            NULL,
    settlement_status   ENUM('PENDING','SETTLED','FAILED','REVERSED') NULL,
    created_at          DATETIME        NULL,
    updated_at          DATETIME        NULL,
    -- Audit metadata
    history_id          BIGINT          NOT NULL AUTO_INCREMENT,
    changed_at          DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    changed_by          VARCHAR(100)    NOT NULL DEFAULT (CURRENT_USER()),
    change_type         ENUM('UPDATE','DELETE') NOT NULL,

    PRIMARY KEY (history_id),
    CONSTRAINT fk_settlement_history_settlement FOREIGN KEY (settlement_id)
        REFERENCES settlements(settlement_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_settlement_history_settlement_id (settlement_id),
    INDEX idx_settlement_history_changed_at    (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable audit history for settlements. INSERT-ONLY.';


-- ============================================================
-- PART 2 & 3: Triggers
-- PART 2: AFTER UPDATE — capture before-image (OLD.*)
-- PART 3: AFTER DELETE — capture deleted row (OLD.*)
-- All triggers are simple (no conditional branching).
-- ============================================================

DELIMITER $$

-- ===========================
-- orders — AFTER UPDATE
-- ===========================
CREATE TRIGGER trg_orders_after_update
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    INSERT INTO order_history (
        order_id, trader_id, asset_id, portfolio_id,
        order_type, order_side, quantity, limit_price,
        filled_quantity, average_fill_price, order_status, order_time,
        cancelled_at, cancel_reason, created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.order_id, OLD.trader_id, OLD.asset_id, OLD.portfolio_id,
        OLD.order_type, OLD.order_side, OLD.quantity, OLD.limit_price,
        OLD.filled_quantity, OLD.average_fill_price, OLD.order_status, OLD.order_time,
        OLD.cancelled_at, OLD.cancel_reason, OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'UPDATE'
    );
END$$

-- ===========================
-- orders — AFTER DELETE
-- ===========================
CREATE TRIGGER trg_orders_after_delete
AFTER DELETE ON orders
FOR EACH ROW
BEGIN
    INSERT INTO order_history (
        order_id, trader_id, asset_id, portfolio_id,
        order_type, order_side, quantity, limit_price,
        filled_quantity, average_fill_price, order_status, order_time,
        cancelled_at, cancel_reason, created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.order_id, OLD.trader_id, OLD.asset_id, OLD.portfolio_id,
        OLD.order_type, OLD.order_side, OLD.quantity, OLD.limit_price,
        OLD.filled_quantity, OLD.average_fill_price, OLD.order_status, OLD.order_time,
        OLD.cancelled_at, OLD.cancel_reason, OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'DELETE'
    );
END$$

-- ===========================
-- positions — AFTER UPDATE
-- ===========================
CREATE TRIGGER trg_positions_after_update
AFTER UPDATE ON positions
FOR EACH ROW
BEGIN
    INSERT INTO position_history (
        position_id, portfolio_id, asset_id, quantity,
        average_cost, current_value, unrealized_pnl,
        created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.position_id, OLD.portfolio_id, OLD.asset_id, OLD.quantity,
        OLD.average_cost, OLD.current_value, OLD.unrealized_pnl,
        OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'UPDATE'
    );
END$$

-- ===========================
-- positions — AFTER DELETE
-- ===========================
CREATE TRIGGER trg_positions_after_delete
AFTER DELETE ON positions
FOR EACH ROW
BEGIN
    INSERT INTO position_history (
        position_id, portfolio_id, asset_id, quantity,
        average_cost, current_value, unrealized_pnl,
        created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.position_id, OLD.portfolio_id, OLD.asset_id, OLD.quantity,
        OLD.average_cost, OLD.current_value, OLD.unrealized_pnl,
        OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'DELETE'
    );
END$$

-- ===========================
-- accounting_ledgers — AFTER UPDATE
-- ===========================
CREATE TRIGGER trg_accounting_ledgers_after_update
AFTER UPDATE ON accounting_ledgers
FOR EACH ROW
BEGIN
    INSERT INTO ledger_audit (
        ledger_id, transaction_date, debit_account, credit_account,
        amount, reference_type, reference_id, description,
        created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.ledger_id, OLD.transaction_date, OLD.debit_account, OLD.credit_account,
        OLD.amount, OLD.reference_type, OLD.reference_id, OLD.description,
        OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'UPDATE'
    );
END$$

-- ===========================
-- accounting_ledgers — AFTER DELETE
-- ===========================
CREATE TRIGGER trg_accounting_ledgers_after_delete
AFTER DELETE ON accounting_ledgers
FOR EACH ROW
BEGIN
    INSERT INTO ledger_audit (
        ledger_id, transaction_date, debit_account, credit_account,
        amount, reference_type, reference_id, description,
        created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.ledger_id, OLD.transaction_date, OLD.debit_account, OLD.credit_account,
        OLD.amount, OLD.reference_type, OLD.reference_id, OLD.description,
        OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'DELETE'
    );
END$$

-- ===========================
-- settlements — AFTER UPDATE
-- ===========================
CREATE TRIGGER trg_settlements_after_update
AFTER UPDATE ON settlements
FOR EACH ROW
BEGIN
    INSERT INTO settlement_history (
        settlement_id, order_id, trade_price, quantity,
        gross_amount, commission, net_amount,
        settlement_date, settlement_status,
        created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.settlement_id, OLD.order_id, OLD.trade_price, OLD.quantity,
        OLD.gross_amount, OLD.commission, OLD.net_amount,
        OLD.settlement_date, OLD.settlement_status,
        OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'UPDATE'
    );
END$$

-- ===========================
-- settlements — AFTER DELETE
-- ===========================
CREATE TRIGGER trg_settlements_after_delete
AFTER DELETE ON settlements
FOR EACH ROW
BEGIN
    INSERT INTO settlement_history (
        settlement_id, order_id, trade_price, quantity,
        gross_amount, commission, net_amount,
        settlement_date, settlement_status,
        created_at, updated_at,
        changed_at, changed_by, change_type
    ) VALUES (
        OLD.settlement_id, OLD.order_id, OLD.trade_price, OLD.quantity,
        OLD.gross_amount, OLD.commission, OLD.net_amount,
        OLD.settlement_date, OLD.settlement_status,
        OLD.created_at, OLD.updated_at,
        NOW(6), CURRENT_USER(), 'DELETE'
    );
END$$

DELIMITER ;


-- ============================================================
-- PART 4: Verification Queries (commented out)
-- Run manually to confirm tables and triggers are in place.
-- ============================================================

-- SELECT 'order_history'      AS tbl, COUNT(*) AS rows FROM order_history;
-- SELECT 'position_history'   AS tbl, COUNT(*) AS rows FROM position_history;
-- SELECT 'ledger_audit'       AS tbl, COUNT(*) AS rows FROM ledger_audit;
-- SELECT 'settlement_history' AS tbl, COUNT(*) AS rows FROM settlement_history;
-- SHOW TRIGGERS WHERE `Table` IN ('orders','positions','accounting_ledgers','settlements');


-- Rollback (commented out)
-- DROP TRIGGER IF EXISTS trg_settlements_after_delete;
-- DROP TRIGGER IF EXISTS trg_settlements_after_update;
-- DROP TRIGGER IF EXISTS trg_accounting_ledgers_after_delete;
-- DROP TRIGGER IF EXISTS trg_accounting_ledgers_after_update;
-- DROP TRIGGER IF EXISTS trg_positions_after_delete;
-- DROP TRIGGER IF EXISTS trg_positions_after_update;
-- DROP TRIGGER IF EXISTS trg_orders_after_delete;
-- DROP TRIGGER IF EXISTS trg_orders_after_update;
-- DROP TABLE IF EXISTS settlement_history;
-- DROP TABLE IF EXISTS ledger_audit;
-- DROP TABLE IF EXISTS position_history;
-- DROP TABLE IF EXISTS order_history;
