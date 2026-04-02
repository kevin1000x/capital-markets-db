> Last reverse-synced: 2026-03-10. Reflects final state of V1–V4 migrations.

# Requirements Analysis: Capital Markets Financial Trading Platform Database System

---

## 1. Problem Statement

### 1.1 Background and Motivation

Securities trading operations at institutional scale require the coordinated
management of trader accounts, financial instruments, order routing, trade
execution, position maintenance, and post-trade settlement across multiple
concurrent participants. In the absence of a centralised, transactional database
system, these operations are commonly managed through fragmented spreadsheets and
siloed ledger files, introducing critical operational risks. Manual tracking
mechanisms provide no ACID guarantees, meaning concurrent order submissions may
produce inconsistent state in the absence of atomic, isolated transactions. The
lack of a reliable audit trail makes post-trade reconciliation and regulatory
inquiry difficult to satisfy, while race conditions on concurrent order
modifications can result in inventory mismatches and financial loss. Furthermore,
the absence of enforced double-entry accounting integrity permits ledger
imbalances to persist undetected, undermining the accuracy of portfolio
valuations and financial reporting.

### 1.2 Problem Definition

This project designs and implements a fully normalised relational database system
to track the complete lifecycle of a financial trade: from the submission of a
buy or sell order, through partial and full execution, to T+2 settlement and the
corresponding double-entry accounting ledger entries. The system must enforce
referential integrity across all domain entities, guarantee ACID compliance for
all financial write operations, and maintain an immutable audit trail for every
state change to core financial records. The implementation targets MySQL 8.0 with
the InnoDB storage engine, employing Flyway-managed versioned migrations and
role-based access control.

---

## 2. System Scope and Objectives

### 2.1 In Scope

- **Multi-asset trading**: equities (stocks), fixed income (bonds),
  exchange-traded funds (ETFs), and derivatives (options and futures).
- **Trader account management and portfolio tracking**: each trader may hold one
  or more named portfolios; the system maintains current positions and aggregate
  valuations per portfolio.
- **Order lifecycle management**: orders shall transition through the state
  machine NEW → PARTIAL → FILLED → CANCELLED, with all transitions persisted.
- **Position maintenance**: current asset holdings shall be updated atomically
  upon every order execution event via stored procedure.
- **Double-entry accounting ledger**: every financial event shall generate
  exactly one debit entry and one credit entry summing to zero, enforced as a
  database-level invariant.
- **T+2 settlement workflow**: settlement obligations and their resolution shall
  be recorded for all executed trades.
- **Immutable audit trail**: AFTER UPDATE and AFTER DELETE triggers shall write
  before-images of all changes to core financial tables into append-only history
  tables.

### 2.2 Out of Scope

- Real-time market data feeds and streaming price ingestion pipelines.
- Risk management calculations (margin, value-at-risk, collateral management).
- Regulatory reporting frameworks (MiFID II transaction reporting, Dodd-Frank
  swap data repository submissions).

---

## 3. Core Entities

### 3.1 Traders

A trader represents an individual or institutional participant authorised to
submit orders within the system. Key attributes include a unique trader
identifier, legal name, email address, account status, and assigned system role.
Traders are the originating parties for all orders and are associated with one
or more portfolios through which their positions are managed. The system enforces
that no order may be submitted on behalf of a suspended or inactive trader. As a
real-world example, a hedge fund acting as a single institutional trader may
maintain multiple portfolios representing distinct investment mandates.

### 3.2 Assets

An asset represents a financial instrument available for trading within the
platform. Key attributes include ticker symbol (up to 10 characters), asset type
(STOCK, BOND, ETF, or DERIVATIVE), listing exchange, denomination currency,
current market price as DECIMAL(15,4), and active status. Assets are referenced by both orders and positions;
their current market price determines the mark-to-market valuation of all
holdings. An asset may be delisted — marked inactive — without deletion, thereby
preserving historical position and order records. For example, Apple Inc. common
stock is represented as ticker AAPL, asset type STOCK, currency USD.

### 3.3 Portfolios

A portfolio is a named collection of positions held by a single trader and serves
as the primary unit of performance measurement and valuation reporting. Each
trader may maintain multiple portfolios reflecting different investment strategies
or risk mandates. Key attributes include portfolio name, owning trader reference,
and optional description. Portfolio valuation is derived by aggregating
the current market value of all constituent positions. For instance, a trader
might maintain both a "Fixed Income Portfolio" and a "Growth Equity Portfolio" as
distinct managed accounts.

### 3.4 Orders

An order represents a buy or sell instruction submitted by a trader against a
specific asset within a designated portfolio. Key attributes include side (BUY or
SELL), order type (MARKET, LIMIT, STOP, or STOP_LIMIT), limit price, requested
quantity, filled quantity, average fill price, and current status. Orders progress
through a defined lifecycle — PENDING, PARTIALLY_FILLED, FILLED, CANCELLED, or
REJECTED — with each status transition persisted and audited. Cancelled orders
record a cancellation timestamp and reason. The system validates that the submitting trader and target portfolio are
active prior to order acceptance. An example order specifies: BUY 1,000 shares of
AAPL at a limit price of USD 175.0000.

### 3.5 Positions

A position records the current net holding of a specific asset within a specific
portfolio. Key attributes include the portfolio reference, asset reference, net
quantity held, and average cost per unit stored as DECIMAL(15,4). Positions are
updated atomically upon every trade execution via stored procedure, employing
pessimistic locking (SELECT … FOR UPDATE) to prevent concurrent write conflicts.
A position with a quantity of zero is retained as a record of prior ownership and
cost basis. For example, a position might record 500 shares of AAPL at an average
cost of USD 172.5000 within the Growth Equity Portfolio.

### 3.6 Accounting Ledgers

The accounting ledger provides an immutable, double-entry record of every
financial event within the system. Each ledger row records a single journal
posting with a debit account code, a credit account code, and a positive amount
as DECIMAL(15,4), representing the flow of value from the debited account to the
credited account. A polymorphic reference (reference_type and reference_id)
links each posting to the originating order, settlement, or manual adjustment. No UPDATE or DELETE operations are permitted on the accounting ledger
under any operational circumstance; it is maintained as an append-only financial
record. As an example, a trade settlement debits the cash account and credits the
securities account by the equivalent transaction value.

### 3.7 Settlements

A settlement record represents the clearing and delivery obligations arising from
a fully or partially executed order, managed under the T+2 settlement convention.
Key attributes include the linked order identifier (1:1 cardinality enforced by
UNIQUE constraint), trade price, settled quantity, gross amount, commission,
net amount (all as DECIMAL(15,4)), settlement date (two business days after
execution), and settlement status (PENDING, SETTLED, FAILED, or REVERSED). The settlement
workflow ensures that securities and cash obligations are formally recorded and
reconcilable against the accounting ledger. Failed settlements trigger a status
update and require manual intervention outside the scope of automated processing.
For example, an equity trade executed on a Monday carries a settlement date of
the following Wednesday.

### 3.8 History and Audit Tables

