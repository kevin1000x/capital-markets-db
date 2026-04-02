-- ============================================================
-- Flyway Migration: V2__Add_Indexes_And_Views.sql
-- Description:     Performance indexes and reporting views
-- Depends on:      V1__Create_Core_Tables.sql
-- Author:          system
-- Date:            2026-03-09
-- ============================================================

USE capital_markets_db;


-- ============================================================
-- SECTION 1: INDEXES
-- All created with IF NOT EXISTS for idempotent re-runs.
-- ============================================================

-- ------------------------------------------------------------
-- orders indexes
-- ------------------------------------------------------------

-- Supports: "show all orders for trader X sorted by time"
-- Composite covers both trader filtering and chronological sort in one scan.
CREATE INDEX idx_orders_trader_date
    ON orders (trader_id, order_time);

-- Supports: "find all orders for a given asset" (order book aggregation)
CREATE INDEX idx_orders_asset
    ON orders (asset_id);

-- Supports: "find all PENDING orders" — used by order matching engine
CREATE INDEX idx_orders_status
    ON orders (order_status);

-- Supports: "find all orders for a given portfolio"
CREATE INDEX idx_orders_portfolio
    ON orders (portfolio_id);


-- ------------------------------------------------------------
-- positions indexes
-- ------------------------------------------------------------

-- Supports: "show all positions in a portfolio"
CREATE INDEX idx_positions_portfolio
    ON positions (portfolio_id);

-- Supports: "find which portfolios hold a given asset" (risk aggregation)
CREATE INDEX idx_positions_asset
    ON positions (asset_id);


-- ------------------------------------------------------------
-- accounting_ledgers indexes
-- ------------------------------------------------------------

-- Supports: "generate daily ledger report" (date-range financial reporting)
CREATE INDEX idx_ledger_date
    ON accounting_ledgers (transaction_date);

-- Supports: "find all ledger entries for a given order or settlement"
-- Composite matches the polymorphic (reference_type, reference_id) lookup pattern.
CREATE INDEX idx_ledger_reference
    ON accounting_ledgers (reference_type, reference_id);


-- ------------------------------------------------------------
-- settlements indexes
-- ------------------------------------------------------------

-- Supports: "find all settlements due on a given date" (T+2 batch processing)
CREATE INDEX idx_settlements_date
    ON settlements (settlement_date);

-- Supports: "find all PENDING settlements" (monitoring dashboard)
CREATE INDEX idx_settlements_status
    ON settlements (settlement_status);


-- ------------------------------------------------------------
-- traders indexes
-- ------------------------------------------------------------

-- Supports: "login / trader lookup by email"
-- Note: covered by UNIQUE KEY uq_traders_email; named index for explicit query hints.
CREATE INDEX idx_traders_email
    ON traders (email);


-- ------------------------------------------------------------
-- assets indexes
-- ------------------------------------------------------------

-- Supports: "asset lookup by ticker symbol" (order entry)
-- Note: covered by UNIQUE KEY uq_assets_ticker; named index for explicit query hints.
CREATE INDEX idx_assets_ticker
    ON assets (ticker_symbol);


-- ============================================================
-- SECTION 2: VIEWS
-- All created with CREATE OR REPLACE for idempotent re-runs.
-- ============================================================

-- ------------------------------------------------------------
-- VIEW: vw_portfolio_summary
-- Purpose: Portfolio-level overview for the trader dashboard.
-- Returns one row per portfolio including aggregate market value
-- and unrealised P&L across all held positions.
-- Joins: portfolios → traders (INNER), portfolios → positions (LEFT)
-- LEFT JOIN ensures empty portfolios with no positions are included.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_portfolio_summary AS
SELECT
    p.portfolio_id,
    p.portfolio_name,
    p.trader_id,
    CONCAT(t.first_name, ' ', t.last_name)  AS trader_full_name,
    COUNT(pos.position_id)                   AS total_positions,
    COALESCE(SUM(pos.current_value),  0)     AS total_market_value,
    COALESCE(SUM(pos.unrealized_pnl), 0)     AS total_unrealized_pnl
FROM portfolios p
JOIN  traders   t   ON t.trader_id    = p.trader_id
LEFT  JOIN positions pos ON pos.portfolio_id = p.portfolio_id
GROUP BY p.portfolio_id, p.portfolio_name, p.trader_id, trader_full_name;


-- ------------------------------------------------------------
-- VIEW: vw_active_orders
-- Purpose: Real-time view of all open orders for the order
-- management dashboard and matching engine monitoring.
-- Filter: PENDING and PARTIALLY_FILLED orders only.
-- Joins: orders → assets (INNER), orders → traders (INNER)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_active_orders AS
SELECT
    o.order_id,
    o.order_time,
    o.order_side,
    o.order_type,
    a.ticker_symbol,
    a.asset_name,
    o.quantity,
    o.filled_quantity,
    (o.quantity - o.filled_quantity)        AS remaining_quantity,
    o.limit_price,
    o.order_status,
    CONCAT(t.first_name, ' ', t.last_name)  AS trader_full_name
FROM orders o
JOIN assets  a ON a.asset_id  = o.asset_id
JOIN traders t ON t.trader_id = o.trader_id
WHERE o.order_status IN ('PENDING', 'PARTIALLY_FILLED');


-- ------------------------------------------------------------
-- VIEW: vw_daily_settlements
-- Purpose: Today's settlement processing queue for the T+2
-- settlement operations team.
-- Filter: settlement_date = CURRENT_DATE only.
-- Joins: settlements → orders → assets → traders
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_daily_settlements AS
SELECT
    s.settlement_id,
    s.order_id,
    a.ticker_symbol,
    s.quantity,
    s.trade_price,
    s.gross_amount,
    s.commission,
    s.net_amount,
    s.settlement_date,
    s.settlement_status,
    CONCAT(t.first_name, ' ', t.last_name)  AS trader_full_name
FROM settlements s
JOIN orders  o ON o.order_id  = s.order_id
JOIN assets  a ON a.asset_id  = o.asset_id
JOIN traders t ON t.trader_id = o.trader_id
WHERE s.settlement_date = CURRENT_DATE;


-- ------------------------------------------------------------
-- VIEW: vw_trader_account_summary
-- Purpose: Per-trader account overview for account management
-- and risk monitoring. Aggregates portfolio count, open order
-- count, and total portfolio market value per trader.
-- Main join: traders LEFT JOIN portfolios
-- Correlated subqueries for open_orders_count and
-- total_portfolio_value avoid count inflation from multi-join.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_trader_account_summary AS
SELECT
    t.trader_id,
    CONCAT(t.first_name, ' ', t.last_name)  AS trader_full_name,
    t.email,
    t.trader_type,
    t.trader_status,
    COUNT(DISTINCT p.portfolio_id)           AS portfolio_count,
    (
        SELECT COUNT(*)
        FROM   orders o
        WHERE  o.trader_id    = t.trader_id
          AND  o.order_status IN ('PENDING', 'PARTIALLY_FILLED')
    )                                        AS open_orders_count,
    (
        SELECT COALESCE(SUM(pos.current_value), 0)
        FROM   portfolios p2
        JOIN   positions  pos ON pos.portfolio_id = p2.portfolio_id
        WHERE  p2.trader_id = t.trader_id
    )                                        AS total_portfolio_value
FROM  traders    t
LEFT  JOIN portfolios p ON p.trader_id = t.trader_id
GROUP BY t.trader_id, trader_full_name, t.email, t.trader_type, t.trader_status;
