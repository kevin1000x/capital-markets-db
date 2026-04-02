# Stage 4: Logical Design — Capital Markets Trading Platform

---

## 4.1 Table Specifications

---

### Table: traders

**Purpose**: Stores registered traders and their classification, serving as the root entity to which all portfolios and orders are attributed.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| trader_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique trader identifier |
| first_name | VARCHAR(50) | NOT NULL | — | — | Trader's legal given name |
| last_name | VARCHAR(50) | NOT NULL | — | — | Trader's legal family name |
| email | VARCHAR(100) | NOT NULL | — | UNIQUE | Contact and login email address; globally unique across all traders |
| phone | VARCHAR(20) | NULL | NULL | — | Optional contact phone number |
| trader_type | ENUM('INDIVIDUAL','INSTITUTIONAL') | NOT NULL | — | — | Classifies the trader as a retail individual or institutional desk |
| trader_status | ENUM('ACTIVE','SUSPENDED','CLOSED') | NOT NULL | 'ACTIVE' | DEFAULT | Lifecycle state; ACTIVE permits order placement; SUSPENDED and CLOSED do not |
| registration_date | DATE | NOT NULL | — | — | Calendar date when the trader account was formally registered |
| created_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP | DEFAULT | Row creation timestamp; set once at INSERT |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Last modification timestamp; auto-maintained by MySQL |

**Primary Key**: trader_id

**Foreign Keys**: none

**Unique Constraints**:
- UNIQUE (email) — enforces one account per email address; also supports O(1) login lookups

**Check Constraints**:
- CHECK (registration_date <= CAST(created_at AS DATE)) — registration date cannot be in the future relative to row creation

**Indexes** (as implemented in V2):
- idx_traders_email ON (email) — covered by UNIQUE constraint; supports login and deduplication lookups

---

### Table: assets

**Purpose**: Catalogues all tradeable financial instruments available on the platform, including current market price and active status.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| asset_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique asset identifier |
| ticker_symbol | VARCHAR(10) | NOT NULL | — | UNIQUE | Exchange ticker (e.g., AAPL, MSFT); globally unique across all exchanges on this platform |
| asset_name | VARCHAR(150) | NOT NULL | — | — | Full descriptive name of the instrument |
| asset_type | ENUM('STOCK','BOND','ETF','DERIVATIVE') | NOT NULL | — | — | Instrument class; drives applicable business rules and margin requirements |
| exchange | VARCHAR(50) | NOT NULL | — | — | Listing exchange name (e.g., NYSE, NASDAQ); stored as VARCHAR per platform convention |
| currency | VARCHAR(3) | NOT NULL | — | CHECK (CHAR_LENGTH(currency) = 3) | ISO 4217 three-letter currency code (e.g., USD, EUR, GBP) |
| current_price | DECIMAL(15,4) | NOT NULL | — | CHECK (current_price >= 0) | Latest known market price; updated by market data feed; zero is permitted for halted instruments |
| is_active | TINYINT(1) | NOT NULL | 1 | DEFAULT | Soft-delete flag; 0 indicates a delisted or deactivated instrument |
| created_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP | DEFAULT | Row creation timestamp |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Last modification timestamp; auto-maintained by MySQL |

**Primary Key**: asset_id

**Foreign Keys**: none

**Unique Constraints**:
- UNIQUE (ticker_symbol) — one canonical row per listed instrument symbol

**Check Constraints**:
- CHECK (current_price >= 0) — price may be zero for suspended instruments but never negative
- CHECK (CHAR_LENGTH(currency) = 3) — enforces ISO 4217 three-letter code format

**Indexes** (as implemented in V2):
- idx_assets_ticker ON (ticker_symbol) — covered by UNIQUE constraint; primary lookup path for order entry

---

### Table: portfolios

**Purpose**: Groups positions and orders under named investment mandates belonging to a single trader.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| portfolio_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique portfolio identifier |
| trader_id | BIGINT | NOT NULL | — | FK | Owning trader; references traders(trader_id) |
| portfolio_name | VARCHAR(100) | NOT NULL | — | — | Human-readable portfolio label; unique within a trader's account |
| description | TEXT | NULL | NULL | — | Optional free-text description of the portfolio's investment mandate |
| created_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP | DEFAULT | Row creation timestamp |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Last modification timestamp; auto-maintained by MySQL |

