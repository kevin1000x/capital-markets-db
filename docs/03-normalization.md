# Stage 3: Normalization Analysis — Capital Markets Trading Platform

---

## Introduction

This document performs a rigorous sequential normalization analysis of all seven
core entities defined in `docs/02-er-diagram.md`. Each table is evaluated against
First, Second, and Third Normal Form using formal functional dependency notation.
Where a normal form is violated, a corrective decomposition is specified and
justified. Where a violation is deliberately retained for practical reasons,
the trade-off is explicitly documented.

**Notation conventions used throughout:**
- `X → Y` denotes that attribute set X functionally determines attribute set Y.
- `{A, B} → C` denotes a composite determinant.
- PK = Primary Key; CK = Candidate Key; FK = Foreign Key.
- Prime attribute = any attribute that is a member of at least one candidate key.
- Non-prime attribute = any attribute that is not a member of any candidate key.

---

---

### Table: traders

**Proposed Attributes:**
`trader_id` (PK), `first_name`, `last_name`, `email` (UK), `trader_type`,
`trader_status`, `registration_date`, `created_at`

**Candidate Keys:** `{trader_id}`, `{email}`
**Prime Attributes:** `trader_id`, `email`
**Non-Prime Attributes:** `first_name`, `last_name`, `trader_type`,
`trader_status`, `registration_date`, `created_at`

**Functional Dependencies:**
- FD1: `trader_id → first_name, last_name, email, trader_type, trader_status, registration_date, created_at`
- FD2: `email → trader_id, first_name, last_name, trader_type, trader_status, registration_date, created_at`

**1NF Analysis:**
All attributes are single-valued and atomic. `first_name` and `last_name` are
stored as separate columns (no composite name field). Contact details such as
phone numbers are not stored in this table — they would belong in a separate
contacts table if required. Each row is uniquely identified by `trader_id`.
**This table satisfies 1NF.**

**2NF Analysis:**
The primary key is a single column (`trader_id`). By definition, a single-column
primary key cannot give rise to a partial dependency (partial dependencies require
a composite key where a non-key attribute depends on only part of the key).
**This table satisfies 2NF.**

**3NF Analysis:**
Checking for transitive dependencies (non-prime → non-prime):
- `trader_type` is an enumeration stored as a code value (`INDIVIDUAL`,
  `INSTITUTIONAL`). No `trader_type_description` column exists in this table;
  therefore, `trader_type` does not determine any other attribute here.
- `trader_status` (`ACTIVE`, `SUSPENDED`, `INACTIVE`) similarly carries no
  dependent description column.
- No non-prime attribute determines any other non-prime attribute.

**This table satisfies 3NF.**

**Summary Table:**

| Attribute | Depends On | Partial Dep? | Transitive Dep? | Action |
|-----------|------------|--------------|-----------------|--------|
| first_name | trader_id | No | No | Retain |
| last_name | trader_id | No | No | Retain |
| email | trader_id | No | No | Retain (CK) |
| trader_type | trader_id | No | No | Retain |
| trader_status | trader_id | No | No | Retain |
| registration_date | trader_id | No | No | Retain |
| created_at | trader_id | No | No | Retain |

---

### Table: assets

**Proposed Attributes:**
`asset_id` (PK), `ticker_symbol` (UK), `asset_name`, `asset_type`, `exchange`,
`currency`, `current_price`, `created_at`

**Candidate Keys:** `{asset_id}`, `{ticker_symbol}`
**Prime Attributes:** `asset_id`, `ticker_symbol`
**Non-Prime Attributes:** `asset_name`, `asset_type`, `exchange`, `currency`,
`current_price`, `created_at`

**Functional Dependencies:**
- FD1: `asset_id → ticker_symbol, asset_name, asset_type, exchange, currency, current_price, created_at`
- FD2: `ticker_symbol → asset_id, asset_name, asset_type, exchange, currency, current_price, created_at`
- FD3 (potential): `exchange → currency` — examined below.

**1NF Analysis:**
All attributes store single, atomic values. `exchange` stores a single exchange
code string (e.g., `'NYSE'`). No multi-valued attributes are present.
**This table satisfies 1NF.**

**2NF Analysis:**
Single-column primary key; partial dependencies are impossible by construction.
**This table satisfies 2NF.**

**3NF Analysis:**
The user-specified check is: does `exchange → exchange_country` (or any other
exchange-dependent attribute) exist within this table?

