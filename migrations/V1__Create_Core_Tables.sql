-- ============================================================
-- Flyway Migration: V1__Create_Core_Tables.sql
-- Description:     Create all core trading platform tables
-- Tables created:  traders, assets, portfolios, orders,
--                  positions, accounting_ledgers, settlements
-- Author:          system
-- Date:            2026-03-09
-- Notes:           All monetary values use DECIMAL(15,4).
--                  NEVER use FLOAT or DOUBLE for money.
--                  Indexes and views are in V2.
--                  Stored procedures are in V3.
--                  Audit triggers are in V4.
-- ============================================================


-- ============================================================
-- SECTION 1: DATABASE CREATION
-- ============================================================

DROP DATABASE IF EXISTS capital_markets_db;

CREATE DATABASE capital_markets_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE capital_markets_db;


-- ============================================================
-- SECTION 2: DROP TABLES (reverse dependency order)
-- Safe to re-run on a clean rebuild.
-- ============================================================

DROP TABLE IF EXISTS settlements;
DROP TABLE IF EXISTS accounting_ledgers;
DROP TABLE IF EXISTS positions;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS portfolios;
DROP TABLE IF EXISTS assets;
DROP TABLE IF EXISTS traders;


-- ============================================================
-- SECTION 3: CREATE TABLES (forward dependency order)
-- traders → assets → portfolios → orders → positions
--         → accounting_ledgers → settlements
-- ============================================================


