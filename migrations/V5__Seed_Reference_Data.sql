-- ============================================================
-- Flyway Migration: V5__Seed_Reference_Data.sql
-- Description:     Minimal reference data for development and demo
--                  This is NOT the volume test data (see data_generation/).
--                  This file seeds just enough rows to demonstrate the
--                  application and take screenshots.
-- Depends on:      V1, V2, V3, V4
-- Author:          system
-- Date:            2026-03-09
-- ============================================================

USE capital_markets_db;

SET FOREIGN_KEY_CHECKS = 0;


-- ============================================================
-- SECTION 1: TRADERS
-- 5 traders: 2 INDIVIDUAL, 3 INSTITUTIONAL.
-- registration_date values are historical (2020-2022) so they
-- satisfy CHECK (registration_date <= CAST(created_at AS DATE))
-- when created_at defaults to NOW().
-- ============================================================

INSERT INTO traders
    (first_name, last_name, email, trader_type, trader_status, registration_date)
VALUES
    ('James',   'Harrison', 'james.harrison@trademail.com', 'INDIVIDUAL',   'ACTIVE', '2022-01-15'),
    ('Sarah',   'Chen',     'sarah.chen@trademail.com',     'INDIVIDUAL',   'ACTIVE', '2022-03-10'),
    ('Marcus',  'Thornton', 'm.thornton@blackrockcap.com',  'INSTITUTIONAL','ACTIVE', '2021-06-20'),
    ('Priya',   'Sharma',   'p.sharma@vanguardasset.com',   'INSTITUTIONAL','ACTIVE', '2021-09-05'),
    ('Robert',  'Kimura',   'r.kimura@goldmanprop.com',     'INSTITUTIONAL','ACTIVE', '2020-12-01');


-- ============================================================
-- SECTION 2: ASSETS
-- 10 instruments: 8 STOCK, 2 ETF.
-- Prices reflect approximate market values at time of authoring.
-- All denominated in USD. is_active defaults to 1.
-- ============================================================

INSERT INTO assets
    (ticker_symbol, asset_name, asset_type, exchange, currency, current_price)
VALUES
    ('AAPL',  'Apple Inc.',                    'STOCK', 'NASDAQ', 'USD',  178.5000),
    ('GOOGL', 'Alphabet Inc. Class A',          'STOCK', 'NASDAQ', 'USD',  141.2000),
    ('MSFT',  'Microsoft Corporation',          'STOCK', 'NASDAQ', 'USD',  415.8000),
    ('TSLA',  'Tesla Inc.',                     'STOCK', 'NASDAQ', 'USD',  248.6000),
    ('AMZN',  'Amazon.com Inc.',                'STOCK', 'NASDAQ', 'USD',  185.4000),
    ('JPM',   'JPMorgan Chase & Co.',           'STOCK', 'NYSE',   'USD',  198.7000),
    ('GS',    'Goldman Sachs Group Inc.',       'STOCK', 'NYSE',   'USD',  512.3000),
    ('SPY',   'SPDR S&P 500 ETF Trust',         'ETF',   'NYSE',   'USD',  502.1000),
    ('QQQ',   'Invesco QQQ Trust Series 1',     'ETF',   'NASDAQ', 'USD',  438.2000),
    ('NVDA',  'NVIDIA Corporation',             'STOCK', 'NASDAQ', 'USD',  875.9000);


-- ============================================================
-- SECTION 3: PORTFOLIOS
-- 3 portfolios spread across 2 traders.
-- trader_id=1 (James Harrison): 2 portfolios.
-- trader_id=2 (Sarah Chen):     1 portfolio.
-- ============================================================

INSERT INTO portfolios
    (trader_id, portfolio_name, description)
VALUES
    (1, 'Growth Portfolio', 'Long-term equity growth strategy focused on large-cap technology'),
    (1, 'Income Portfolio',  'Dividend income and broad-market ETF holdings'),
    (2, 'Tech Holdings',     'Concentrated technology sector positions');


-- ============================================================
-- SECTION 4: ORDERS
-- 5 orders demonstrating all lifecycle states:
--   order_id=1  FILLED  BUY  MARKET — AAPL  100 shares @ 178.50
--   order_id=2  FILLED  BUY  LIMIT  — NVDA   50 shares @ 875.90
--   order_id=3  FILLED  SELL MARKET — MSFT   25 shares @ 415.80
--   order_id=4  PENDING BUY  LIMIT  — SPY    10 shares (limit $500.00)
--   order_id=5  CANCELLED    LIMIT  — GOOGL  30 shares (limit $140.00)
--
-- asset_id mapping (from AUTO_INCREMENT above):
--   1=AAPL  2=GOOGL  3=MSFT  4=TSLA  5=AMZN
--   6=JPM   7=GS     8=SPY   9=QQQ  10=NVDA
-- ============================================================