History and audit tables are immutable shadow tables that record the complete
before-image of every row modified or deleted in a core financial table. They are
populated exclusively by AFTER UPDATE and AFTER DELETE database triggers and are
never subject to application-layer writes, updates, or deletions. Key attributes
replicate all columns of the source table, augmented by a change timestamp, the
triggering database user, and the operation type (UPDATE or DELETE). The audit
tables serve as the primary evidentiary record for compliance review and dispute
resolution. For example, the orders_history table captures every prior state of
an order row at the instant any field is modified.

---

## 4. Stakeholder Analysis

### 4.1 Traders

Traders are the primary end users of the system, responsible for submitting buy
and sell orders and monitoring the performance of their portfolios. Their
principal system interactions include order submission, position inquiry, and
trade history review, requiring read-write access to the orders table and
read-only access to asset, portfolio, and position data. Their primary concern is
execution accuracy — ensuring that submitted orders are recorded correctly and
that position updates reflect executions without delay or data loss.

### 4.2 Portfolio Managers

Portfolio managers oversee the strategic composition and performance of one or
more trader portfolios. Their interactions are primarily analytical — reviewing
aggregate position valuations, unrealised profit and loss, and order flow
summaries — and require read-only access to portfolio valuation views and position
data. Their key concern is the accuracy and timeliness of mark-to-market
valuations that inform investment decision-making.

### 4.3 Risk Officers

Risk officers monitor the aggregate exposure of the firm across all active
positions and outstanding orders. Their system interactions involve querying
position tables, reviewing anomalous orders, and examining accounting ledger
balances, requiring read-only access to positions, orders, and the ledger with no
ability to modify records. Their primary concern is the prevention of
over-concentration risk and the early identification of settlement failures or
ledger imbalances.

### 4.4 Compliance Auditors

Compliance auditors are responsible for reviewing the tamper-proof history of all
system activity for regulatory and internal governance purposes. Their
interactions are restricted to read-only queries against history and audit tables,
and they are granted no DML privileges on any production table. Their key concern
is the integrity and immutability of the audit trail — specifically, that audit
records cannot be modified or deleted by any user or process.

### 4.5 System Administrators

System administrators manage the operational infrastructure of the database,
including user provisioning, role assignment, and the sequential application of
Flyway database migration scripts. They hold DDL and GRANT privileges but do not
interact with trading data in the course of normal operations. Their primary
concern is schema stability — ensuring that migration files are applied in correct
version order and that no existing migration file is altered after deployment.

---

## 5. Data Requirements

### 5.1 Input Data

Input data includes: trader registration records (name, credentials, role);
asset master data (ticker symbol, asset type, exchange, current price); order submissions
(trader, asset, portfolio, side, type, limit price, quantity); and periodic
market price updates used for mark-to-market position valuation. All monetary
input values must conform to DECIMAL(15,4) precision prior to persistence.

### 5.2 Output Data

The system produces: portfolio valuation reports aggregating position quantities
and current market values; trade confirmation records for each filled or partially
filled order; profit and loss statements derived from average cost versus current
market price; immutable audit logs for compliance review; and settlement
notifications indicating the status (PENDING, SETTLED, or FAILED) of each
executed trade obligation.

### 5.3 Stored Data

The system persistently stores: the complete historical record of all submitted
and executed orders; time-series market price snapshots for each asset; double-
entry accounting ledger entries on an append-only basis; current and historical
position records per portfolio per asset; and the full before-image history of
every modification to core financial tables, retained indefinitely for audit
purposes.

---

## 6. System Constraints and Assumptions

### 6.1 Technical Constraints

- Database management system: MySQL 8.0; no alternative RDBMS is considered.
- Storage engine: InnoDB is mandatory on all tables for row-level locking and
  ACID transaction support.
- Monetary precision: all prices, amounts, and quantities with a decimal component
  shall be stored as DECIMAL(15,4); the use of FLOAT or DOUBLE for any financial
  column is strictly prohibited.
- Character set: utf8mb4 with utf8mb4_unicode_ci collation on all tables.
- ACID compliance: all financial write operations shall execute within explicit
  START TRANSACTION / COMMIT blocks with a DECLARE EXIT HANDLER FOR SQLEXCEPTION
  that issues ROLLBACK on error.

### 6.2 Design Constraints

- The accounting_ledgers table is append-only: no UPDATE or DELETE statement
  may be executed against it under any operational circumstance.
- All state changes to core financial tables must be immutably logged to
  corresponding _history tables via AFTER UPDATE and AFTER DELETE triggers.
- Schema evolution is managed exclusively via Flyway versioned migration files;
  existing V*__*.sql files may never be modified after initial deployment.
- History and audit tables are INSERT-only; the trader_role database role is
  granted no SELECT, UPDATE, or DELETE privileges on these tables.

### 6.3 Assumptions

- The system operates in a single base currency (USD); multi-currency conversion
  is outside the defined scope.
- Settlement follows the T+2 convention: all equity and ETF trades settle two
  business days after the execution date.
- Orders are assumed to execute at the submitted limit price, representing a
  simplified execution model suitable for a course prototype; partial fills are
  supported by recording filled quantity separately from requested quantity.

---

## 12. Glossary

**Asset**: A financial instrument available for trading within the platform,
identified by a unique ticker symbol and classified by asset type
(stock, bond, ETF, or derivative).

**Double-Entry Accounting**: An accounting methodology in which every financial
transaction is recorded as exactly two equal and opposite entries — a debit and a
credit — such that the sum of both amounts for any transaction equals zero.

**Debit**: A ledger entry that records an increase in an asset or expense account;
in this system, debit entries are stored as positive DECIMAL(15,4) amounts against
the designated account category.

**Credit**: A ledger entry that records an increase in a liability or equity
account; credit entries offset the corresponding debit entry within the same
journal transaction to maintain ledger balance.

**Journal Entry**: A paired set of debit and credit accounting ledger records
generated by a single financial event, such as a trade execution or settlement,
ensuring that the ledger remains balanced after every operation.

**Order Book**: The collection of all active (NEW and PARTIAL status) buy and sell
orders for a given asset at a given point in time; the order book determines
execution priority under limit-order trading rules.

**Position**: The current net holding of a specific asset within a specific
portfolio, expressed as a quantity and an average cost per unit, updated
atomically upon each trade execution using pessimistic locking.

**Portfolio**: A named grouping of positions owned by a single trader, used as
the primary unit of performance measurement, valuation reporting, and order
attribution within the system.

**Settlement**: The post-trade process by which the buyer receives purchased
securities and the seller receives the corresponding cash payment, formally
concluding the obligations arising from an executed order.

**T+2**: The standard settlement cycle for equities and ETFs, specifying that the
exchange of securities and cash occurs two business days after the trade execution
date.

**ACID**: An acronym denoting the four properties required of reliable database
transactions — Atomicity (the transaction completes fully or not at all),
Consistency (the database transitions between valid states), Isolation (concurrent
transactions do not interfere with one another), and Durability (committed changes
survive system failure).

**InnoDB**: The default transactional storage engine for MySQL 8.0, providing
row-level locking, foreign key constraint enforcement, crash recovery via redo
logs, and full ACID transaction support; mandatory for all tables in this system.