Examining the attribute set: no `exchange_country`, `exchange_timezone`, or any
other exchange-level attribute is stored in the `assets` table. The `exchange`
column holds only a varchar code. Therefore, no exchange-derived attribute is
present to create a transitive dependency.

The potential FD3 (`exchange → currency`) requires scrutiny. In the capital
markets domain, most assets traded on a given exchange are denominated in that
exchange's primary currency (NYSE → USD; LSE → GBP; TSE → JPY). However, this
is not a universal rule: American Depositary Receipts listed on NYSE may be
denominated in USD but represent foreign-currency assets; dual-listed securities
appear on multiple exchanges; cross-listed bonds carry their own denomination
currency independent of the listing exchange. Consequently, `currency` is a
property of the specific financial instrument, not a function of its exchange
alone. FD3 is not a valid functional dependency in general.

**No transitive dependencies exist. This table satisfies 3NF.**

**Design Note — exchange as VARCHAR:**
Although 3NF is satisfied, storing `exchange` as a plain VARCHAR introduces
two data integrity risks: (1) typographic inconsistency across rows
(`'NYSE'` vs `'Nyse'`), and (2) no referential validation against a controlled
set of valid exchanges. A separate `exchanges` lookup table with a FK reference
from `assets.exchange_id` would enforce consistency and allow exchange metadata
(country, timezone, currency) to be stored without denormalization. This
decomposition is **recommended** as a best practice and is adopted in the Final
Normalized Schema Summary below.

**Summary Table:**

| Attribute | Depends On | Partial Dep? | Transitive Dep? | Action |
|-----------|------------|--------------|-----------------|--------|
| ticker_symbol | asset_id | No | No | Retain (CK) |
| asset_name | asset_id | No | No | Retain |
| asset_type | asset_id | No | No | Retain |
| exchange | asset_id | No | No | Replace with exchange_id FK (recommended) |
| currency | asset_id | No | No | Retain |
| current_price | asset_id | No | No | Retain |
| created_at | asset_id | No | No | Retain |

---

### Table: portfolios

**Proposed Attributes:**
`portfolio_id` (PK), `trader_id` (FK), `portfolio_name`, `description`,
`created_date`, `created_at`

**Candidate Keys:** `{portfolio_id}`
**Prime Attributes:** `portfolio_id`
**Non-Prime Attributes:** `trader_id`, `portfolio_name`, `description`,
`created_date`, `created_at`

**Functional Dependencies:**
- FD1: `portfolio_id → trader_id, portfolio_name, description, created_date, created_at`

**1NF Analysis:**
All attributes are atomic and single-valued. A portfolio has exactly one owning
trader (`trader_id`); multiple portfolio names are not stored in a single column.
**This table satisfies 1NF.**

**2NF Analysis:**
Single-column primary key; no partial dependencies possible.
**This table satisfies 2NF.**

**3NF Analysis:**
- `trader_id` is a foreign key reference. Within this table, `trader_id` does not
  determine `portfolio_name` or any other attribute — the portfolio's name is an
  independent property of each portfolio row.
- No non-prime attribute transitively determines another non-prime attribute.

**This table satisfies 3NF.**

**Summary Table:**

| Attribute | Depends On | Partial Dep? | Transitive Dep? | Action |
|-----------|------------|--------------|-----------------|--------|
| trader_id | portfolio_id | No | No | Retain (FK) |
| portfolio_name | portfolio_id | No | No | Retain |
| description | portfolio_id | No | No | Retain |
| created_date | portfolio_id | No | No | Retain |
| created_at | portfolio_id | No | No | Retain |

---

### Table: orders

**Proposed Attributes:**
`order_id` (PK), `trader_id` (FK), `asset_id` (FK), `portfolio_id` (FK),
`order_type`, `order_side`, `quantity`, `limit_price`, `filled_quantity`,
`order_status`, `order_time`, `created_at`

**Candidate Keys:** `{order_id}`
**Prime Attributes:** `order_id`
**Non-Prime Attributes:** all remaining attributes

**Functional Dependencies:**
- FD1: `order_id → trader_id, asset_id, portfolio_id, order_type, order_side, quantity, limit_price, filled_quantity, order_status, order_time, created_at`
- FD2 (cross-table): `portfolio_id → trader_id` — a portfolio belongs to exactly one trader; this dependency holds in the domain even though `trader_id` appears as a direct column in `orders`.
- FD3 (conditional domain constraint): `order_type = 'MARKET' → limit_price IS NULL` — this is a domain rule, not a functional dependency among stored column values.