INSERT INTO orders
    (trader_id, asset_id, portfolio_id,
     order_type, order_side, quantity, limit_price,
     filled_quantity, average_fill_price, order_status,
     cancelled_at, cancel_reason)
VALUES
    -- Filled market BUY: James Harrison buys 100 AAPL at market
    (1, 1, 1, 'MARKET', 'BUY',  100, NULL,     100, 178.5000, 'FILLED',    NULL,                    NULL),
    -- Filled limit BUY: Sarah Chen buys 50 NVDA with limit $880
    (2, 10, 3, 'LIMIT', 'BUY',   50, 880.0000,  50, 875.9000, 'FILLED',    NULL,                    NULL),
    -- Filled market SELL: James Harrison sells 25 MSFT at market
    (1, 3, 1, 'MARKET', 'SELL',  25, NULL,       25, 415.8000, 'FILLED',    NULL,                    NULL),
    -- Pending limit BUY: James Harrison bids $500 for 100 SPY (not yet filled)
    (1, 8, 2, 'LIMIT',  'BUY',  100, 500.0000,   0,  NULL,     'PENDING',   NULL,                    NULL),
    -- Cancelled limit BUY: Sarah Chen's GOOGL order cancelled end-of-session
    (2, 2, 3, 'LIMIT',  'BUY',   30, 140.0000,   0,  NULL,     'CANCELLED', '2026-03-07 14:22:00',  'Limit price not reached within session');


-- ============================================================
-- SECTION 5: SETTLEMENTS
-- 2 settlements for the 2 FILLED BUY orders.
-- Financials verified:
--   Order 1 (AAPL):  gross = 178.50 × 100 = 17850.0000
--                    net   = 17850.0000 + 9.9900 = 17859.9900
--   Order 2 (NVDA):  gross = 875.90 ×  50 = 43795.0000
--                    net   = 43795.0000 + 9.9900 = 43804.9900
-- settlement_date = T+2 from order submission (2026-03-09 + 2 = 2026-03-11).
-- ============================================================

INSERT INTO settlements
    (order_id, trade_price, quantity, gross_amount, commission, net_amount,
     settlement_date, settlement_status)
VALUES
    -- Settlement for AAPL BUY (order_id=1)
    (1, 178.5000, 100, 17850.0000, 9.9900, 17859.9900, '2026-03-11', 'SETTLED'),
    -- Settlement for NVDA BUY (order_id=2)
    (2, 875.9000,  50, 43795.0000, 9.9900, 43804.9900, '2026-03-11', 'SETTLED');


-- ============================================================
-- SECTION 6: ACCOUNTING LEDGER
-- 4 rows forming 2 double-entry pairs, one pair per settled order.
-- Each pair uses a SETTLEMENT_PAYABLE clearing account:
--   Row A: EQUITY_HOLDINGS   dr / SETTLEMENT_PAYABLE cr  — asset acquired
--   Row B: SETTLEMENT_PAYABLE dr / CASH_ACCOUNT       cr  — cash settled
-- Both rows in a pair carry identical amounts (the net settlement value).
-- Constraint checks: amount > 0 ✓, debit_account <> credit_account ✓.
-- reference_type='ORDER', reference_id = the originating order_id.
-- ============================================================

INSERT INTO accounting_ledgers
    (debit_account, credit_account, amount, reference_type, reference_id, description)
VALUES
    -- Pair 1 — AAPL BUY (order_id=1, net=17859.9900)
    ('EQUITY_HOLDINGS',   'SETTLEMENT_PAYABLE', 17859.9900, 'ORDER', 1,
     'AAPL 100 shares acquired — asset leg'),
    ('SETTLEMENT_PAYABLE','CASH_ACCOUNT',        17859.9900, 'ORDER', 1,
     'AAPL 100 shares — cash settlement cleared'),

    -- Pair 2 — NVDA BUY (order_id=2, net=43804.9900)
    ('EQUITY_HOLDINGS',   'SETTLEMENT_PAYABLE', 43804.9900, 'ORDER', 2,
     'NVDA 50 shares acquired — asset leg'),
    ('SETTLEMENT_PAYABLE','CASH_ACCOUNT',        43804.9900, 'ORDER', 2,
     'NVDA 50 shares — cash settlement cleared');


SET FOREIGN_KEY_CHECKS = 1;