**DECIMAL Precision**: The MySQL DECIMAL(15,4) data type, which stores exact
fixed-point numeric values with up to 15 significant digits and exactly 4 digits
after the decimal point, used for all monetary, price, and quantity columns to
eliminate floating-point rounding error.

**Flyway**: An open-source database migration tool that applies versioned SQL
scripts (V1__*.sql, V2__*.sql, …) to a target database in strict sequential order,
recording each applied version in a schema history table to ensure repeatable and
auditable schema evolution.

**Pessimistic Locking**: A concurrency control strategy in which a transaction
acquires an exclusive row-level lock (via SELECT … FOR UPDATE) before reading data
it intends to modify, preventing concurrent transactions from reading or writing
the same row until the lock is released and thereby eliminating time-of-check /
time-of-use (TOCTOU) race conditions in financial write operations.

---

## 7. Use Case Descriptions

---

**UC-001: Register New Trader Account**

| Field | Description |
|-------|-------------|
| Primary Actor | System Administrator |
| Secondary Actors | Prospective Trader (provides identity data) |
| Preconditions | Administrator is authenticated with appropriate database role; the prospective trader's legal identity has been verified through an external onboarding process; no existing trader record shares the submitted email address. |
| Trigger | The System Administrator submits a completed trader registration request containing the trader's legal name, email address, and designated role. |

**Main Success Flow:**

1. The System Administrator submits trader registration data: legal name, email address, and role designation.
2. The system validates that the submitted email address does not already exist in the `traders` table (`SELECT COUNT(*) WHERE email = ?`).
3. The system validates that all mandatory fields conform to domain constraints (name ≤ 100 characters; email ≤ 100 characters; role is one of the permitted enumerated values).
4. The system executes `INSERT INTO traders (first_name, last_name, email, trader_type, trader_status, registration_date) VALUES (...)` with `trader_status = 'ACTIVE'`.
5. The system creates a default portfolio for the new trader via `INSERT INTO portfolios (trader_id, portfolio_name) VALUES (last_insert_id(), 'Default Portfolio')`.
6. The system grants the `trader_role` database role to the new account.
7. The system returns the generated `trader_id` and confirmation to the Administrator.

**Alternative Flows:**

- A1 [At step 2, if the email address already exists in `traders`]: The system raises a duplicate-email error, aborts the transaction, and returns a descriptive error message to the Administrator; no record is created.
- A2 [At step 3, if any mandatory field fails validation]: The system raises a constraint-violation error, aborts the transaction, and returns the specific failing field to the Administrator; no record is created.

**Postconditions (Success):** A new row exists in `traders` with `status = 'ACTIVE'`; a corresponding default portfolio row exists in `portfolios`; the trader may immediately authenticate and place orders.

**Postconditions (Failure):** No row is created in `traders` or `portfolios`; the database state is unchanged; the Administrator receives a specific error description.

**Business Rules:**

- BR-1: Each trader's email address must be globally unique across the `traders` table.
- BR-2: Trader `trader_status` must default to `ACTIVE` on creation; values are restricted to `ACTIVE`, `SUSPENDED`, and `CLOSED`.
- BR-3: All monetary and identity data must be stored using the utf8mb4 character set to support international characters.

---

**UC-002: Add Asset to Trading Universe**

| Field | Description |
|-------|-------------|
| Primary Actor | System Administrator |
| Secondary Actors | None |
| Preconditions | Administrator is authenticated; no existing asset record shares the submitted ticker symbol; the designated asset type is one of the supported enumerated values (STOCK, BOND, ETF, DERIVATIVE). |
| Trigger | The System Administrator submits a new asset master data record including ticker symbol, asset type, exchange, currency, and current reference price. |

**Main Success Flow:**

1. The System Administrator submits asset master data: ticker symbol, full instrument name, asset type, listing exchange, denomination currency, and initial reference price.
2. The system validates that the ticker symbol (≤ 10 characters) does not already exist in the `assets` table.
3. The system validates that all mandatory fields conform to domain constraints (asset_name ≤ 150 characters; currency is a 3-letter ISO 4217 code).
4. The system validates that `asset_type` is one of: `STOCK`, `BOND`, `ETF`, `DERIVATIVE`.
5. The system validates that the reference price is a positive `DECIMAL(15,4)` value.
6. The system executes `INSERT INTO assets (ticker_symbol, asset_name, asset_type, exchange, currency, current_price, is_active) VALUES (...)` with `is_active = 1`.
7. The system returns the generated `asset_id` and confirmation to the Administrator.

**Alternative Flows:**

- A1 [At step 2, if the ticker symbol already exists]: The system raises a duplicate-ticker error, aborts the transaction, and returns an error message; no record is created.
- A2 [At step 3, if any mandatory field fails validation]: The system raises a constraint-violation error, aborts the transaction; no record is created.
- A3 [At step 4, if the asset type is not a permitted ENUM value]: The system raises an enumeration-constraint error; no record is created.

**Postconditions (Success):** A new row exists in `assets` with `is_active = TRUE`; the asset is immediately available for reference in order submissions and position records.

**Postconditions (Failure):** No row is created in `assets`; the trading universe is unchanged; the Administrator receives a specific error description.

**Business Rules:**

- BR-1: Ticker symbols must be unique and must not exceed 10 characters (VARCHAR(10)).
- BR-2: Asset names must not exceed 150 characters (VARCHAR(150)).
- BR-3: The initial reference price must be stored as `DECIMAL(15,4)` and must be strictly greater than zero.
- BR-4: Assets are never physically deleted; instruments that cease trading are deactivated by setting `is_active = FALSE`.

---

**UC-003: Place Buy Order (LIMIT type)**

| Field | Description |
|-------|-------------|
| Primary Actor | Trader |
| Secondary Actors | None |
| Preconditions | Trader is authenticated and holds `status = 'ACTIVE'`; the target asset exists in `assets` with `is_active = TRUE`; the designated portfolio exists in `portfolios` and is owned by the authenticated trader. |
| Trigger | The Trader submits a BUY LIMIT order specifying asset, portfolio, limit price, and quantity. |

**Main Success Flow:**

1. The Trader submits a BUY LIMIT order: `asset_id`, `portfolio_id`, `limit_price`, and `quantity`.
2. The system queries `SELECT status FROM traders WHERE id = ? FOR UPDATE` and confirms `status = 'ACTIVE'`.
3. The system queries `SELECT is_active FROM assets WHERE id = ?` and confirms `is_active = TRUE`.
4. The system queries `SELECT trader_id FROM portfolios WHERE id = ?` and confirms the portfolio is owned by the authenticated trader.
5. The system validates that `limit_price > 0` and `quantity > 0` (both `DECIMAL(15,4)`).
6. The system executes `INSERT INTO orders (trader_id, asset_id, portfolio_id, side, order_type, limit_price, quantity, filled_quantity, status) VALUES (?, ?, ?, 'BUY', 'LIMIT', ?, ?, 0, 'NEW')`.
7. The system commits the transaction and returns the generated `order_id` and order summary to the Trader.

**Alternative Flows:**