-- ------------------------------------------------------------
-- TABLE: traders
-- ------------------------------------------------------------
CREATE TABLE traders (
    trader_id         BIGINT                               NOT NULL AUTO_INCREMENT
                      COMMENT 'Surrogate primary key',
    first_name        VARCHAR(50)                          NOT NULL
                      COMMENT 'Trader given name',
    last_name         VARCHAR(50)                          NOT NULL
                      COMMENT 'Trader family name',
    email             VARCHAR(100)                         NOT NULL
                      COMMENT 'Unique contact email address used for login and notifications',
    phone             VARCHAR(20)                          NULL
                      COMMENT 'Optional contact phone number including country code',
    trader_type       ENUM('INDIVIDUAL','INSTITUTIONAL')   NOT NULL
                      COMMENT 'Classification of trader account: retail individual or institutional firm',
    trader_status     ENUM('ACTIVE','SUSPENDED','CLOSED')  NOT NULL DEFAULT 'ACTIVE'
                      COMMENT 'Current lifecycle status of the trader account',
    registration_date DATE                                 NOT NULL DEFAULT (CURRENT_DATE)
                      COMMENT 'Calendar date on which the trader account was registered',
    created_at        DATETIME                             NOT NULL DEFAULT CURRENT_TIMESTAMP
                      COMMENT 'Record creation timestamp',
    updated_at        DATETIME                             NOT NULL DEFAULT CURRENT_TIMESTAMP
                      ON UPDATE CURRENT_TIMESTAMP
                      COMMENT 'Record last modification timestamp',

    PRIMARY KEY (trader_id),
    UNIQUE KEY uq_traders_email (email),
    CONSTRAINT chk_traders_reg_date
        CHECK (registration_date <= CAST(created_at AS DATE))

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Registered traders who can place orders on the platform';


-- ------------------------------------------------------------
-- TABLE: assets
-- ------------------------------------------------------------
CREATE TABLE assets (
    asset_id      BIGINT                                    NOT NULL AUTO_INCREMENT
                  COMMENT 'Surrogate primary key',
    ticker_symbol VARCHAR(10)                               NOT NULL
                  COMMENT 'Exchange ticker symbol uniquely identifying the instrument (e.g. AAPL, BRK.B)',
    asset_name    VARCHAR(150)                              NOT NULL
                  COMMENT 'Full descriptive name of the financial instrument',
    asset_type    ENUM('STOCK','BOND','ETF','DERIVATIVE')   NOT NULL
                  COMMENT 'Classification of the financial instrument category',
    exchange      VARCHAR(50)                               NOT NULL
                  COMMENT 'Primary exchange where the asset is listed (e.g. NYSE, NASDAQ, LSE)',
    currency      VARCHAR(3)                                NOT NULL DEFAULT 'USD'
                  COMMENT 'ISO 4217 three-letter currency code for the asset denomination',
    current_price DECIMAL(15,4)                             NOT NULL DEFAULT 0.0000
                  COMMENT 'Most recent market price per share or unit; refreshed by price feed',
    is_active     TINYINT(1)                                NOT NULL DEFAULT 1
                  COMMENT '1 = tradeable on the platform; 0 = delisted or suspended from trading',
    created_at    DATETIME                                  NOT NULL DEFAULT CURRENT_TIMESTAMP
                  COMMENT 'Record creation timestamp',
    updated_at    DATETIME                                  NOT NULL DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP
                  COMMENT 'Record last modification timestamp',

    PRIMARY KEY (asset_id),
    UNIQUE KEY uq_assets_ticker (ticker_symbol),
    CONSTRAINT chk_assets_price    CHECK (current_price >= 0),
    CONSTRAINT chk_assets_currency CHECK (CHAR_LENGTH(currency) = 3)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Financial instruments available for trading on the platform';


-- ------------------------------------------------------------
-- TABLE: portfolios
-- ------------------------------------------------------------
CREATE TABLE portfolios (
    portfolio_id   BIGINT       NOT NULL AUTO_INCREMENT
                   COMMENT 'Surrogate primary key',
    trader_id      BIGINT       NOT NULL
                   COMMENT 'FK: the trader who owns this portfolio',
    portfolio_name VARCHAR(100) NOT NULL
                   COMMENT 'User-defined portfolio label; unique per trader but not globally',
    description    TEXT         NULL
                   COMMENT 'Optional free-text notes describing the portfolio strategy or purpose',
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                   COMMENT 'Record creation timestamp',
    updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                   ON UPDATE CURRENT_TIMESTAMP
                   COMMENT 'Record last modification timestamp',

    PRIMARY KEY (portfolio_id),
    UNIQUE KEY uq_portfolios_trader_name (trader_id, portfolio_name),
    CONSTRAINT fk_portfolios_trader
        FOREIGN KEY (trader_id) REFERENCES traders (trader_id)
        ON DELETE RESTRICT ON UPDATE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Named groupings of positions belonging to a single trader';


-- ------------------------------------------------------------
-- TABLE: orders
-- ------------------------------------------------------------
CREATE TABLE orders (
    order_id            BIGINT                                                                NOT NULL AUTO_INCREMENT
                        COMMENT 'Surrogate primary key',
    trader_id           BIGINT                                                                NOT NULL
                        COMMENT 'FK: trader who placed the order; denormalised from portfolio for query performance',
    asset_id            BIGINT                                                                NOT NULL
                        COMMENT 'FK: financial instrument being bought or sold',
    portfolio_id        BIGINT                                                                NOT NULL
                        COMMENT 'FK: portfolio to which this order and resulting position belong',
    order_type          ENUM('MARKET','LIMIT','STOP','STOP_LIMIT')                            NOT NULL
                        COMMENT 'Execution mechanism: MARKET fills at best available price; LIMIT at a specified price or better',
    order_side          ENUM('BUY','SELL')                                                    NOT NULL
                        COMMENT 'Direction of the trade: BUY acquires shares, SELL disposes of them',
    quantity            INT                                                                   NOT NULL
                        COMMENT 'Number of shares or units requested by the trader',
    limit_price         DECIMAL(15,4)                                                         NULL
                        COMMENT 'Maximum acceptable price for BUY or minimum for SELL; NULL for MARKET orders',
    filled_quantity     INT                                                                   NOT NULL DEFAULT 0
                        COMMENT 'Cumulative number of shares executed so far; 0 until the first partial fill',
    average_fill_price  DECIMAL(15,4)                                                         NULL
                        COMMENT 'Volume-weighted average execution price across all fills; NULL until first fill',
    order_status        ENUM('PENDING','PARTIALLY_FILLED','FILLED','CANCELLED','REJECTED')    NOT NULL DEFAULT 'PENDING'
                        COMMENT 'Current lifecycle state of the order',
    order_time          DATETIME(6)                                                           NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                        COMMENT 'Microsecond-precision timestamp when the order was submitted to the platform',
    cancelled_at        DATETIME                                                              NULL
                        COMMENT 'Timestamp when the order was cancelled; NULL if the order was never cancelled',
    cancel_reason       VARCHAR(255)                                                          NULL
                        COMMENT 'Human-readable explanation for cancellation; NULL if the order was not cancelled',
    created_at          DATETIME                                                              NOT NULL DEFAULT CURRENT_TIMESTAMP
                        COMMENT 'Record creation timestamp',
    updated_at          DATETIME                                                              NOT NULL DEFAULT CURRENT_TIMESTAMP
                        ON UPDATE CURRENT_TIMESTAMP
                        COMMENT 'Record last modification timestamp',

    PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_trader
        FOREIGN KEY (trader_id)    REFERENCES traders    (trader_id)    ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_orders_asset
        FOREIGN KEY (asset_id)     REFERENCES assets     (asset_id)     ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_orders_portfolio
        FOREIGN KEY (portfolio_id) REFERENCES portfolios (portfolio_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_orders_quantity
        CHECK (quantity > 0),
    CONSTRAINT chk_orders_limit_price
        CHECK (limit_price IS NULL OR limit_price > 0),
    CONSTRAINT chk_orders_filled
        CHECK (filled_quantity >= 0 AND filled_quantity <= quantity)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Buy and sell instructions submitted by traders; the central transaction entity of the platform';


-- ------------------------------------------------------------
-- TABLE: positions
-- ------------------------------------------------------------
CREATE TABLE positions (
    position_id    BIGINT        NOT NULL AUTO_INCREMENT
                   COMMENT 'Surrogate primary key',
    portfolio_id   BIGINT        NOT NULL
                   COMMENT 'FK: portfolio that holds this position',
    asset_id       BIGINT        NOT NULL
                   COMMENT 'FK: financial instrument held in this position',
    quantity       INT           NOT NULL DEFAULT 0
                   COMMENT 'Current net share count; zero if the position was fully liquidated but record retained',
    average_cost   DECIMAL(15,4) NOT NULL DEFAULT 0.0000
                   COMMENT 'FIFO average cost per share across all purchases in this position',
    current_value  DECIMAL(15,4) NOT NULL DEFAULT 0.0000
                   COMMENT 'Denormalised: quantity × assets.current_price; refreshed by stored procedure on price or fill events',
    unrealized_pnl DECIMAL(15,4) NOT NULL DEFAULT 0.0000
                   COMMENT 'Denormalised: current_value − (quantity × average_cost); refreshed by stored procedure',
    created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                   COMMENT 'Record creation timestamp',
    updated_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                   ON UPDATE CURRENT_TIMESTAMP
                   COMMENT 'Record last modification timestamp',

    PRIMARY KEY (position_id),
    UNIQUE KEY uq_positions_portfolio_asset (portfolio_id, asset_id),
    CONSTRAINT fk_positions_portfolio
        FOREIGN KEY (portfolio_id) REFERENCES portfolios (portfolio_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_positions_asset
        FOREIGN KEY (asset_id)     REFERENCES assets     (asset_id)     ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_positions_quantity
        CHECK (quantity >= 0),
    CONSTRAINT chk_positions_avg_cost
        CHECK (average_cost >= 0)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Current holdings of a financial instrument within a portfolio';


-- ------------------------------------------------------------
-- TABLE: accounting_ledgers
-- APPEND-ONLY: no UPDATE or DELETE is permitted on this table.
-- Every financial event produces exactly one debit row and one
-- credit row. The pair for a given (reference_type, reference_id)
-- must net to zero (equal amounts, opposite sides).
-- ------------------------------------------------------------
CREATE TABLE accounting_ledgers (
    ledger_id        BIGINT                                     NOT NULL AUTO_INCREMENT
                     COMMENT 'Surrogate primary key',
    transaction_date DATETIME(6)                                NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                     COMMENT 'Microsecond-precision timestamp of the financial event',
    debit_account    VARCHAR(50)                                NOT NULL
                     COMMENT 'Chart-of-accounts code for the account being debited',
    credit_account   VARCHAR(50)                                NOT NULL
                     COMMENT 'Chart-of-accounts code for the account being credited',
    amount           DECIMAL(15,4)                              NOT NULL
                     COMMENT 'Absolute transaction amount; always positive — direction determined by debit/credit accounts',
    reference_type   ENUM('ORDER','SETTLEMENT','ADJUSTMENT')    NOT NULL
                     COMMENT 'Type of business event that generated this ledger entry',
    reference_id     BIGINT                                     NOT NULL
                     COMMENT 'FK-like reference to orders.order_id or settlements.settlement_id depending on reference_type',
    description      VARCHAR(255)                               NULL
                     COMMENT 'Optional human-readable explanation of the ledger entry',
    created_at       DATETIME                                   NOT NULL DEFAULT CURRENT_TIMESTAMP
                     COMMENT 'Record creation timestamp',
    updated_at       DATETIME                                   NOT NULL DEFAULT CURRENT_TIMESTAMP
                     ON UPDATE CURRENT_TIMESTAMP
                     COMMENT 'Record last modification timestamp',

    PRIMARY KEY (ledger_id),
    CONSTRAINT chk_ledger_amount   CHECK (amount > 0),
    CONSTRAINT chk_ledger_accounts CHECK (debit_account <> credit_account)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Append-only double-entry accounting ledger. Every financial event creates exactly one debit row and one credit row. No UPDATE or DELETE permitted.';


-- ------------------------------------------------------------
-- TABLE: settlements
-- ------------------------------------------------------------
CREATE TABLE settlements (
    settlement_id     BIGINT                                         NOT NULL AUTO_INCREMENT
                      COMMENT 'Surrogate primary key',
    order_id          BIGINT                                         NOT NULL
                      COMMENT 'FK: the filled order this settlement relates to; UNIQUE enforces 1:1 cardinality with orders',
    trade_price       DECIMAL(15,4)                                  NOT NULL
                      COMMENT 'Actual execution price per share at which the order was filled',
    quantity          INT                                            NOT NULL
                      COMMENT 'Number of shares settled in this record',
    gross_amount      DECIMAL(15,4)                                  NOT NULL
                      COMMENT 'trade_price × quantity before commission deduction',
    commission        DECIMAL(15,4)                                  NOT NULL DEFAULT 9.9900
                      COMMENT 'Flat broker commission charged per trade',
    net_amount        DECIMAL(15,4)                                  NOT NULL
                      COMMENT 'For BUY: gross_amount + commission. For SELL: gross_amount − commission.',
    settlement_date   DATE                                           NOT NULL
                      COMMENT 'T+2 business days after the trade date; the date funds and shares legally transfer',
    settlement_status ENUM('PENDING','SETTLED','FAILED','REVERSED')  NOT NULL DEFAULT 'PENDING'
                      COMMENT 'Current state of the settlement lifecycle',
    created_at        DATETIME                                       NOT NULL DEFAULT CURRENT_TIMESTAMP
                      COMMENT 'Record creation timestamp',
    updated_at        DATETIME                                       NOT NULL DEFAULT CURRENT_TIMESTAMP
                      ON UPDATE CURRENT_TIMESTAMP
                      COMMENT 'Record last modification timestamp',

    PRIMARY KEY (settlement_id),
    UNIQUE KEY uq_settlements_order (order_id),
    CONSTRAINT fk_settlements_order
        FOREIGN KEY (order_id) REFERENCES orders (order_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_settlement_trade_price CHECK (trade_price > 0),
    CONSTRAINT chk_settlement_quantity    CHECK (quantity > 0),
    CONSTRAINT chk_settlement_gross       CHECK (gross_amount > 0),
    CONSTRAINT chk_settlement_commission  CHECK (commission >= 0)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Settlement records for fully executed orders. One settlement per order (enforced by UNIQUE on order_id). Retains gross_amount and net_amount for reporting compatibility.';
