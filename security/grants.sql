-- ============================================================
-- Capital Markets Trading Platform — Security Configuration
-- MySQL 8.0 Role-Based Access Control
-- Author: Kevin
-- Date:   2026-03-10
-- ============================================================

USE capital_markets_db;

-- ============================================================
-- SECTION 1 — CREATE ROLES
-- ============================================================

CREATE ROLE IF NOT EXISTS 'db_admin';
CREATE ROLE IF NOT EXISTS 'trader_role';
CREATE ROLE IF NOT EXISTS 'auditor_role';
CREATE ROLE IF NOT EXISTS 'system_role';

-- ============================================================
-- SECTION 2 — GRANT PRIVILEGES TO ROLES
-- ============================================================

-- ----- db_admin (full access for database administrators) -----
GRANT ALL PRIVILEGES ON capital_markets_db.* TO 'db_admin' WITH GRANT OPTION;

-- ----- trader_role (read-only access via MySQL Workbench) -----
-- Traders interact through the Spring Boot API (which uses system_role).
-- trader_role is for hypothetical direct DB tool access (e.g., read-only views).
GRANT SELECT ON capital_markets_db.vw_portfolio_summary TO 'trader_role';
GRANT SELECT ON capital_markets_db.vw_active_orders     TO 'trader_role';
GRANT SELECT ON capital_markets_db.assets               TO 'trader_role';
-- NO access to accounting_ledgers directly (sensitive financial records)
-- NO access to history/audit tables directly

-- ----- auditor_role (compliance team — read everything, change nothing) -----
GRANT SELECT ON capital_markets_db.* TO 'auditor_role';
-- This wildcard grant includes ALL tables: core tables, history tables
-- (order_history, position_history, ledger_audit, settlement_history),
-- and all views. Auditors need full read access for compliance review.
-- NO INSERT, UPDATE, DELETE on anything.

-- ----- system_role (Spring Boot application server) -----
-- Core transactional tables
GRANT SELECT, INSERT, UPDATE ON capital_markets_db.orders      TO 'system_role';
GRANT SELECT, INSERT, UPDATE ON capital_markets_db.positions   TO 'system_role';
GRANT SELECT, INSERT, UPDATE ON capital_markets_db.settlements TO 'system_role';

-- accounting_ledgers is append-only: INSERT only, no UPDATE or DELETE
GRANT SELECT, INSERT ON capital_markets_db.accounting_ledgers TO 'system_role';

-- Reference / lookup tables (read-only)
GRANT SELECT ON capital_markets_db.traders    TO 'system_role';
GRANT SELECT ON capital_markets_db.assets     TO 'system_role';
GRANT SELECT ON capital_markets_db.portfolios TO 'system_role';

-- Stored procedures
GRANT EXECUTE ON PROCEDURE capital_markets_db.sp_cancel_order_refund TO 'system_role';

-- order_history   — NOT granted to system_role — triggers write here using DEFINER privileges
-- position_history — NOT granted to system_role — triggers write here using DEFINER privileges
-- ledger_audit     — NOT granted to system_role — triggers write here using DEFINER privileges
-- settlement_history — NOT granted to system_role — triggers write here using DEFINER privileges

-- NO DROP, ALTER, or CREATE privileges for system_role

-- ============================================================
-- SECTION 3 — CREATE USERS
-- ============================================================

-- ⚠️  Replace the placeholder passwords below before running in production.
--     Use strong, unique passwords that comply with FR-SEC-005 policy
--     (≥12 chars, mixed case, digit, special character).

CREATE USER IF NOT EXISTS 'admin_user'@'localhost'
    IDENTIFIED BY '<CHANGE_ME_admin_password>'
    PASSWORD EXPIRE INTERVAL 90 DAY;

CREATE USER IF NOT EXISTS 'spring_app'@'localhost'
    IDENTIFIED BY '<CHANGE_ME_spring_app_password>'
    COMMENT 'Spring Boot application server connection';

CREATE USER IF NOT EXISTS 'auditor'@'10.0.0.%'
    IDENTIFIED BY '<CHANGE_ME_auditor_password>'
    COMMENT 'Compliance team — restricted to internal network';

-- ============================================================
-- SECTION 4 — ASSIGN ROLES TO USERS
-- ============================================================

GRANT 'db_admin'     TO 'admin_user'@'localhost';
GRANT 'system_role'  TO 'spring_app'@'localhost';
GRANT 'auditor_role' TO 'auditor'@'10.0.0.%';

-- ============================================================
-- SECTION 5 — SET DEFAULT ROLES
-- ============================================================

SET DEFAULT ROLE 'db_admin'     TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'system_role'  TO 'spring_app'@'localhost';
SET DEFAULT ROLE 'auditor_role' TO 'auditor'@'10.0.0.%';

FLUSH PRIVILEGES;

-- Verification queries (uncomment to test):
-- SHOW GRANTS FOR 'spring_app'@'localhost';
-- SHOW GRANTS FOR 'auditor'@'10.0.0.%';
-- SHOW GRANTS FOR 'admin_user'@'localhost';