- A1 [At step 2, if `trader.status` is not `ACTIVE`]: The system raises a trader-suspended error, rolls back the transaction, and returns an error; no order is created.
- A2 [At step 3, if `asset.is_active` is `FALSE`]: The system raises an asset-inactive error, rolls back, and returns an error; no order is created.
- A3 [At step 4, if the portfolio does not belong to the trader]: The system raises an unauthorised-portfolio error, rolls back; no order is created.
- A4 [At step 5, if `limit_price ≤ 0` or `quantity ≤ 0`]: The system raises a constraint-violation error; no order is created.

**Postconditions (Success):** A new row exists in `orders` with `status = 'NEW'`, `filled_quantity = 0`, `side = 'BUY'`, and `order_type = 'LIMIT'`; the order is queued for execution.

**Postconditions (Failure):** No row is created in `orders`; all tables remain unchanged; the Trader receives a specific error description.

**Business Rules:**

- BR-1: `limit_price` and `quantity` must be stored as `DECIMAL(15,4)` and must be strictly greater than zero.
- BR-2: Only traders with `status = 'ACTIVE'` may submit orders.
- BR-3: A trader may only submit orders against portfolios they own.
- BR-4: New orders must always be initialised with `status = 'NEW'` and `filled_quantity = 0`.

---

**UC-004: Place Sell Order (MARKET type)**

| Field | Description |
|-------|-------------|
| Primary Actor | Trader |
| Secondary Actors | None |
| Preconditions | Trader is authenticated and holds `status = 'ACTIVE'`; the target asset exists with `is_active = TRUE`; the designated portfolio contains an existing position in the target asset with a net quantity sufficient to cover the sell quantity. |
| Trigger | The Trader submits a SELL MARKET order specifying asset, portfolio, and quantity. |

**Main Success Flow:**

1. The Trader submits a SELL MARKET order: `asset_id`, `portfolio_id`, and `quantity`.
2. The system queries `SELECT status FROM traders WHERE id = ?` and confirms `status = 'ACTIVE'`.
3. The system queries `SELECT is_active FROM assets WHERE id = ?` and confirms `is_active = TRUE`.
4. The system queries `SELECT trader_id FROM portfolios WHERE id = ?` and confirms portfolio ownership.
5. The system executes `SELECT quantity FROM positions WHERE portfolio_id = ? AND asset_id = ? FOR UPDATE` to obtain an exclusive lock on the position row and read the current holding.
6. The system verifies that the position's `quantity >= sell_quantity`; if so, the validation passes.
7. The system executes `INSERT INTO orders (trader_id, asset_id, portfolio_id, side, order_type, quantity, filled_quantity, status) VALUES (?, ?, ?, 'SELL', 'MARKET', ?, 0, 'NEW')`. No limit price is recorded for MARKET orders.
8. The system commits the transaction and returns the generated `order_id` to the Trader.

**Alternative Flows:**

- A1 [At step 2, if `trader.status` is not `ACTIVE`]: The system raises a trader-suspended error, rolls back, and returns an error; no order is created.
- A2 [At step 5, if no position row exists for the given portfolio and asset]: The system raises a no-position error (cannot sell what is not held); rolls back; no order is created.
- A3 [At step 6, if the position `quantity < sell_quantity`]: The system raises an insufficient-position error, rolls back; no order is created.

**Postconditions (Success):** A new row exists in `orders` with `status = 'NEW'`, `side = 'SELL'`, `order_type = 'MARKET'`, and `filled_quantity = 0`; the position row is unlocked and unchanged pending execution.

**Postconditions (Failure):** No row is created in `orders`; the position record is unchanged; the Trader receives a specific error description.

**Business Rules:**

- BR-1: MARKET orders do not carry a `limit_price`; the execution price is determined at the time of fill.
- BR-2: The sell `quantity` must not exceed the current net `quantity` held in the position; this check must be performed under a `SELECT … FOR UPDATE` lock.
- BR-3: `quantity` must be `DECIMAL(15,4)` and strictly greater than zero.

---

**UC-005: Execute and Fill Order (System-Initiated)**

| Field | Description |
|-------|-------------|
| Primary Actor | Trading Engine (System) |
| Secondary Actors | Settlement System, Trader (receives confirmation) |
| Preconditions | A matching order exists in `orders` with `status = 'NEW'` or `status = 'PARTIAL'`; the referenced asset is active; a valid execution price is available. |
| Trigger | The Trading Engine identifies a fill event for a queued order at the order's limit price (or prevailing market price for MARKET orders). |

**Main Success Flow:**

1. The Trading Engine identifies an order eligible for execution and begins a transaction: `START TRANSACTION`.
2. The system executes `SELECT * FROM orders WHERE id = ? FOR UPDATE` to acquire an exclusive row lock before any state is read or modified.
3. The system confirms that `order.status` is `'NEW'` or `'PARTIAL'`; a status of `'CANCELLED'` or `'FILLED'` causes immediate rollback.
4. The system determines the fill quantity: either the full remaining `(quantity − filled_quantity)` for a complete fill, or a partial amount for a partial fill.
5. **For a full fill:** The system executes `UPDATE orders SET status = 'FILLED', filled_quantity = quantity WHERE id = ?`.  **For a partial fill:** The system executes `UPDATE orders SET status = 'PARTIAL', filled_quantity = filled_quantity + ? WHERE id = ?`.
6. The system executes `SELECT * FROM positions WHERE portfolio_id = ? AND asset_id = ? FOR UPDATE` to lock the position row; if no row exists, a new position row is created via `INSERT INTO positions`.
7. The system updates the position: recalculates average cost as `((old_quantity × old_avg_cost) + (fill_qty × execution_price)) / new_quantity`; executes `UPDATE positions SET quantity = ?, average_cost = ? WHERE id = ?`.
8. The system creates exactly two accounting ledger entries within the same transaction: `INSERT INTO accounting_ledgers (order_id, entry_type, account_category, amount) VALUES (?, 'DEBIT', 'CASH', -fill_value), (?, 'CREDIT', 'SECURITIES', fill_value)`, where `fill_value = fill_qty × execution_price` as `DECIMAL(15,4)` and the sum of both amounts equals zero.
9. The system creates a settlement record: `INSERT INTO settlements (order_id, settlement_date, status, amount) VALUES (?, DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'PENDING', ?)`.
10. The system executes `COMMIT`; confirmation is dispatched to the Trader.

**Alternative Flows:**

- A1 [At step 3, if `order.status = 'CANCELLED'` or `'FILLED'`]: The system immediately executes `ROLLBACK`; no tables are modified; the Trading Engine logs a stale-order warning.
- A2 [At step 4, if only a partial fill is available]: The system applies steps 5–10 for the partial quantity only; the order remains in `status = 'PARTIAL'` and re-enters the execution queue for the residual quantity.
- A3 [At any step, if an SQL exception is raised]: The `DECLARE EXIT HANDLER FOR SQLEXCEPTION` fires, executes `ROLLBACK`, and logs the failure; all tables revert to their pre-transaction state.

**Postconditions (Success):** The order `status` is `'FILLED'` or `'PARTIAL'`; the position reflects the updated quantity and average cost; exactly two ledger entries exist summing to zero; one `PENDING` settlement record exists.

**Postconditions (Failure):** All tables remain in their pre-transaction state; the order retains its previous `status`; no ledger or settlement records are created.

**Business Rules:**