**1NF Analysis:**
All attributes are atomic. `order_status` stores a single status value at any
point in time; its lifecycle history is tracked in `order_history`, not within
this column. `quantity` and `filled_quantity` are separate atomic columns (no
arrays or composite fields).
**This table satisfies 1NF.**

**2NF Analysis:**
Single-column primary key; no partial dependencies possible.
**This table satisfies 2NF.**

**3NF Analysis:**

**Check 1 — order_type → order_type_description:**
The `order_type` column stores an enumeration code (`LIMIT`, `MARKET`, `STOP`).
No `order_type_description` or any other attribute derived from `order_type`
exists in this table. Therefore no transitive dependency arises from `order_type`.

If human-readable descriptions or additional type metadata were needed, an
`order_types` lookup table should be created and `order_type` converted to a FK.
In the current design, enum semantics are enforced at the application layer and
via CHECK constraints; no such decomposition is required.

**Check 2 — portfolio_id → trader_id (transitive dependency):**
FD2 establishes that `portfolio_id → trader_id` holds in the domain. Combined
with FD1 (`order_id → portfolio_id`), this creates a transitive chain:

`order_id → portfolio_id → trader_id`

This means `trader_id` in the `orders` table is transitively determined through
`portfolio_id`. Under strict 3NF, `trader_id` should be removed from `orders`
and derived by joining `orders → portfolios → trader_id` at query time.

**Decision: Documented denormalization — `trader_id` is retained in `orders`.**
Justification:
1. **Direct query performance**: filtering orders by trader requires no JOIN.
2. **Explicit audit record**: the submitting trader's identity is captured
   directly on the order record for auditing purposes.
3. **Constraint validation**: stored procedures verify `orders.trader_id =
   portfolios.trader_id` at order submission time, ensuring consistency.
4. **Future resilience**: if portfolio ownership were ever transferable, the
   order record would retain the original submitter's identity independently.

This denormalization is annotated in the schema with a comment and enforced
by stored procedure validation rather than a DB-level constraint.

**Check 3 — limit_price nullability:**
`limit_price` is NULL for MARKET-type orders. This is a conditional domain
constraint, not a functional dependency among non-key attributes, and does not
constitute a normal form violation.

**This table satisfies 3NF with one documented denormalization (trader_id).**

**Summary Table:**

| Attribute | Depends On | Partial Dep? | Transitive Dep? | Action |
|-----------|------------|--------------|-----------------|--------|
| trader_id | order_id (direct); also portfolio_id (transitive) | No | **Yes** | **Retained — documented denormalization** |
| asset_id | order_id | No | No | Retain (FK) |
| portfolio_id | order_id | No | No | Retain (FK) |
| order_type | order_id | No | No | Retain (enum) |
| order_side | order_id | No | No | Retain |
| quantity | order_id | No | No | Retain |
| limit_price | order_id | No | No | Retain (NULL for MARKET) |
| filled_quantity | order_id | No | No | Retain |
| order_status | order_id | No | No | Retain |
| order_time | order_id | No | No | Retain |
| created_at | order_id | No | No | Retain |

---

### Table: positions

**Proposed Attributes:**
`position_id` (PK), `portfolio_id` (FK), `asset_id` (FK), `quantity`,
`average_cost`, `current_value`, `unrealized_pnl`, `created_at`

**Candidate Keys:**
- `{position_id}` (surrogate PK)
- `{portfolio_id, asset_id}` (natural CK, enforced by UNIQUE constraint)

**Prime Attributes:** `position_id`, `portfolio_id`, `asset_id`
**Non-Prime Attributes:** `quantity`, `average_cost`, `current_value`,
`unrealized_pnl`, `created_at`

**Functional Dependencies:**
- FD1: `position_id → portfolio_id, asset_id, quantity, average_cost, current_value, unrealized_pnl, created_at`
- FD2: `{portfolio_id, asset_id} → position_id, quantity, average_cost, current_value, unrealized_pnl` (natural CK)
- FD3 (cross-table derived): `current_value ≈ quantity × assets.current_price`
- FD4 (cross-table derived): `unrealized_pnl ≈ (assets.current_price − average_cost) × quantity`

