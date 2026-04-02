# Stage 2: Entity-Relationship Diagram — Capital Markets Trading Platform

---

## 2.1 Entity-Relationship Diagram

```mermaid
erDiagram

    traders {
        bigint   trader_id         PK
        varchar  first_name
        varchar  last_name
        varchar  email             UK
        varchar  phone
        enum     trader_type
        enum     trader_status
        date     registration_date
        datetime created_at
        datetime updated_at
    }

    assets {
        bigint   asset_id          PK
        varchar  ticker_symbol     UK
        varchar  asset_name
        enum     asset_type
        varchar  exchange
        varchar  currency
        decimal  current_price        "DECIMAL(15,4)"
        tinyint  is_active
        datetime created_at
        datetime updated_at
    }

    portfolios {
        bigint   portfolio_id      PK
        bigint   trader_id         FK
        varchar  portfolio_name
        text     description
        datetime created_at
        datetime updated_at
    }

    orders {
        bigint   order_id          PK
        bigint   trader_id         FK
        bigint   asset_id          FK
        bigint   portfolio_id      FK
        enum     order_type
        enum     order_side
        int      quantity
        decimal  limit_price          "DECIMAL(15,4)"
        int      filled_quantity
        decimal  average_fill_price   "DECIMAL(15,4)"
        enum     order_status
        datetime order_time           "DATETIME(6)"
        datetime cancelled_at
        varchar  cancel_reason
        datetime created_at
        datetime updated_at
    }

    positions {
        bigint   position_id       PK
        bigint   portfolio_id      FK
        bigint   asset_id          FK
        int      quantity
        decimal  average_cost         "DECIMAL(15,4)"
        decimal  current_value        "DECIMAL(15,4)"
        decimal  unrealized_pnl       "DECIMAL(15,4)"
        datetime created_at
        datetime updated_at
    }

    accounting_ledgers {
        bigint   ledger_id         PK
        datetime transaction_date     "DATETIME(6)"
        varchar  debit_account
        varchar  credit_account
        decimal  amount               "DECIMAL(15,4)"
        enum     reference_type
        bigint   reference_id
        varchar  description
        datetime created_at
        datetime updated_at
    }

    settlements {
        bigint   settlement_id     PK
        bigint   order_id          FK
        decimal  trade_price          "DECIMAL(15,4)"
        int      quantity
        decimal  gross_amount         "DECIMAL(15,4)"
        decimal  commission           "DECIMAL(15,4)"
        decimal  net_amount           "DECIMAL(15,4)"
        date     settlement_date
        enum     settlement_status
        datetime created_at
        datetime updated_at
    }

    order_history {
        bigint   history_id        PK
        bigint   order_id          FK
        enum     change_type
        datetime changed_at           "DATETIME(6)"
        varchar  changed_by
        enum     order_status
        int      filled_quantity
        datetime updated_at
    }

    position_history {
        bigint   history_id        PK
        bigint   position_id       FK
        enum     change_type
        datetime changed_at           "DATETIME(6)"
        varchar  changed_by
        int      quantity
        decimal  average_cost         "DECIMAL(15,4)"
        datetime updated_at
    }

    ledger_audit {
        bigint   history_id        PK
        bigint   ledger_id         FK
        enum     change_type
        datetime changed_at           "DATETIME(6)"
        varchar  changed_by
        decimal  amount               "DECIMAL(15,4)"
        enum     reference_type
        datetime updated_at
    }

    settlement_history {
        bigint   history_id        PK
        bigint   settlement_id     FK
        enum     change_type
        datetime changed_at           "DATETIME(6)"
        varchar  changed_by
        enum     settlement_status
        decimal  net_amount           "DECIMAL(15,4)"
        datetime updated_at
    }

    traders            ||--o{ portfolios         : "owns (1:N)"
    traders            ||--o{ orders             : "places (1:N)"
    portfolios         ||--o{ positions          : "contains (1:N)"
    portfolios         ||--o{ orders             : "associated with (1:N)"
    assets             ||--o{ positions          : "held in (1:N)"
    assets             ||--o{ orders             : "ordered for (1:N)"
    orders             ||--o| settlements        : "settles to (1:0..1)"
    orders             ||--o{ order_history      : "audited by (1:N)"
    positions          ||--o{ position_history   : "audited by (1:N)"
    accounting_ledgers ||--o{ ledger_audit       : "audited by (1:N)"
    settlements        ||--o{ settlement_history : "audited by (1:N)"
```

---

## 2.2 Relationship Narrative

**Core One-to-Many Relationships.** A trader may own many portfolios, each
representing a distinct investment mandate; every portfolio belongs to exactly
one trader. Traders may place many orders over their lifecycle; each order is
attributed to its single submitting trader. Portfolios contain many positions —
one per asset, uniquely constrained on `(portfolio_id, asset_id)` — and are
referenced by many orders, routing execution updates to the correct holdings
set. Assets appear across many positions and many orders; each position and
order references exactly one asset. All 1:N relationships are enforced by
foreign key constraints with `ON DELETE RESTRICT`, preventing removal of parent
rows still referenced by child records.

**Optional One-to-Zero-or-One: orders → settlements.** A settlement record is
created only upon order execution (`FILLED` or `PARTIALLY_FILLED` state); orders in
status `PENDING` or `CANCELLED` carry no associated settlement record. The
cardinality notation `||--o|` expresses this precisely: every settlement has
exactly one parent order (mandatory left side), but an order may have zero or
one settlement record (optional right side). This faithfully models the T+2
workflow, where settlement obligations arise only after execution, not at order
submission.

**Polymorphic Reference in accounting_ledgers.** The `reference_type` (VARCHAR)
and `reference_id` (BIGINT) columns together implement a polymorphic association
pattern: `reference_type = 'ORDER'` links the entry to `orders.order_id`;
`reference_type = 'SETTLEMENT'` links it to `settlements.settlement_id`;
`reference_type = 'ADJUSTMENT'` captures manual corrections outside the
automated workflow. Because the referenced entity type varies at runtime, no
database-level foreign key constraint can be declared for this column pair —
referential integrity is enforced within stored procedure logic instead. This
design eliminates multiple nullable FK columns and keeps the ledger extensible
for future event types without schema alteration.

**Trigger-Based, INSERT-Only Audit Tables.** The four history tables are
populated exclusively by `AFTER UPDATE` and `AFTER DELETE` database triggers on
their respective parent tables (FR-AUD-001, FR-AUD-002). Enforcing audit capture
at the InnoDB engine level ensures every modification is recorded regardless of
whether it originates from the application layer, a stored procedure, or a
direct administrative session — sources that application-level logging cannot
guarantee to intercept. No database role is granted `UPDATE` or `DELETE`
privileges on any history table (FR-AUD-003), rendering each audit row immutable
from the moment of insertion and producing a tamper-evident, append-only journal
that meets compliance and evidentiary audit requirements.