- BR-1: `SELECT … FOR UPDATE` must be applied to both the `orders` row (step 2) and the `positions` row (step 6) before any read-then-write operation, eliminating TOCTOU race conditions.
- BR-2: Every execution must produce exactly two accounting ledger entries (one DEBIT, one CREDIT) whose amounts sum to zero; this invariant is mandatory and is verified by the test suite.
- BR-3: Execution price and fill value must be stored as `DECIMAL(15,4)`; FLOAT and DOUBLE are prohibited.
- BR-4: Settlement date must be set to the execution date plus two business days (T+2 convention).

---

**UC-006: Cancel Order and Process Refund**

| Field | Description |
|-------|-------------|
| Primary Actor | Trader |
| Secondary Actors | None |
| Preconditions | Trader is authenticated; the specified order exists in `orders` and is owned by the authenticated trader; the order's current `order_status` is `'PENDING'` or `'PARTIALLY_FILLED'`. |
| Trigger | The Trader submits a cancellation request for a specific `order_id`. |

**Main Success Flow:**

1. The Trader submits a cancellation request containing the `order_id`.
2. The system begins a transaction: `START TRANSACTION`.
3. The system executes `SELECT * FROM orders WHERE id = ? FOR UPDATE` to acquire an exclusive row-level lock on the order before reading its status. This pessimistic lock is mandatory: it prevents a concurrent execution or duplicate cancellation request from reading the same `'NEW'` status simultaneously and producing a race condition.
4. The system verifies that `order.trader_id` matches the authenticated trader's identity; a mismatch causes immediate `ROLLBACK` and an authorisation error.
5. The system reads `order.order_status`; only `'PENDING'` or `'PARTIALLY_FILLED'` are eligible for cancellation. A status of `'FILLED'` or `'CANCELLED'` causes immediate `ROLLBACK` with an appropriate error.
6. The system executes `UPDATE orders SET order_status = 'CANCELLED' WHERE order_id = ?`.
7. If the order was in `order_status = 'PARTIALLY_FILLED'` (a partial fill had already been recorded), the system inserts two reversal accounting ledger entries to unwind the partial position: `INSERT INTO accounting_ledgers (order_id, entry_type, account_category, amount) VALUES (?, 'DEBIT', 'SECURITIES', -partial_value), (?, 'CREDIT', 'CASH', partial_value)`, where the sum of both amounts equals zero, and updates the position accordingly.
8. The system executes `COMMIT` and returns a cancellation confirmation to the Trader.

**Alternative Flows:**

- A1 [At step 5, if `order.status = 'FILLED'`]: The system executes `ROLLBACK` and returns an error stating that a fully filled order cannot be cancelled; the order record is unchanged.
- A2 [At step 5, if `order.status = 'CANCELLED'`]: The system executes `ROLLBACK` and returns an idempotent confirmation that the order is already cancelled; no further action is taken.
- A3 [At any step, if an SQL exception is raised]: The `DECLARE EXIT HANDLER FOR SQLEXCEPTION` fires, executes `ROLLBACK`; all tables revert to their pre-transaction state.

**Postconditions (Success):** The order row holds `order_status = 'CANCELLED'`; if a partial fill existed, two offsetting reversal ledger entries have been created summing to zero, and the position has been adjusted; no monetary state is left inconsistent.

**Postconditions (Failure):** The order `status` is unchanged; no ledger entries are created; the database state is identical to its pre-request state.

**Business Rules:**

- BR-1: `SELECT … FOR UPDATE` on the `orders` row is mandatory before any status check or modification, preventing concurrent cancellation race conditions (TOCTOU vulnerability).
- BR-2: Only orders with `order_status = 'PENDING'` or `'PARTIALLY_FILLED'` may be cancelled; a `'FILLED'` order is irrevocable.
- BR-3: Any reversal ledger entries created during cancellation must also satisfy the double-entry invariant: debit amount and credit amount must sum to zero.
- BR-4: The cancellation operation must execute within a single `START TRANSACTION / COMMIT` block with a `DECLARE EXIT HANDLER FOR SQLEXCEPTION` issuing `ROLLBACK` on any failure.

---

**UC-007: View Portfolio Holdings and Unrealised P&L**

| Field | Description |
|-------|-------------|
| Primary Actor | Trader; Portfolio Manager |
| Secondary Actors | None |
| Preconditions | Actor is authenticated; the specified portfolio exists and is owned by (or accessible to) the requesting actor; at least one position record exists in `positions` for the portfolio. |
| Trigger | The actor requests a portfolio holdings summary for a given `portfolio_id`. |

**Main Success Flow:**

1. The actor submits a holdings request specifying `portfolio_id`.
2. The system verifies that `portfolios.trader_id` matches the authenticated actor's identity (or that the actor holds a Portfolio Manager role with appropriate read access).
3. The system queries the `positions` table joined with `assets` for the given portfolio: `SELECT a.ticker, a.name, p.quantity, p.average_cost, a.current_price FROM positions p JOIN assets a ON p.asset_id = a.id WHERE p.portfolio_id = ?`.
4. For each position row, the system computes unrealised P&L: `unrealised_pnl = (current_price − average_cost) × quantity` using `DECIMAL(15,4)` arithmetic throughout.
5. The system computes total portfolio market value: `SUM(current_price × quantity)` across all positions.
6. The system returns the per-position table (ticker, quantity, average cost, current price, unrealised P&L) and the aggregate portfolio value to the actor. No rows in any table are modified.

**Alternative Flows:**

- A1 [At step 2, if the portfolio does not belong to the actor and the actor is not a Portfolio Manager]: The system returns an authorisation error; no data is disclosed.
- A2 [At step 3, if no position rows exist for the portfolio]: The system returns an empty holdings summary with a total portfolio value of zero; no error is raised.
- A3 [At step 3, if `assets.current_price` is NULL for any position]: The system substitutes `average_cost` as a proxy price and flags the position with a data-unavailable indicator in the output.

**Postconditions (Success):** A read-only holdings report is returned to the actor; no rows in `positions`, `assets`, `portfolios`, or any other table have been modified.

**Postconditions (Failure):** No data is returned; the actor receives an authorisation or system error; database state is unchanged.

**Business Rules:**

- BR-1: All arithmetic (unrealised P&L, market value) must be performed using `DECIMAL(15,4)` precision; intermediate rounding must not be applied before the final result is computed.
- BR-2: This use case is strictly read-only; no `INSERT`, `UPDATE`, or `DELETE` statements may be issued.
- BR-3: Position data for portfolios not owned by the requesting actor must never be disclosed without an explicit Portfolio Manager role grant.

---

**UC-008: Generate Accounting Ledger Reconciliation Report**

| Field | Description |
|-------|-------------|
| Primary Actor | Compliance Auditor; Risk Officer |
| Secondary Actors | None |
| Preconditions | Actor is authenticated with read-only access to `accounting_ledgers`; a valid date range (start date, end date) has been provided; the actor holds no DML privileges on any financial table. |
| Trigger | The actor requests a reconciliation report for a specified date range to verify the integrity of all journal entries within that period. |

**Main Success Flow:**