**1NF Analysis:**
All attributes are atomic and single-valued. The unique constraint on
`(portfolio_id, asset_id)` ensures that each portfolio-asset pair has at most
one position row — there are no repeating groups within a single row.
**This table satisfies 1NF.**

**2NF Analysis:**
With surrogate PK `position_id` (single column): no partial dependencies
are possible. With natural CK `{portfolio_id, asset_id}`: every non-prime
attribute (`quantity`, `average_cost`, `current_value`, `unrealized_pnl`)
depends on the complete composite key, not a subset of it. Quantity and cost
are properties of the specific portfolio-asset holding, not of the portfolio
or asset alone.
**This table satisfies 2NF under both candidate keys.**

**3NF Analysis:**

Within the `positions` table, examining non-prime → non-prime dependencies:
- Does `quantity → current_value`? **No.** `current_value` = `quantity × current_price`, but `current_price` is stored in `assets`, not in `positions`. This formula cannot be evaluated using only columns within `positions`.
- Does `{quantity, average_cost} → unrealized_pnl`? **No.** `unrealized_pnl = (current_price − average_cost) × quantity` also requires `current_price` from `assets`.

Because both derivations require a value from an external table (`assets.current_price`), there is no intra-table functional dependency from non-key attributes to `current_value` or `unrealized_pnl`. Formally, no transitive dependency exists within the relation.

**This table satisfies 3NF under the strict intra-table definition.**

**Cross-Table Derivation Anomaly (documented design concern):**
Although 3NF is not violated, `current_value` and `unrealized_pnl` introduce a
**staleness anomaly**: whenever `assets.current_price` is updated, every
`positions` row referencing that asset must also be updated to keep these columns
current. This creates an O(N) update cascade for every market price change.

Strict relational design would eliminate these columns and compute them at query
time via a view:

```sql
-- Normalized view (no stored current_value or unrealized_pnl):
SELECT p.position_id, p.portfolio_id, p.asset_id,
       p.quantity, p.average_cost,
       p.quantity * a.current_price                            AS current_value,
       (a.current_price - p.average_cost) * p.quantity        AS unrealized_pnl
FROM positions p
JOIN assets a ON p.asset_id = a.asset_id;
```

**Decision: `current_value` and `unrealized_pnl` are removed from the normalized
physical schema.** They are surfaced through the `v_portfolio_summary` view.
This elimination is adopted in the Final Normalized Schema Summary.

**Summary Table:**

| Attribute | Depends On | Partial Dep? | Transitive Dep? | Action |
|-----------|------------|--------------|-----------------|--------|
| portfolio_id | position_id | No | No | Retain (FK, part of natural CK) |
| asset_id | position_id | No | No | Retain (FK, part of natural CK) |
| quantity | position_id | No | No | Retain |
| average_cost | position_id | No | No | Retain |
| current_value | position_id (via cross-table derivation) | No | No (cross-table) | **Remove — computed in view** |
| unrealized_pnl | position_id (via cross-table derivation) | No | No (cross-table) | **Remove — computed in view** |
| created_at | position_id | No | No | Retain |

---

### Table: accounting_ledgers

**Proposed Attributes:**
`ledger_id` (PK), `transaction_date`, `debit_account`, `credit_account`,
`amount`, `reference_type`, `reference_id`, `description`, `created_at`

**Candidate Keys:** `{ledger_id}`
**Prime Attributes:** `ledger_id`
**Non-Prime Attributes:** all remaining attributes

**Functional Dependencies:**
- FD1: `ledger_id → transaction_date, debit_account, credit_account, amount, reference_type, reference_id, description, created_at`
- FD2 (soft domain constraint): `reference_type ∈ {'ORDER', 'SETTLEMENT', 'ADJUSTMENT'}` — constrains the valid domain of `reference_type` but is not a functional dependency between stored column values.
- FD3 (domain semantics): `reference_type` constrains the semantic interpretation of `reference_id`; it does not determine the *value* of `reference_id`.

**1NF Analysis:**
All attributes are atomic. `reference_id` stores a single BIGINT value per row;
there are no multi-valued fields. The debit and credit sides of a journal entry
are stored as separate rows (one DEBIT row, one CREDIT row per event), not as a
composite field within a single row.
**This table satisfies 1NF.**

**2NF Analysis:**
Single-column primary key; no partial dependencies possible.
**This table satisfies 2NF.**

**3NF Analysis:**