**Primary Key**: portfolio_id

**Foreign Keys**:
- trader_id → traders(trader_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**:
- UNIQUE (trader_id, portfolio_name) — a single trader may not hold two portfolios with the same name

**Check Constraints**: none

**Indexes needed** (beyond PK and FK auto-indexes):
- idx_portfolios_trader ON (trader_id) — covered by FK auto-index; supports trader→portfolios join
- idx_portfolios_trader_name ON (trader_id, portfolio_name) — backing index for UNIQUE constraint; accelerates name-based portfolio lookup

---

### Table: orders

**Purpose**: Records every buy and sell instruction submitted to the platform, capturing intent, execution progress, cancellation metadata, and routing to a specific portfolio.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| order_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique order identifier |
| trader_id | BIGINT | NOT NULL | — | FK | Submitting trader; denormalised from portfolios.trader_id for direct audit and trader-level queries (see Design Decisions §4.3) |
| asset_id | BIGINT | NOT NULL | — | FK | Instrument being bought or sold; references assets(asset_id) |
| portfolio_id | BIGINT | NOT NULL | — | FK | Target portfolio for position update upon execution; references portfolios(portfolio_id) |
| order_type | ENUM('MARKET','LIMIT','STOP','STOP_LIMIT') | NOT NULL | — | — | Execution instruction type; determines price matching rules at the exchange |
| order_side | ENUM('BUY','SELL') | NOT NULL | — | — | Trade direction |
| quantity | INT | NOT NULL | — | CHECK (quantity > 0) | Number of whole shares ordered; must be a positive integer |
| limit_price | DECIMAL(15,4) | NULL | NULL | CHECK (limit_price IS NULL OR limit_price > 0) | Maximum (BUY) or minimum (SELL) acceptable price; NULL for MARKET orders |
| filled_quantity | INT | NOT NULL | 0 | DEFAULT, CHECK (filled_quantity >= 0) | Cumulative shares matched against the order book; starts at zero on submission |
| average_fill_price | DECIMAL(15,4) | NULL | NULL | — | Volume-weighted average price across all partial fills; NULL until first fill |
| order_status | ENUM('PENDING','PARTIALLY_FILLED','FILLED','CANCELLED','REJECTED') | NOT NULL | 'PENDING' | DEFAULT | Current lifecycle state; transitions are one-directional |
| order_time | DATETIME(6) | NOT NULL | CURRENT_TIMESTAMP(6) | DEFAULT | Microsecond-precision submission timestamp; required for exchange sequencing and regulatory reporting |
| cancelled_at | DATETIME | NULL | NULL | — | Timestamp when the order was cancelled or rejected; NULL for non-terminal states |
| cancel_reason | VARCHAR(255) | NULL | NULL | — | Human-readable or system-generated reason for cancellation or rejection |
| created_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP | DEFAULT | Row creation timestamp |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Last modification timestamp; auto-maintained by MySQL |

**Primary Key**: order_id

**Foreign Keys**:
- trader_id → traders(trader_id) ON DELETE RESTRICT ON UPDATE CASCADE
- asset_id → assets(asset_id) ON DELETE RESTRICT ON UPDATE CASCADE
- portfolio_id → portfolios(portfolio_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**: none

**Check Constraints**:
- CHECK (quantity > 0) — at least one share must be ordered
- CHECK (filled_quantity >= 0) — cumulative fills cannot be negative
- CHECK (filled_quantity <= quantity) — fills cannot exceed the original order size
- CHECK (limit_price IS NULL OR limit_price > 0) — limit price, when specified, must be positive

**Indexes** (as implemented in V2):
- idx_orders_trader_date ON (trader_id, order_time) — supports "show all orders for trader X sorted by time"
- idx_orders_asset ON (asset_id) — supports order book aggregation per instrument
- idx_orders_status ON (order_status) — supports "find all PENDING orders" for matching engine
- idx_orders_portfolio ON (portfolio_id) — covered by FK auto-index; supports portfolio-level order history

---

### Table: positions

**Purpose**: Maintains the current held quantity and cost basis for each asset within each portfolio, with denormalised market-value columns updated in real time on each fill.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| position_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique position identifier |
| portfolio_id | BIGINT | NOT NULL | — | FK | Owning portfolio; references portfolios(portfolio_id) |
| asset_id | BIGINT | NOT NULL | — | FK | Held instrument; references assets(asset_id) |
| quantity | INT | NOT NULL | — | CHECK (quantity >= 0) | Current whole-share holding; zero indicates a flat (closed) position |
| average_cost | DECIMAL(15,4) | NOT NULL | — | CHECK (average_cost >= 0) | Weighted-average cost per share across all fills; updated via stored procedure on each execution |
| current_value | DECIMAL(15,4) | NOT NULL | 0.0000 | DEFAULT | Market value of the position (quantity × assets.current_price); intentionally denormalised — see Design Decisions §4.3 |
| unrealized_pnl | DECIMAL(15,4) | NOT NULL | 0.0000 | DEFAULT | Unrealised profit or loss (current_value − quantity × average_cost); intentionally denormalised — see Design Decisions §4.3 |
| created_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP | DEFAULT | Row creation timestamp |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Last modification timestamp; auto-maintained by MySQL |

**Primary Key**: position_id

**Foreign Keys**:
- portfolio_id → portfolios(portfolio_id) ON DELETE RESTRICT ON UPDATE CASCADE
- asset_id → assets(asset_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**:
- UNIQUE (portfolio_id, asset_id) — one position row per asset per portfolio; fills are aggregated into this single row rather than stored as individual fill records

**Check Constraints**:
- CHECK (quantity >= 0) — cannot hold a negative number of shares (short selling is out of scope for this version)
- CHECK (average_cost >= 0) — cost basis cannot be negative

**Indexes needed** (beyond PK and FK auto-indexes):
- idx_positions_portfolio_asset ON (portfolio_id, asset_id) — covered by UNIQUE constraint; primary path for position lookup during order execution
- idx_positions_asset ON (asset_id) — supports cross-portfolio holdings queries for a single instrument (e.g., price-impact analysis, risk aggregation)

---

### Table: accounting_ledgers

**Purpose**: Records every double-entry journal posting generated by order fills, settlements, and manual adjustments, providing a tamper-evident financial audit trail.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| ledger_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique ledger entry identifier |
| transaction_date | DATETIME(6) | NOT NULL | — | — | Microsecond-precision timestamp of the financial event; DATETIME(6) chosen to correlate with order_time for same-millisecond events |
| debit_account | VARCHAR(50) | NOT NULL | — | — | Chart-of-accounts code for the account being debited |
| credit_account | VARCHAR(50) | NOT NULL | — | — | Chart-of-accounts code for the account being credited |
| amount | DECIMAL(15,4) | NOT NULL | — | CHECK (amount > 0) | Absolute monetary amount of the posting; always positive — debit/credit direction is encoded in account codes |
| reference_type | ENUM('ORDER','SETTLEMENT','ADJUSTMENT') | NOT NULL | — | — | Identifies the domain entity that triggered this posting (polymorphic discriminator column) |
| reference_id | BIGINT | NOT NULL | — | — | Primary key of the triggering entity in its respective table; no DB-level FK declared — see ER-to-Relational Mapping §4.2 |
| description | VARCHAR(255) | NULL | NULL | — | Optional human-readable narrative for the posting |
| created_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP | DEFAULT | Row creation timestamp |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Last modification timestamp; auto-maintained by MySQL |

**Primary Key**: ledger_id

**Foreign Keys**: none — the polymorphic `reference_type`/`reference_id` pattern precludes a database-level foreign key constraint; referential integrity is enforced within stored procedure logic (see ER-to-Relational Mapping §4.2)

**Unique Constraints**: none

**Check Constraints**:
- CHECK (amount > 0) — monetary amounts are always positive; debit/credit direction is expressed through account codes, not sign
- CHECK (debit_account <> credit_account) — a double-entry posting cannot debit and credit the same account

**Indexes** (as implemented in V2):
- idx_ledger_date ON (transaction_date) — supports date-range financial reporting and period-close queries
- idx_ledger_reference ON (reference_type, reference_id) — composite index for polymorphic lookups; retrieves all ledger lines associated with a given order or settlement

---

### Table: settlements

**Purpose**: Records the financial and operational outcome of an executed order, capturing the agreed price, quantity, brokerage fees, and T+2 settlement lifecycle status.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| settlement_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique settlement identifier |
| order_id | BIGINT | NOT NULL | — | FK, UNIQUE | Parent order that generated this settlement; UNIQUE constraint enforces the 1:0..1 cardinality between orders and settlements |
| trade_price | DECIMAL(15,4) | NOT NULL | — | CHECK (trade_price > 0) | Actual execution price per share at which the order was filled |
| quantity | INT | NOT NULL | — | CHECK (quantity > 0) | Number of whole shares covered by this settlement record |
| gross_amount | DECIMAL(15,4) | NOT NULL | — | CHECK (gross_amount > 0) | Pre-commission trade value (trade_price × quantity); stored for V5 seed data compatibility and settlement reporting |
| commission | DECIMAL(15,4) | NOT NULL | 0.0000 | DEFAULT, CHECK (commission >= 0) | Brokerage commission charged; zero for commission-free instruments |
| net_amount | DECIMAL(15,4) | NOT NULL | — | — | Post-commission settlement obligation (gross_amount + commission for BUY; gross_amount − commission for SELL); stored for V5 seed data compatibility |
| settlement_date | DATE | NOT NULL | — | — | Target settlement date; typically T+2 business days after execution |
| settlement_status | ENUM('PENDING','SETTLED','FAILED','REVERSED') | NOT NULL | 'PENDING' | DEFAULT | Current state in the settlement lifecycle |
| created_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP | DEFAULT | Row creation timestamp |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Last modification timestamp; auto-maintained by MySQL |

**Primary Key**: settlement_id

**Foreign Keys**:
- order_id → orders(order_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**:
- UNIQUE (order_id) — one settlement record per order at most; enforces the 1:0..1 relationship at the database level without requiring a nullable FK on the orders table

**Check Constraints**:
- CHECK (trade_price > 0) — execution price must be positive
- CHECK (quantity > 0) — settled quantity must be at least one share
- CHECK (gross_amount > 0) — gross trade value must be positive
- CHECK (commission >= 0) — commission cannot be negative

**Indexes needed** (beyond PK and FK auto-indexes):
- idx_settlements_order ON (order_id) — covered by UNIQUE constraint; primary path for settlement lookup by order
- idx_settlements_date ON (settlement_date) — supports T+2 batch settlement processing and date-range queries
- idx_settlements_status ON (settlement_status) — supports monitoring dashboards for PENDING and FAILED settlements

---

### Table: order_history

**Purpose**: INSERT-only audit log populated exclusively by `AFTER UPDATE` and `AFTER DELETE` triggers on the `orders` table; preserves a complete before-image of every row change.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| history_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique history record identifier |
| change_type | ENUM('UPDATE','DELETE') | NOT NULL | — | — | Type of DML operation that triggered this history record |
| changed_at | DATETIME(6) | NOT NULL | CURRENT_TIMESTAMP(6) | DEFAULT | Microsecond-precision timestamp of the triggering DML operation |
| changed_by | VARCHAR(100) | NOT NULL | — | — | Database user or application context that initiated the change (e.g., 'execution_engine', 'db_admin') |
| order_id | BIGINT | NOT NULL | — | FK | Parent order being audited; references orders(order_id) |
| trader_id | BIGINT | NULL | — | — | Mirrored from orders.trader_id at time of change (OLD.*) |
| asset_id | BIGINT | NULL | — | — | Mirrored from orders.asset_id at time of change |
| portfolio_id | BIGINT | NULL | — | — | Mirrored from orders.portfolio_id at time of change |
| order_type | ENUM('MARKET','LIMIT','STOP','STOP_LIMIT') | NULL | — | — | Mirrored from orders.order_type at time of change |
| order_side | ENUM('BUY','SELL') | NULL | — | — | Mirrored from orders.order_side at time of change |
| quantity | INT | NULL | — | — | Mirrored from orders.quantity at time of change |
| limit_price | DECIMAL(15,4) | NULL | — | — | Mirrored from orders.limit_price at time of change |
| filled_quantity | INT | NULL | — | — | Mirrored from orders.filled_quantity at time of change |
| average_fill_price | DECIMAL(15,4) | NULL | — | — | Mirrored from orders.average_fill_price at time of change |
| order_status | ENUM('PENDING','PARTIALLY_FILLED','FILLED','CANCELLED','REJECTED') | NULL | — | — | Mirrored from orders.order_status at time of change |
| order_time | DATETIME(6) | NULL | — | — | Mirrored from orders.order_time at time of change |
| cancelled_at | DATETIME | NULL | — | — | Mirrored from orders.cancelled_at at time of change |
| cancel_reason | VARCHAR(255) | NULL | — | — | Mirrored from orders.cancel_reason at time of change |
| created_at | DATETIME | NULL | — | — | Mirrored from orders.created_at at time of change |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Set by trigger to OLD.updated_at at INSERT; ON UPDATE clause satisfies CLAUDE.md audit requirement but never fires on INSERT-only rows |

**Primary Key**: history_id

**Foreign Keys**:
- order_id → orders(order_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**: none — multiple history records per order are expected and required

**Check Constraints**: none — trigger correctness is validated at the stored procedure level; application code cannot INSERT into history tables

**Indexes needed** (beyond PK and FK auto-indexes):
- idx_order_history_order_id ON (order_id) — retrieves the full audit trail for a specific order in chronological order
- idx_order_history_changed_at ON (changed_at) — supports time-range compliance queries and regulatory reporting

---

### Table: position_history

**Purpose**: INSERT-only audit log populated exclusively by `AFTER UPDATE` and `AFTER DELETE` triggers on the `positions` table; preserves pre-change quantity and cost basis for compliance and dispute resolution.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| history_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique history record identifier |
| change_type | ENUM('UPDATE','DELETE') | NOT NULL | — | — | Type of DML operation that triggered this history record |
| changed_at | DATETIME(6) | NOT NULL | CURRENT_TIMESTAMP(6) | DEFAULT | Microsecond-precision timestamp of the triggering DML operation |
| changed_by | VARCHAR(100) | NOT NULL | — | — | Database user or application context that initiated the change |
| position_id | BIGINT | NOT NULL | — | FK | Parent position being audited; references positions(position_id) |
| portfolio_id | BIGINT | NULL | — | — | Mirrored from positions.portfolio_id at time of change |
| asset_id | BIGINT | NULL | — | — | Mirrored from positions.asset_id at time of change |
| quantity | INT | NULL | — | — | Mirrored from positions.quantity at time of change |
| average_cost | DECIMAL(15,4) | NULL | — | — | Mirrored from positions.average_cost at time of change |
| current_value | DECIMAL(15,4) | NULL | — | — | Mirrored from positions.current_value at time of change |
| unrealized_pnl | DECIMAL(15,4) | NULL | — | — | Mirrored from positions.unrealized_pnl at time of change |
| created_at | DATETIME | NULL | — | — | Mirrored from positions.created_at at time of change |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Set by trigger to OLD.updated_at at INSERT; ON UPDATE clause satisfies CLAUDE.md audit requirement but never fires on INSERT-only rows |

**Primary Key**: history_id

**Foreign Keys**:
- position_id → positions(position_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**: none

**Check Constraints**: none

**Indexes needed** (beyond PK and FK auto-indexes):
- idx_position_history_position_id ON (position_id) — retrieves the full position audit trail for a specific holding
- idx_position_history_changed_at ON (changed_at) — supports time-range compliance queries and portfolio valuation history

---

### Table: ledger_audit

**Purpose**: INSERT-only audit log populated exclusively by `AFTER UPDATE` and `AFTER DELETE` triggers on the `accounting_ledgers` table; preserves pre-change financial values for tamper-evident journal integrity.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| history_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique history record identifier |
| change_type | ENUM('UPDATE','DELETE') | NOT NULL | — | — | Type of DML operation that triggered this history record |
| changed_at | DATETIME(6) | NOT NULL | CURRENT_TIMESTAMP(6) | DEFAULT | Microsecond-precision timestamp of the triggering DML operation |
| changed_by | VARCHAR(100) | NOT NULL | — | — | Database user or application context that initiated the change |
| ledger_id | BIGINT | NOT NULL | — | FK | Parent ledger entry being audited; references accounting_ledgers(ledger_id) |
| transaction_date | DATETIME(6) | NULL | — | — | Mirrored from accounting_ledgers.transaction_date at time of change |
| debit_account | VARCHAR(50) | NULL | — | — | Mirrored from accounting_ledgers.debit_account at time of change |
| credit_account | VARCHAR(50) | NULL | — | — | Mirrored from accounting_ledgers.credit_account at time of change |
| amount | DECIMAL(15,4) | NULL | — | — | Mirrored from accounting_ledgers.amount at time of change |
| reference_type | ENUM('ORDER','SETTLEMENT','ADJUSTMENT') | NULL | — | — | Mirrored from accounting_ledgers.reference_type at time of change |
| reference_id | BIGINT | NULL | — | — | Mirrored from accounting_ledgers.reference_id at time of change |
| description | TEXT | NULL | — | — | Mirrored from accounting_ledgers.description at time of change. ⚠️ **Cross-migration type mismatch:** V4 declares TEXT here but V1 parent column is VARCHAR(255). Migrations are immutable; this discrepancy is documented but not correctable without a new migration. |
| created_at | DATETIME | NULL | — | — | Mirrored from accounting_ledgers.created_at at time of change |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Set by trigger to OLD.updated_at at INSERT; ON UPDATE clause satisfies CLAUDE.md audit requirement but never fires on INSERT-only rows |

**Primary Key**: history_id

**Foreign Keys**:
- ledger_id → accounting_ledgers(ledger_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**: none

**Check Constraints**: none

**Indexes needed** (beyond PK and FK auto-indexes):
- idx_ledger_audit_ledger_id ON (ledger_id) — retrieves the full audit trail for a specific ledger entry
- idx_ledger_audit_changed_at ON (changed_at) — supports regulatory compliance and period-end audit queries

---

### Table: settlement_history

**Purpose**: INSERT-only audit log populated exclusively by `AFTER UPDATE` and `AFTER DELETE` triggers on the `settlements` table; preserves settlement status transitions and net amount changes for dispute resolution.

| Column Name | MySQL Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| history_id | BIGINT | NOT NULL | — | PK, AUTO_INCREMENT | Surrogate primary key; system-assigned unique history record identifier |
| change_type | ENUM('UPDATE','DELETE') | NOT NULL | — | — | Type of DML operation that triggered this history record |
| changed_at | DATETIME(6) | NOT NULL | CURRENT_TIMESTAMP(6) | DEFAULT | Microsecond-precision timestamp of the triggering DML operation |
| changed_by | VARCHAR(100) | NOT NULL | — | — | Database user or application context that initiated the change |
| settlement_id | BIGINT | NOT NULL | — | FK | Parent settlement being audited; references settlements(settlement_id) |
| order_id | BIGINT | NULL | — | — | Mirrored from settlements.order_id at time of change |
| trade_price | DECIMAL(15,4) | NULL | — | — | Mirrored from settlements.trade_price at time of change |
| quantity | INT | NULL | — | — | Mirrored from settlements.quantity at time of change |
| gross_amount | DECIMAL(15,4) | NULL | — | — | Mirrored from settlements.gross_amount at time of change |
| commission | DECIMAL(15,4) | NULL | — | — | Mirrored from settlements.commission at time of change |
| net_amount | DECIMAL(15,4) | NULL | — | — | Mirrored from settlements.net_amount at time of change |
| settlement_date | DATE | NULL | — | — | Mirrored from settlements.settlement_date at time of change |
| settlement_status | ENUM('PENDING','SETTLED','FAILED','REVERSED') | NULL | — | — | Mirrored from settlements.settlement_status at time of change |
| created_at | DATETIME | NULL | — | — | Mirrored from settlements.created_at at time of change |
| updated_at | DATETIME | NOT NULL | CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP | DEFAULT | Set by trigger to OLD.updated_at at INSERT; ON UPDATE clause satisfies CLAUDE.md audit requirement but never fires on INSERT-only rows |

**Primary Key**: history_id

**Foreign Keys**:
- settlement_id → settlements(settlement_id) ON DELETE RESTRICT ON UPDATE CASCADE

**Unique Constraints**: none

**Check Constraints**: none

**Indexes needed** (beyond PK and FK auto-indexes):
- idx_settlement_history_settlement_id ON (settlement_id) — retrieves full status-change history for a settlement record
- idx_settlement_history_changed_at ON (changed_at) — supports T+2 failure investigation and regulatory audit queries

---

## 4.2 ER-to-Relational Mapping Narrative

**One-to-Many Relationships.** Every 1:N relationship in the ER diagram maps to a foreign key placed on the "many" side of the association. The trader_id column in both `portfolios` and `orders` references `traders.trader_id`; portfolio_id and asset_id in `positions` reference their respective parent tables; portfolio_id and asset_id in `orders` do the same. All foreign keys are declared with `ON DELETE RESTRICT` — preventing removal of any parent row that still has child records — and `ON UPDATE CASCADE`, propagating primary key changes automatically. The `UNIQUE (portfolio_id, asset_id)` constraint on `positions` further enforces that each portfolio–asset pair has exactly one position row, aggregating all fills into a single record rather than storing individual trade lots.

**Optional One-to-Zero-or-One: orders → settlements.** Two implementation strategies exist for 1:0..1 cardinality. The first places a nullable `settlement_id` foreign key on the `orders` table; the second places a non-nullable `order_id` foreign key on `settlements` combined with a `UNIQUE` constraint. This design adopts the second approach. A nullable FK on `orders` would require a two-step write (INSERT the order, then UPDATE it after the settlement is created), introducing a window of inconsistency and a potential circular FK dependency if both tables referenced each other. With the FK on `settlements`, every settlement row unambiguously references its parent order at INSERT time, and the `UNIQUE (order_id)` constraint prevents more than one settlement per order without any additional application-level enforcement.

**Polymorphic Reference Pattern: accounting_ledgers.** The `reference_type` / `reference_id` column pair implements a polymorphic association: when `reference_type = 'ORDER'`, `reference_id` is interpreted as `orders.order_id`; when `reference_type = 'SETTLEMENT'`, it is `settlements.settlement_id`; when `reference_type = 'ADJUSTMENT'`, it is an internal reference with no parent table. Because the referenced table varies at runtime, the MySQL engine cannot declare a standard `FOREIGN KEY` constraint for this column pair. An alternative design using separate nullable FK columns (`order_id BIGINT NULL`, `settlement_id BIGINT NULL`) would restore DB-level referential integrity but requires an additional CHECK constraint to ensure exactly one column is non-null, and adds a new nullable column for every future event type. The polymorphic pattern avoids this DDL expansion and keeps the ledger schema extensible; the trade-off is that `reference_id` validity must be enforced within the `sp_execute_trade` and `sp_cancel_order` stored procedures before any `INSERT` into `accounting_ledgers`.

**Trigger-Based INSERT-Only Audit Tables.** The four `_history` / `_audit` tables are populated exclusively by `AFTER UPDATE` and `AFTER DELETE` triggers on their respective parent tables (FR-AUD-001, FR-AUD-002). Capturing audit records at the InnoDB engine level guarantees that every row modification is recorded regardless of whether the change originates from the application layer, a stored procedure, or a direct administrative session — sources that application-level logging cannot guarantee to intercept. No database role is granted `UPDATE` or `DELETE` privileges on any history table (FR-AUD-003), rendering each audit row immutable from the moment of insertion and producing a tamper-evident, append-only journal that satisfies compliance and evidentiary requirements.

---

## 4.3 Design Decisions Log

**Decision 1 — DECIMAL(15,4) for all monetary and price columns.** The alternatives are `FLOAT`/`DOUBLE` (IEEE 754 binary floating-point) and `BIGINT` storing integer cents. FLOAT and DOUBLE are ruled out categorically: binary floating-point cannot represent most decimal fractions exactly, producing rounding drift that accumulates across thousands of settlement calculations and violates the double-entry invariant (FR-BIZ-004). A BIGINT cents approach avoids floating-point error but introduces a persistent unit-conversion obligation — every read must divide by 100, every write must multiply, and this convention must be enforced across the application, stored procedures, and reporting layer without any schema-level documentation. DECIMAL(15,4) is self-documenting (the type itself declares the scale), supports currencies without sub-cent denominations (e.g., JPY, KRW) as well as four-decimal-place pricing for bonds and ETFs, and MySQL stores DECIMAL as an exact fixed-point binary-coded decimal with no representation error.

**Decision 2 — Separate per-entity history tables rather than a single generic audit_log.** A single `audit_log` table with columns `(table_name, record_id, change_type, old_values JSON, new_values JSON, changed_at, changed_by)` is simpler to maintain and avoids DDL changes when source tables evolve. However, it forces every audit query to parse a JSON blob: a compliance officer querying all status transitions for a specific order must extract `old_values->>'$.order_status'` from potentially millions of rows, with no index on the extracted value. Per-entity history tables (`order_history`, `position_history`, `ledger_audit`, `settlement_history`) carry typed columns that match their parent tables exactly, support standard B-tree indexes on `order_id` and `changed_at`, and allow JOIN-free audit queries that read and filter as ordinary relational data. The cost — one additional DDL statement per future schema change to the parent table — is acceptable given the compliance and performance requirements.

**Decision 3 — ENUM for all status and type columns.** The alternative is a `status_codes` or `order_types` lookup table with a foreign key reference. Lookup tables provide runtime extensibility (a new status can be added with an INSERT rather than an ALTER TABLE) and support localised descriptions. However, the valid values for all status and type fields in this system are defined by financial protocol specifications (`PENDING` → `PARTIALLY_FILLED` → `FILLED` is a fixed regulatory lifecycle, not a business configuration). They do not change at runtime and do not carry localised descriptions in the current scope. ENUM avoids the JOIN overhead incurred on every `orders`, `positions`, and `settlements` read, stores the value in 1–2 bytes (vs. a BIGINT FK), and makes invalid values impossible at the database level without an additional constraint. The cost of an `ALTER TABLE` to add a new ENUM value (a rare, schema-level event) is acceptable.

**Decision 4 — Retained gross_amount and net_amount in settlements.** The normalization analysis (Stage 3, §settlements) correctly identifies both columns as 3NF violations: `{trade_price, quantity} → gross_amount` and `{gross_amount, commission} → net_amount` are non-key functional dependencies among non-prime attributes. Under strict normalization, both should be removed and computed at query time. They are retained here for two reasons. First, the V5 seed data specification references both columns directly and requires their presence in the physical table for the data generation scripts to function without modification. Second, settled trade records are legally immutable — the exact agreed amounts at settlement time must be preserved as a point-in-time record for regulatory post-trade reporting, not recomputed from current inputs. A stored procedure enforces consistency at write time: `gross_amount` must equal `trade_price × quantity` and `net_amount` must equal `gross_amount ± commission` before any INSERT is committed; this eliminates the update anomaly risk associated with the stored redundancy.

**Decision 5 — Retained current_value and unrealized_pnl in positions (intentional denormalization).** Both columns are derivable from a cross-table calculation: `current_value = positions.quantity × assets.current_price` and `unrealized_pnl = current_value − positions.quantity × positions.average_cost`. The normalization analysis (Stage 3, §positions) documents this as a cross-table derivation anomaly rather than a strict 3NF violation (because the dependency crosses table boundaries). The pure relational approach exposes these values through a `v_portfolio_summary` view computed at query time. They are stored as materialised columns instead for read performance: portfolio dashboard queries retrieve `current_value` and `unrealized_pnl` for potentially thousands of positions simultaneously, and requiring a JOIN to `assets` on every page load introduces latency proportional to portfolio size. The stored procedure responsible for processing each fill recalculates and persists both values atomically within the same transaction that updates `quantity` and `average_cost`, accepting transient staleness between market price ticks — which is the same staleness that would exist if `assets.current_price` itself is not updated in real time. The trade-off is an O(N) update cascade whenever a bulk price refresh is applied; this is mitigated by batching price updates and recalculating positions in a background job rather than inline per-tick.