1. The actor submits a reconciliation request specifying `date_from` and `date_to`.
2. The system queries all ledger entries within the range: `SELECT order_id, entry_type, amount FROM accounting_ledgers WHERE created_at BETWEEN ? AND ?`.
3. The system groups the retrieved entries by `order_id` (each `order_id` represents a paired journal entry) and computes `SUM(amount)` for each group.
4. The system evaluates the double-entry invariant for every journal entry group: each group must satisfy `SUM(amount) = 0`. A result of zero confirms that the debit and credit amounts are equal and opposite; any non-zero result constitutes an integrity violation.
5. The system counts: total ledger entries retrieved, total debit entries, total credit entries, total journal entry groups, and the number of groups with `SUM(amount) ≠ 0` (integrity violations).
6. The system returns the reconciliation report to the actor: summary counts, the aggregate balance across all entries (which must also equal zero for a balanced ledger), and a flagged list of any journal entries that violate the double-entry invariant.
7. No row in `accounting_ledgers` or any other table is modified at any stage of this use case.

**Alternative Flows:**

- A1 [At step 2, if no ledger entries exist within the specified date range]: The system returns an empty reconciliation report with zero counts and notes that no entries were found; no error is raised.
- A2 [At step 4, if one or more journal entry groups yield `SUM(amount) ≠ 0`]: The system flags each violating `order_id` in the report output and marks the overall reconciliation status as `FAILED`; the report is still returned in full so that the actor may investigate the specific violations.
- A3 [At step 1, if `date_from > date_to`]: The system returns an invalid-date-range error without querying the ledger.

**Postconditions (Success):** A complete reconciliation report has been returned to the actor; the report confirms whether all journal entries within the date range satisfy the double-entry invariant (`SUM(amount) = 0` per group); no tables have been modified.

**Postconditions (Failure):** No report is returned; the actor receives an error description; database state is unchanged.

**Business Rules:**

- BR-1: The double-entry invariant — every journal entry group (identified by `order_id`) must have `SUM(amount) = 0` — is the central correctness criterion of this report; any violation indicates a data integrity breach that must be escalated.
- BR-2: The aggregate sum of all ledger entries across the entire report period must also equal zero; a non-zero aggregate indicates that orphaned or unmatched entries exist in the ledger.
- BR-3: No `UPDATE` or `DELETE` statement may ever be issued against `accounting_ledgers`; the table is append-only and the reconciliation process must be entirely read-only.
- BR-4: All amount comparisons must use exact `DECIMAL(15,4)` arithmetic; floating-point types must not be used in any intermediate calculation to avoid false-positive zero-sum results caused by rounding error.

---

## 8. Functional Requirements

---

### 8.1 CRUD Requirements

**FR-CRUD-001 [MUST]:** The system SHALL create a new trader record containing legal name, unique email address, designated role, and initial status upon administrator submission, within a single atomic transaction.

**FR-CRUD-002 [MUST]:** The system SHALL retrieve a trader's full profile — including name, email, role, status, creation timestamp, and a list of associated portfolio identifiers — given a valid `trader_id`.

**FR-CRUD-003 [MUST]:** The system SHALL update a trader's status to one of the permitted values (`ACTIVE`, `SUSPENDED`, `CLOSED`) without physically deleting the trader record; no row in the `traders` table shall ever be removed.

**FR-CRUD-004 [MUST]:** The system SHALL create a new asset record containing ticker symbol (≤ 10 characters), full instrument name, asset type (`STOCK`, `BOND`, `ETF`, `DERIVATIVE`), listing exchange, denomination currency, and initial reference price stored as `DECIMAL(15,4)`.

**FR-CRUD-005 [MUST]:** The system SHALL retrieve a complete asset record — including ticker, asset type, exchange, current reference price, and active status — given a valid `asset_id` or ticker symbol.

**FR-CRUD-006 [MUST]:** The system SHALL deactivate an asset by setting `is_active = FALSE`; no asset row shall be physically deleted, thereby preserving the referential integrity of all historical orders and positions that reference the asset.

**FR-CRUD-007 [MUST]:** The system SHALL create a new portfolio record containing portfolio name and owning trader reference upon trader or administrator request, and SHALL automatically associate the portfolio with the owning trader.

**FR-CRUD-008 [MUST]:** The system SHALL retrieve a portfolio record including portfolio name, owning trader identifier, and all associated position records, given a valid `portfolio_id`.

**FR-CRUD-009 [SHOULD]:** The system SHALL permit a portfolio's display name to be updated by the owning trader or an administrator; no portfolio record shall be physically deleted while any active position or historical order references it.

**FR-CRUD-010 [MUST]:** The system SHALL create a new order record containing trader reference, asset reference, portfolio reference, side (`BUY` or `SELL`), order type (`MARKET`, `LIMIT`, `STOP`, or `STOP_LIMIT`), requested quantity, and — for LIMIT/STOP_LIMIT orders — limit price, with `order_status` initialised to `PENDING` and `filled_quantity` initialised to zero.

**FR-CRUD-011 [MUST]:** The system SHALL retrieve a complete order record including all submitted fields, current status, filled quantity, and creation and last-updated timestamps, given a valid `order_id`.

**FR-CRUD-012 [MUST]:** The system SHALL cancel an order by updating `status = 'CANCELLED'` within a locked transaction; no order row shall ever be physically deleted, preserving the complete order lifecycle history for audit purposes.

**FR-CRUD-013 [MUST]:** The system SHALL create a new position record for a portfolio–asset pair upon the first execution against that asset in that portfolio; if a position record already exists, the system SHALL update the existing row's `quantity` and `average_cost` in place rather than inserting a duplicate row.

**FR-CRUD-014 [MUST]:** The system SHALL retrieve all current position records for a specified portfolio, returning asset ticker, net quantity held, average cost per unit as `DECIMAL(15,4)`, and the timestamp of the most recent update.

**FR-CRUD-015 [MUST]:** The system SHALL update a position's `quantity` and `average_cost` atomically within the same database transaction that records the corresponding order execution, ensuring that the position state is never observable in a partially updated form.

**FR-CRUD-016 [MUST]:** The system SHALL insert new accounting ledger entries exclusively as paired DEBIT and CREDIT records within a single transaction; no `UPDATE` or `DELETE` operation shall be permitted on any row in the `accounting_ledgers` table under any operational circumstance.

**FR-CRUD-017 [MUST]:** The system SHALL retrieve accounting ledger entries filterable by date range, order reference, entry type (`DEBIT` / `CREDIT`), and account category, returning results in chronological order by `created_at`.

**FR-CRUD-018 [MUST]:** The system SHALL create a settlement record upon order execution, containing the linked `order_id`, trade price, quantity, gross amount, commission, net amount, calculated settlement date (T+2), and initial `settlement_status = 'PENDING'`.

**FR-CRUD-019 [MUST]:** The system SHALL retrieve settlement records filterable by `settlement_status` (`PENDING`, `SETTLED`, `FAILED`, `REVERSED`), settlement date range, and `order_id`, to support daily settlement workflow and exception management.

**FR-CRUD-020 [MUST]:** The system SHALL update a settlement record's status from `PENDING` to `SETTLED` or `FAILED` upon the occurrence of the corresponding settlement event; no settlement row shall be physically deleted.

---