**Check — reference_type → [any other non-key attribute]:**
`reference_type` constrains the semantic domain of `reference_id` (i.e., when
`reference_type = 'ORDER'`, `reference_id` should be a valid `order_id`). However,
`reference_type` does not functionally determine the *value* of `reference_id` or
any other attribute in the table. Different rows with `reference_type = 'ORDER'`
will have different `reference_id` values (different order IDs). No non-key
attribute determines another non-key attribute.

**This table satisfies 3NF.**

---

**In-Depth Analysis: The Polymorphic Reference Pattern**

The `{reference_type, reference_id}` pair implements a **polymorphic association**:
a single foreign-key-like column (`reference_id`) points to different parent
tables depending on the discriminator column (`reference_type`). This pattern
achieves extensibility at the cost of referential integrity enforcement.

| reference_type | reference_id refers to | FK constraint possible? |
|----------------|------------------------|------------------------|
| `'ORDER'` | `orders.order_id` | No — target table varies |
| `'SETTLEMENT'` | `settlements.settlement_id` | No — target table varies |
| `'ADJUSTMENT'` | Internal reference (no parent table) | No |

**Does this pattern violate any normal form?**
No. The formal definitions of 1NF, 2NF, and 3NF concern functional dependencies
among attribute values within a relation. The polymorphic pattern is a
**referential integrity** concern — it prevents the declaration of a standard
`FOREIGN KEY` constraint — not a data dependency concern. The normal forms are
satisfied; the issue is that the RDBMS cannot enforce `reference_id` validity
automatically.

**Trade-off analysis:**

| Criterion | Polymorphic pattern | Alternative A: separate ledger tables | Alternative B: nullable FK columns |
|-----------|--------------------|-----------------------------------------|-----------------------------------|
| Schema simplicity | High — one table | Low — three tables | Medium — one table |
| FK enforcement | None (application-enforced) | Full | Full (exactly-one-non-null constraint) |
| JOIN complexity | Requires `WHERE reference_type = ?` | Simple per-type JOIN | Requires COALESCE across columns |
| Extensibility | Add new type with no DDL change | DDL change required per new type | DDL change required per new column |
| Report (all events) | Single `SELECT` | `UNION` across tables | Single `SELECT` |
| 3NF compliance | Satisfied | Satisfied | Satisfied |

**Decision: the polymorphic pattern is retained.** Referential integrity is
enforced within the `sp_execute_trade`, `sp_cancel_order` stored procedures,
which validate `reference_id` before inserting ledger entries. This choice is
pragmatic for an academic prototype; a production system might prefer Alternative
B (nullable FK columns) for database-enforced integrity.

**Summary Table:**

| Attribute | Depends On | Partial Dep? | Transitive Dep? | Action |
|-----------|------------|--------------|-----------------|--------|
| transaction_date | ledger_id | No | No | Retain |
| debit_account | ledger_id | No | No | Retain |
| credit_account | ledger_id | No | No | Retain |
| amount | ledger_id | No | No | Retain |
| reference_type | ledger_id | No | No | Retain |
| reference_id | ledger_id | No | No | Retain (polymorphic FK, application-enforced) |
| description | ledger_id | No | No | Retain |
| created_at | ledger_id | No | No | Retain |

---

### Table: settlements

**Proposed Attributes:**
`settlement_id` (PK), `order_id` (FK, UK), `trade_price`, `quantity`,
`gross_amount`, `commission`, `net_amount`, `settlement_date`,
`settlement_status`, `created_at`

**Candidate Keys:** `{settlement_id}`, `{order_id}` (each order has at most one settlement)
**Prime Attributes:** `settlement_id`, `order_id`
**Non-Prime Attributes:** `trade_price`, `quantity`, `gross_amount`, `commission`,
`net_amount`, `settlement_date`, `settlement_status`, `created_at`

**Functional Dependencies:**
- FD1: `settlement_id → order_id, trade_price, quantity, gross_amount, commission, net_amount, settlement_date, settlement_status, created_at`
- FD2: `order_id → settlement_id, trade_price, quantity, gross_amount, commission, net_amount, settlement_date, settlement_status, created_at` (order_id is a CK — each order has at most one settlement)
- **FD3: `{trade_price, quantity} → gross_amount`** — in the simplified model where `gross_amount = trade_price × quantity`.
- **FD4: `{gross_amount, commission} → net_amount`** — where `net_amount = gross_amount − commission`.

