# Security Design — Role-Based Access Control

## Permission Matrix

### Table 1: Core Tables

| Role | traders | assets | portfolios | orders | positions | accounting_ledgers | settlements |
|------|---------|--------|------------|--------|-----------|-------------------|-------------|
| **db_admin** | ALL | ALL | ALL | ALL | ALL | ALL | ALL |
| **trader_role** | — | ✓ SELECT | — | — | — | — | — |
| **auditor_role** | ✓ SELECT | ✓ SELECT | ✓ SELECT | ✓ SELECT | ✓ SELECT | ✓ SELECT | ✓ SELECT |
| **system_role** | ✓ SELECT | ✓ SELECT | ✓ SELECT | ✓ S/I/U | ✓ S/I/U | ✓ S/I | ✓ S/I/U |

> S = SELECT, I = INSERT, U = UPDATE. No role except db_admin has DELETE on any table.
> accounting_ledgers: system_role has SELECT + INSERT only (append-only enforcement).
> History tables (order_history, position_history, ledger_audit, settlement_history): only db_admin and auditor_role have access. system_role has no grants — triggers write using DEFINER privileges.

### Table 2: Views and Stored Procedures

| Role | vw_portfolio_summary | vw_active_orders | vw_daily_settlements | vw_trader_account_summary | sp_cancel_order_refund |
|------|---------------------|-----------------|---------------------|--------------------------|----------------------|
| **db_admin** | ALL | ALL | ALL | ALL | ✓ EXECUTE |
| **trader_role** | ✓ SELECT | ✓ SELECT | — | — | — |
| **auditor_role** | ✓ SELECT | ✓ SELECT | ✓ SELECT | ✓ SELECT | — |
| **system_role** | — | — | — | — | ✓ EXECUTE |

## Architecture

The Spring Boot application connects to MySQL as `spring_app`, which holds the `system_role`. This role has been granted only the minimum privileges required to serve the three REST endpoints: listing orders, creating orders, and cancelling orders via the `sp_cancel_order_refund` stored procedure. The application server never operates as `db_admin`, because granting full privileges to a network-facing service would violate the principle of least privilege. If the application were compromised, an attacker with `db_admin` access could drop tables, alter schemas, or exfiltrate the entire database. By restricting `spring_app` to `system_role`, the blast radius of a potential breach is limited to the specific tables and operations the application legitimately requires.

Traders do not have direct access to the `accounting_ledgers` table. This table contains double-entry journal records that must remain consistent and tamper-proof. The `trader_role` is limited to two read-only views (`vw_portfolio_summary` and `vw_active_orders`) plus the `assets` reference table. All order placement and cancellation flows pass through the Spring Boot API, which enforces business rules before writing to the database. This separation ensures that no trader — even one with direct MySQL Workbench access — can modify or read raw ledger entries.

The `system_role` has INSERT but not UPDATE on `accounting_ledgers`, enforcing the append-only ledger principle at the database permission level. Financial corrections are never made by modifying existing entries; instead, a reversal entry with opposite debit and credit values is inserted. This approach preserves the complete audit trail. Even if application-level code contained a bug that attempted an UPDATE on the ledger table, MySQL would reject the query with an access-denied error. The database itself acts as the final enforcement layer for financial data integrity.

History tables (`order_history`, `position_history`, `ledger_audit`, `settlement_history`) are written exclusively by AFTER UPDATE and AFTER DELETE triggers defined with `DEFINER = root@localhost`. The `system_role` has no grants on these tables. This means the application cannot insert fabricated audit records or tamper with the change history. The triggers execute with the definer's elevated privileges, bypassing the connection user's permission set. This architectural choice ensures that audit trails are generated automatically and cannot be circumvented by the application layer.

## Connection Security Notes

The Spring Boot `application.properties` should use the `spring_app` credentials (see `security/grants.sql` — replace placeholder passwords before deployment) rather than root or admin credentials. The `admin_user` account has a 90-day password expiration policy enforced at the MySQL level via `PASSWORD EXPIRE INTERVAL 90 DAY`. Application service accounts should rotate credentials at least annually. The `auditor` user is restricted to connections from the `10.0.0.%` subnet, ensuring that compliance team access is limited to the internal corporate network. External connections from auditor credentials will be rejected by MySQL regardless of whether the password is correct.

## Implementation

- GRANT statements: [`security/grants.sql`](../security/grants.sql)
- Audit triggers: [`migrations/V4__Add_Audit_Triggers.sql`](../migrations/V4__Add_Audit_Triggers.sql)