### 8.2 Business Logic Requirements

**FR-BIZ-001 [MUST]:** The system SHALL validate that a trader's `trader_status = 'ACTIVE'` before accepting any order submission; orders submitted by traders with `trader_status = 'SUSPENDED'` or `'CLOSED'` SHALL be rejected with a descriptive error and no order record shall be created.

**FR-BIZ-002 [MUST]:** The system SHALL validate, under a `SELECT … FOR UPDATE` row-level lock on the relevant `positions` record, that the trader's current net position `quantity` is greater than or equal to the requested sell quantity before accepting a SELL order; an insufficient-quantity condition SHALL cause an immediate `ROLLBACK` and rejection with no order created.

**FR-BIZ-003 [MUST]:** The system SHALL calculate the updated average cost of a position following a BUY execution using the weighted-average cost methodology: `new_average_cost = ((prior_quantity × prior_average_cost) + (fill_quantity × execution_price)) / new_total_quantity`, with all intermediate and final values computed in `DECIMAL(15,4)` arithmetic.

**FR-BIZ-004 [MUST]:** The system SHALL post exactly two accounting ledger entries — one `DEBIT` and one `CREDIT` — for every financial event (order execution or cancellation reversal); the algebraic sum of the paired entry amounts SHALL equal exactly zero, enforcing the double-entry invariant as a mandatory database-level correctness criterion.

**FR-BIZ-005 [MUST]:** The system SHALL calculate the settlement date for every executed order as the execution date plus two calendar business days (T+2 convention), and SHALL store the result as a `DATE` column in the `settlements` table at the time the execution transaction is committed.

**FR-BIZ-006 [MUST]:** The system SHALL enforce the following order status lifecycle: an order SHALL be created with `order_status = 'PENDING'`; upon partial execution it SHALL transition to `'PARTIALLY_FILLED'`; upon complete execution it SHALL transition to `'FILLED'`; upon cancellation it SHALL transition to `'CANCELLED'`; upon validation failure it SHALL transition to `'REJECTED'`. No status transition outside this defined directed graph SHALL be permitted by any stored procedure or application code path.

**FR-BIZ-007 [MUST]:** The system SHALL acquire a `SELECT … FOR UPDATE` exclusive row-level lock on the `orders` record before evaluating its status during any cancellation or execution operation; this pessimistic lock SHALL be held for the duration of the enclosing transaction to prevent concurrent processes from simultaneously reading the same pre-transition status and causing double-processing or race conditions.

**FR-BIZ-008 [MUST]:** The system SHALL validate that the target asset's `is_active = TRUE` before accepting any order submission referencing that asset; orders against inactive or delisted assets SHALL be rejected with no order record created.

**FR-BIZ-009 [MUST]:** The system SHALL validate that the `portfolio_id` referenced in an order submission is owned by the submitting trader (i.e., `portfolios.trader_id = authenticated_trader_id`); orders referencing portfolios belonging to a different trader SHALL be rejected with an authorisation error.

**FR-BIZ-010 [MUST]:** The system SHALL validate that the `limit_price` for any LIMIT-type order is a `DECIMAL(15,4)` value strictly greater than zero; a zero, negative, or NULL limit price SHALL cause immediate rejection of the order with no record created.

**FR-BIZ-011 [MUST]:** The system SHALL support partial fills: when an execution event fills only a portion of an order's `quantity`, the system SHALL increment `filled_quantity` by the fill amount, transition `order_status` to `'PARTIALLY_FILLED'`, and retain the residual unfilled quantity against the original order record without creating a new order row.

**FR-BIZ-012 [MUST]:** The system SHALL wrap every financial write operation — comprising order status update, position quantity and average-cost update, accounting ledger posting, and settlement record creation — within a single `START TRANSACTION / COMMIT` block, with a `DECLARE EXIT HANDLER FOR SQLEXCEPTION` that issues `ROLLBACK` on any error, ensuring all-or-nothing atomicity across all affected tables.

---

### 8.3 Audit Requirements

**FR-AUD-001 [MUST]:** All `UPDATE` operations on `orders`, `positions`, `accounting_ledgers`, and `settlements` MUST be captured in corresponding `_history` tables via `AFTER UPDATE` database triggers.

**FR-AUD-002 [MUST]:** All `DELETE` operations on the above tables MUST be captured via `AFTER DELETE` triggers, recording the full before-image of the deleted row.

**FR-AUD-003 [MUST]:** History tables MUST be `INSERT`-ONLY — no application code, stored procedure, or database user (including `db_admin`) may issue `UPDATE` or `DELETE` statements against any `_history` or audit table.

**FR-AUD-004 [MUST]:** Each audit record MUST capture the full before-image of the modified or deleted row, a `DATETIME(6)` timestamp with microsecond precision reflecting the exact moment of the trigger execution, and the change type (`UPDATE` or `DELETE`).

**FR-AUD-005 [SHOULD]:** The `changed_by` column in each history table SHOULD be populated by the trigger using `CURRENT_USER()` at the time the trigger fires, recording the MySQL account responsible for the data modification.

---

### 8.4 Reporting Requirements

**FR-RPT-001 [MUST]:** The system SHALL provide a portfolio summary report that returns, for a given `portfolio_id`, each held asset's ticker symbol, net quantity, average cost, current market price, computed market value (`quantity × current_price`), and unrealised profit and loss (`(current_price − average_cost) × quantity`), with all arithmetic performed in `DECIMAL(15,4)`.

**FR-RPT-002 [MUST]:** The system SHALL provide a trade history report returning all executed orders for a specified trader or portfolio, filterable by asset, date range, and order side, and including execution price, fill quantity, commission, fees, and the associated settlement status for each record.

**FR-RPT-003 [SHOULD]:** The system SHALL provide a daily profit and loss report for a specified portfolio and date, computing realised P&L from positions closed on that date and unrealised P&L from open positions valued at the most recent available market price recorded in the `assets` table.

**FR-RPT-004 [MUST]:** The system SHALL provide an accounting ledger reconciliation report for a specified date range, grouping ledger entries by order reference, computing `SUM(amount)` per group using `DECIMAL(15,4)` arithmetic, and flagging as a double-entry integrity violation any group for which the sum is not equal to exactly zero.

**FR-RPT-005 [MUST]:** The system SHALL provide an audit trail report for a specified table name and date range, returning all history records including the full before-image, change type, `DATETIME(6)` timestamp, and `changed_by` user; access to this report SHALL be restricted to users holding the `auditor_role` or `db_admin` database role.

---

### 8.5 Security Requirements

**FR-SEC-001 [MUST]:** The system SHALL implement role-based access control using four distinct MySQL database roles: `trader_role` (DML on `traders`, `assets`, `portfolios`, `orders`, `positions`, and `settlements`; no access to `_history` tables); `auditor_role` (`SELECT`-only on all tables including `_history` tables; no DML); `system_role` (DML and stored procedure `EXECUTE` privileges on all operational tables; used exclusively by the Spring Boot application); and `db_admin` (DDL, `GRANT`, and full DML; restricted to database administration operations only).