**1NF Analysis:**
All attributes are atomic. `settlement_status` holds a single status value
(`PENDING`, `SETTLED`, `FAILED`). No repeating groups are present.
**This table satisfies 1NF.**

**2NF Analysis:**
Using surrogate PK `settlement_id` (single column): no partial dependencies
are possible. Using natural CK `{order_id}` (also single column): same result.
**This table satisfies 2NF.**

**3NF Analysis:**

**FD3 — `{trade_price, quantity} → gross_amount` (3NF VIOLATION):**

Under the model where `gross_amount = trade_price × quantity`:
- `trade_price` is a non-prime attribute.
- `quantity` is a non-prime attribute.
- `gross_amount` is a non-prime attribute.
- A set of non-prime attributes determines another non-prime attribute.

By the formal definition of 3NF ("for every non-trivial FD X → A, either X is
a superkey or A is a prime attribute"), this dependency violates 3NF because
`{trade_price, quantity}` is not a superkey and `gross_amount` is not a prime
attribute.

**FD4 — `{gross_amount, commission} → net_amount` (3NF VIOLATION):**

Similarly:
- `gross_amount` and `commission` are non-prime attributes.
- `net_amount` is a non-prime attribute.
- Non-prime attributes determine another non-prime attribute → 3NF violation.

**Strict 3NF decomposition:**

To eliminate both violations, `gross_amount` and `net_amount` are removed from
the stored schema. They are computed at query time:

```sql
-- gross_amount and net_amount derived at query time:
SELECT settlement_id, order_id, trade_price, quantity, commission,
       settlement_date, settlement_status,
       trade_price * quantity                    AS gross_amount,
       trade_price * quantity - commission       AS net_amount
FROM settlements;
```

The normalized `settlements` table retains only:
`settlement_id`, `order_id`, `trade_price`, `quantity`, `commission`,
`settlement_date`, `settlement_status`, `created_at`

**Decision: gross_amount and net_amount are removed from the stored schema.**

This does not preclude their appearance in application output; the
`v_settlement_summary` view computes them on-the-fly. If financial regulation
requires that the exact computed amounts be preserved as an immutable record
(e.g., for post-trade reporting), they may be re-introduced as a documented
denormalization with an explicit annotation in the physical design document.

**Summary Table:**

| Attribute | Depends On | Partial Dep? | Transitive Dep? | Action |
|-----------|------------|--------------|-----------------|--------|
| order_id | settlement_id | No | No | Retain (FK, CK) |
| trade_price | settlement_id | No | No | Retain |
| quantity | settlement_id | No | No | Retain |
| gross_amount | settlement_id; also {trade_price, quantity} | No | **Yes** | **Remove — computed in view** |
| commission | settlement_id | No | No | Retain |
| net_amount | settlement_id; also {gross_amount, commission} | No | **Yes** | **Remove — computed in view** |
| settlement_date | settlement_id | No | No | Retain |
| settlement_status | settlement_id | No | No | Retain |
| created_at | settlement_id | No | No | Retain |

---

## Normal Form Results Summary

| Table | 1NF | 2NF | 3NF | Violations / Notes |
|-------|-----|-----|-----|--------------------|
| traders | ✅ | ✅ | ✅ | Fully normalized |
| assets | ✅ | ✅ | ✅ | exchange VARCHAR → recommend exchanges FK (best practice) |
| portfolios | ✅ | ✅ | ✅ | Fully normalized |
| orders | ✅ | ✅ | ⚠️ | trader_id transitively dependent via portfolio_id — documented denormalization retained |
| positions | ✅ | ✅ | ✅ | current_value, unrealized_pnl removed (cross-table derivation anomaly) |
| accounting_ledgers | ✅ | ✅ | ✅ | Polymorphic reference_type/reference_id — referential integrity concern, not NF violation |
| settlements | ✅ | ✅ | ❌ | gross_amount and net_amount violate 3NF — **removed** from stored schema |

---

## Final Normalized Schema Summary

This section consolidates the output of the normalization analysis. It supersedes
the ER diagram attribute lists where corrections have been applied and serves as
the direct input to Stage 4 (Logical Design).

---

### traders
**Primary Key:** `trader_id`
**Candidate Keys:** `trader_id`, `email`
| Column | Type | Constraint |
|--------|------|------------|
| trader_id | BIGINT | PK, AUTO_INCREMENT |
| first_name | VARCHAR(50) | NOT NULL |
| last_name | VARCHAR(50) | NOT NULL |
| email | VARCHAR(100) | NOT NULL, UNIQUE |
| phone | VARCHAR(20) | NULL |
| trader_type | ENUM('INDIVIDUAL','INSTITUTIONAL') | NOT NULL |
| trader_status | ENUM('ACTIVE','SUSPENDED','CLOSED') | NOT NULL DEFAULT 'ACTIVE' |
| registration_date | DATE | NOT NULL |
| created_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP |
| updated_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP |

*Change from ER diagram: name column sizes reduced to VARCHAR(50) to match V1 implementation; phone added; INACTIVE status replaced by CLOSED; updated_at added.*

---

### ~~exchanges~~ *(proposed but not implemented)*

> **Design note:** The 3NF analysis above recommended decomposing
> `assets.exchange` into a separate `exchanges` lookup table with an
> `exchange_id` FK. This decomposition was intentionally **not implemented**
> in V1. The `assets` table retains `exchange VARCHAR(50)` as a deliberate
> denormalization to keep the schema simpler for the academic prototype scope.
> See Design Decisions §4.3 in the logical design document for rationale.

---

### assets
**Primary Key:** `asset_id`
**Candidate Keys:** `asset_id`, `ticker_symbol`
| Column | Type | Constraint |
|--------|------|------------|
| asset_id | BIGINT | PK, AUTO_INCREMENT |
| ticker_symbol | VARCHAR(10) | NOT NULL, UNIQUE |
| asset_name | VARCHAR(150) | NOT NULL |
| asset_type | ENUM('STOCK','BOND','ETF','DERIVATIVE') | NOT NULL |
| exchange | VARCHAR(50) | NOT NULL *(retained as VARCHAR — exchanges table not implemented; see note above)* |
| currency | VARCHAR(3) | NOT NULL DEFAULT 'USD' |
| current_price | DECIMAL(15,4) | NOT NULL, CHECK >= 0 |
| is_active | TINYINT(1) | NOT NULL DEFAULT 1 |
| created_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP |
| updated_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP |

*Change from ER diagram: asset_name size reduced to VARCHAR(150); EQUITY renamed
to STOCK; exchange retained as VARCHAR(50) (exchanges table not implemented);
is_active and updated_at added.*

---

### portfolios
**Primary Key:** `portfolio_id`
| Column | Type | Constraint |
|--------|------|------------|
| portfolio_id | BIGINT | PK, AUTO_INCREMENT |
| trader_id | BIGINT | NOT NULL, FK → traders.trader_id |
| portfolio_name | VARCHAR(100) | NOT NULL |
| description | TEXT | NULL |
| created_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP |
| updated_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP |

*Change from ER diagram: created_date removed (not in V1 implementation);
portfolio_name size reduced to VARCHAR(100); updated_at added.*

---

### orders
**Primary Key:** `order_id`
| Column | Type | Constraint |
|--------|------|------------|
| order_id | BIGINT | PK, AUTO_INCREMENT |
| trader_id | BIGINT | NOT NULL, FK → traders.trader_id *(denormalization — see 3NF analysis)* |
| asset_id | BIGINT | NOT NULL, FK → assets.asset_id |
| portfolio_id | BIGINT | NOT NULL, FK → portfolios.portfolio_id |
| order_type | ENUM('MARKET','LIMIT','STOP','STOP_LIMIT') | NOT NULL |
| order_side | ENUM('BUY','SELL') | NOT NULL |
| quantity | INT | NOT NULL, CHECK > 0 |
| limit_price | DECIMAL(15,4) | NULL *(NULL for MARKET orders)*, CHECK > 0 when NOT NULL |
| filled_quantity | INT | NOT NULL DEFAULT 0, CHECK >= 0 |
| average_fill_price | DECIMAL(15,4) | NULL |
| order_status | ENUM('PENDING','PARTIALLY_FILLED','FILLED','CANCELLED','REJECTED') | NOT NULL DEFAULT 'PENDING' |
| order_time | DATETIME(6) | NOT NULL DEFAULT CURRENT_TIMESTAMP(6) |
| cancelled_at | DATETIME | NULL |
| cancel_reason | VARCHAR(255) | NULL |
| created_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP |
| updated_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP |

*Change from ER diagram: trader_id retained with documented 3NF denormalization;
STOP_LIMIT added to order_type; status values updated to PENDING/PARTIALLY_FILLED/
FILLED/CANCELLED/REJECTED; average_fill_price, cancelled_at, cancel_reason, and
updated_at added.*

---

### positions
**Primary Key:** `position_id`
**Candidate Keys:** `position_id`, `{portfolio_id, asset_id}`
| Column | Type | Constraint |
|--------|------|------------|
| position_id | BIGINT | PK, AUTO_INCREMENT |
| portfolio_id | BIGINT | NOT NULL, FK → portfolios.portfolio_id |
| asset_id | BIGINT | NOT NULL, FK → assets.asset_id |
| quantity | INT | NOT NULL DEFAULT 0, CHECK >= 0 |
| average_cost | DECIMAL(15,4) | NOT NULL DEFAULT 0.0000, CHECK >= 0 |
| current_value | DECIMAL(15,4) | NOT NULL DEFAULT 0.0000 *(denormalization — see Decision 5 in §4.3)* |
| unrealized_pnl | DECIMAL(15,4) | NOT NULL DEFAULT 0.0000 *(denormalization — see Decision 5 in §4.3)* |
| created_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP |
| updated_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP |
| UNIQUE | — | (portfolio_id, asset_id) |

*Change from ER diagram: the 3NF analysis recommended removing `current_value`
and `unrealized_pnl` (cross-table derivation anomaly). The V1 implementation
retains them as intentional denormalization for dashboard query performance
(Decision 5, §4.3). They are refreshed atomically by stored procedure on each
fill event. updated_at added.*

---

### accounting_ledgers
**Primary Key:** `ledger_id`
| Column | Type | Constraint |
|--------|------|------------|
| ledger_id | BIGINT | PK, AUTO_INCREMENT |
| transaction_date | DATETIME(6) | NOT NULL DEFAULT CURRENT_TIMESTAMP(6) |
| debit_account | VARCHAR(50) | NOT NULL |
| credit_account | VARCHAR(50) | NOT NULL |
| amount | DECIMAL(15,4) | NOT NULL, CHECK > 0 |
| reference_type | ENUM('ORDER','SETTLEMENT','ADJUSTMENT') | NOT NULL |
| reference_id | BIGINT | NOT NULL |
| description | VARCHAR(255) | NULL |
| created_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP |
| updated_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP |

*Change from ER diagram: `transaction_date` changed from DATE to DATETIME(6)
to correlate with microsecond-precision order timestamps; account columns
reduced to VARCHAR(50); `description` changed from TEXT to VARCHAR(255);
`reference_type` promoted from VARCHAR to ENUM; updated_at added.*

---

### settlements
**Primary Key:** `settlement_id`
**Candidate Keys:** `settlement_id`, `order_id`
| Column | Type | Constraint |
|--------|------|------------|
| settlement_id | BIGINT | PK, AUTO_INCREMENT |
| order_id | BIGINT | NOT NULL, UNIQUE, FK → orders.order_id |
| trade_price | DECIMAL(15,4) | NOT NULL, CHECK > 0 |
| quantity | INT | NOT NULL, CHECK > 0 |
| gross_amount | DECIMAL(15,4) | NOT NULL, CHECK > 0 *(denormalization — see Decision 4 in §4.3)* |
| commission | DECIMAL(15,4) | NOT NULL DEFAULT 9.9900, CHECK >= 0 |
| net_amount | DECIMAL(15,4) | NOT NULL *(denormalization — see Decision 4 in §4.3)* |
| settlement_date | DATE | NOT NULL |
| settlement_status | ENUM('PENDING','SETTLED','FAILED','REVERSED') | NOT NULL DEFAULT 'PENDING' |
| created_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP |
| updated_at | DATETIME | NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP |

*Change from ER diagram: the 3NF analysis recommended removing `gross_amount`
and `net_amount` (non-prime → non-prime FD violations). The V1 implementation
retains them as intentional denormalization for settlement reporting and
regulatory immutability (Decision 4, §4.3). A stored procedure enforces
consistency at write time. REVERSED status added; commission default set to
9.9900; updated_at added.*

---

### Audit History Tables *(unchanged from ER diagram)*

The four audit history tables (`order_history`, `position_history`,
`ledger_audit`, `settlement_history`) mirror the before-image of their parent
tables at the moment of each UPDATE or DELETE event. Their structure is
determined by the trigger definitions rather than by normalization analysis of
business data; each history row is identified by `history_id` (PK) and records
all parent columns plus `change_type` and `changed_at`. No normalization changes
are required for these tables.