**FR-SEC-002 [MUST]:** The system SHALL ensure that every modification to a core financial table (`orders`, `positions`, `accounting_ledgers`, `settlements`) is captured by a database-level `AFTER UPDATE` or `AFTER DELETE` trigger writing to the corresponding `_history` table; this audit capture SHALL be enforced at the InnoDB engine level and SHALL not be bypassable by any application code path or direct SQL session.

**FR-SEC-003 [MUST]:** The system SHALL enforce data isolation such that a user authenticated under `trader_role` can read and write only records associated with their own `trader_id`; access to order, position, and portfolio data belonging to other traders SHALL be prevented through stored procedure parameter validation and, where applicable, filtered view definitions.

**FR-SEC-004 [MUST]:** The Spring Boot application layer SHALL connect to the MySQL database exclusively using a credential granted the `system_role` database role; no application configuration file, environment variable, or connection pool definition SHALL reference or embed the `db_admin` credential.

**FR-SEC-005 [SHOULD]:** All MySQL user account passwords SHALL conform to a minimum complexity policy of at least 12 characters, including at least one uppercase letter, one lowercase letter, one digit, and one special character; password rotation and expiry SHOULD be enforced through MySQL account policy configuration (`ALTER USER … PASSWORD EXPIRE INTERVAL`) rather than within application code.

---

## Appendix A: Design Evolution Log

The table below records all discrepancies found during the reverse-sync audit
of documentation files (docs/01–04) against the implemented migrations (V1–V4,
source of truth). Each row identifies what the documentation originally stated,
what the migration actually implemented, and which document was corrected.

| # | Document | Section / Table | Original Doc Value | Actual V1–V4 Value | Fix Applied |
|---|----------|-----------------|--------------------|--------------------|-------------|
| 1 | 01-requirements | §3.2 Assets | ISIN column described | No `isin` column in V1 | Removed ISIN references |
| 2 | 01-requirements | §3.3 Portfolios | `base_currency` described | No `base_currency` in V1 | Removed base currency references |
| 3 | 01-requirements | §3.4 Orders | Status: NEW, PARTIAL | PENDING, PARTIALLY_FILLED, REJECTED | Updated status names |
| 4 | 01-requirements | §3.4 Orders | Types: LIMIT, MARKET, STOP | Also includes STOP_LIMIT | Added STOP_LIMIT |
| 5 | 01-requirements | §3.4 Orders | Missing columns | average_fill_price, cancelled_at, cancel_reason | Mentioned in entity description |
| 6 | 01-requirements | §3.6 Ledgers | Per-row DEBIT/CREDIT entry_type | Single-row debit_account/credit_account model | Rewrote paragraph |
| 7 | 01-requirements | §3.7 Settlements | counterparty reference | No counterparty column in V1 | Removed reference |
| 8 | 01-requirements | §3.7 Settlements | Status: PENDING, SETTLED, FAILED | Also includes REVERSED | Added REVERSED |
| 9 | 01-requirements | UC-001 | `name`, `role`, INACTIVE | first_name/last_name, trader_type, CLOSED | Fixed column and status names |
| 10 | 01-requirements | UC-002 | ISIN, EQUITY | No ISIN; STOCK not EQUITY | Fixed asset_type, removed ISIN |
| 11 | 01-requirements | UC-006 | status NEW/PARTIAL | order_status PENDING/PARTIALLY_FILLED | Fixed status names and column name |
| 12 | 01-requirements | §8.1 FR-CRUD | ISIN, base_currency, counterparty, INACTIVE | Not in V1 schema | Removed stale references |
| 13 | 01-requirements | §8.2 FR-BIZ | status NEW/PARTIAL, INACTIVE | PENDING/PARTIALLY_FILLED, CLOSED | Fixed status names |
| 14 | 02-er-diagram | traders | Missing phone, updated_at | V1 has both columns | Added to diagram |
| 15 | 02-er-diagram | assets | Missing is_active, updated_at | V1 has both columns | Added to diagram |
| 16 | 02-er-diagram | portfolios | `created_date` column | Not in V1 | Removed from diagram |
| 17 | 02-er-diagram | orders | Missing average_fill_price, cancelled_at, cancel_reason, updated_at | V1 has all four | Added to diagram |
| 18 | 02-er-diagram | accounting_ledgers | `date transaction_date`, `text description`, `varchar reference_type` | DATETIME(6), VARCHAR(255), ENUM | Fixed types |
| 19 | 02-er-diagram | all entities | Missing `updated_at` | V1 has on all tables | Added to all entities |
| 20 | 02-er-diagram | narrative | `PARTIAL` state | `PARTIALLY_FILLED` | Fixed status name |
| 21 | 03-normalization | traders summary | VARCHAR(100) names, INACTIVE | VARCHAR(50), CLOSED | Fixed sizes and ENUM |
| 22 | 03-normalization | exchanges table | Proposed as new table | Never implemented | Removed; added explanatory note |
| 23 | 03-normalization | assets summary | EQUITY, VARCHAR(200), exchange_id FK | STOCK, VARCHAR(150), exchange VARCHAR(50) | Fixed ENUM, size, restored exchange |
| 24 | 03-normalization | portfolios summary | created_date, VARCHAR(200) | No created_date, VARCHAR(100) | Removed column, fixed size |
| 25 | 03-normalization | orders summary | LIMIT/MARKET/STOP; NEW/PARTIAL | +STOP_LIMIT; PENDING/PARTIALLY_FILLED/REJECTED | Fixed ENUMs, added missing columns |
| 26 | 03-normalization | positions summary | current_value/unrealized_pnl removed | V1 retains them (Decision 5) | Restored with denormalization note |
| 27 | 03-normalization | accounting_ledgers summary | DATE, VARCHAR(100), TEXT | DATETIME(6), VARCHAR(50), VARCHAR(255) | Fixed types |
| 28 | 03-normalization | settlements summary | gross_amount/net_amount removed; missing REVERSED | V1 retains them (Decision 4); REVERSED in ENUM | Restored with note; added REVERSED |
| 29 | 04-logical-design | portfolios | `created_date DATE` + CHECK constraint | Column does not exist in V1 | Removed column and CHECK |
| 30 | 04-logical-design | accounting_ledgers | `description TEXT` | VARCHAR(255) in V1 | Changed to VARCHAR(255) |
| 31 | 04-logical-design | ledger_audit | `description TEXT` | V4 declares TEXT but V1 parent has VARCHAR(255) | Flagged cross-migration type mismatch |
| 32 | 04-logical-design | orders indexes | idx_orders_trader_status, idx_orders_asset_status, idx_orders_time | idx_orders_trader_date, idx_orders_asset, idx_orders_status | Corrected to match V2 |
| 33 | 04-logical-design | assets indexes | idx_assets_type, idx_assets_exchange listed | Not in V2 | Removed (not implemented) |
| 34 | 04-logical-design | traders indexes | idx_traders_status listed | Not in V2 | Removed (not implemented) |
| 35 | 04-logical-design | history table indexes | _order, _time suffixes | _order_id, _changed_at suffixes in V4 | Corrected to match V4 |
| 36 | 04-logical-design | ledger indexes | idx_ledger_ref, idx_ledger_debit, idx_ledger_credit | idx_ledger_reference only (+ idx_ledger_date) | Corrected to match V2 |
