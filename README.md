# Payroll Management System — MySQL DBA Portfolio Project

A fully featured payroll management system built with MySQL, demonstrating core Database Administrator skills including schema design, indexing strategy, stored procedures, triggers, views, automated event scheduling, role-based access control, verification testing, and business analytics. Built as a DBA portfolio project targeting entry-level remote MySQL DBA roles.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Database Schema](#database-schema)
- [Features](#features)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Setup Instructions](#setup-instructions)
  - [Local MySQL](#local-mysql)
  - [Aiven (Cloud MySQL)](#aiven-cloud-mysql)
- [Usage Examples](#usage-examples)
- [Verification](#verification)
- [Analytics](#analytics)
- [Key Design Decisions](#key-design-decisions)
- [Author](#author)

---

## Project Overview

This system models a Nigerian payroll environment with FIRS PAYE tax compliance. It handles employee management, allowances, deductions, progressive tax calculation, payroll run processing, payslip generation, role-based access control, and a full audit trail — all enforced at the database layer.

**Core DBA concepts demonstrated:**
- Circular foreign key resolution via deferred `ALTER TABLE`
- Soft-delete pattern using status ENUMs
- Progressive PAYE tax calculation using a cursor-based stored procedure
- Audit logging with dual-identity tracking (`db_user` + `app_user_id`)
- Automated monthly payroll via MySQL Event Scheduler
- Index design including composite, covering, and FULLTEXT indexes
- Role-based access control with least-privilege principles
- Verification testing covering triggers, business rules, FK enforcement, and role isolation
- Business analytics queries for payroll cost, compensation, tax, headcount, and audit insights

---

## Database Schema

The database consists of 9 tables:

| Table | Description |
|---|---|
| `department` | Organisational departments with manager assignment |
| `employee` | Employee master records with soft-delete via `status` ENUM |
| `allowance` | Per-employee allowances (housing, transport, meal, etc.) with effective date ranges |
| `deduction` | Per-employee deductions (pension, health insurance, loan repayment, etc.) |
| `tax_bracket` | FIRS PAYE progressive tax bands |
| `payroll_run` | Payroll cycle records with status workflow (`draft` → `processing` → `completed`) |
| `payslip` | One payslip per employee per payroll run |
| `audit_log` | Tracks all sensitive data changes with before/after JSON snapshots |
| `payroll_config` | Key-value store driving event scheduler and payroll behavior |

### Entity Relationship Overview

```
department ──< employee >── allowance
                  │
                  ├──────── deduction
                  │
payroll_run ──< payslip
                  │
tax_bracket ───────┘ (used during payslip calculation)

employee ────────── audit_log (app_user_id)
```

---

## Features

### Schema Design
- Circular FK between `department.manager_id` and `employee.emp_id` resolved via deferred `ALTER TABLE`
- `ON DELETE` actions chosen deliberately: `RESTRICT` for financial records, `SET NULL` for optional references, `CASCADE` for dependent child records
- `CHECK` constraints on salary, tax rates, date ranges, and income bands
- `UNIQUE` constraint on `(run_id, emp_id)` in `payslip` enforcing one payslip per employee per run

### Indexes
- Composite indexes on frequently filtered column combinations (`emp_id, effective_from, effective_to`)
- FULLTEXT index on `(first_name, last_name, job_title)` for HR search queries
- Audit log indexed on `(table_name, record_id)` for per-record history lookups
- Redundant indexes intentionally omitted (e.g. `idx_slip_run` covered by `uq_payslip`)

### Views (5)
| View | Purpose |
|---|---|
| `vw_active_employees` | Active staff with department — safe read API |
| `vw_employee_payroll_summary` | Estimated net pay per employee |
| `vw_department_summary` | Headcount and salary cost per department |
| `vw_latest_payslips` | Payslips from the most recent completed run |
| `vw_audit_trail` | Human-readable audit log with employee name resolution |

### Stored Procedures (6)
| Procedure | Purpose |
|---|---|
| `sp_calculate_tax` | Progressive PAYE tax calculation using cursor over `tax_bracket` |
| `sp_generate_payslip` | Calculates and inserts/updates a single employee payslip |
| `sp_run_payroll` | Orchestrates a full payroll run for all active employees |
| `sp_get_payslip` | Retrieves full payslip detail for a given employee and run |
| `sp_update_salary` | Updates employee salary with automatic audit log entry |
| `sp_search_employees` | Free-text search over name/job title, backed by `ft_emp_name_title` |

### Triggers (7)
| Trigger | Purpose |
|---|---|
| `trg_employee_after_update` | Logs salary, status, title, and department changes |
| `trg_employee_after_delete` | Logs employee deletion with full snapshot |
| `trg_payslip_after_insert` | Logs every generated payslip |
| `trg_payslip_before_update` | Blocks edits to payslips on completed runs |
| `trg_payroll_run_before_update` | Prevents status regression on completed runs |
| `trg_allowance_after_insert` | Logs new allowance assignments |
| `trg_deduction_after_insert` | Logs new deduction assignments |

### Event Scheduler
- Automated monthly payroll execution driven by `payroll_config` settings
- Respects `auto_run_enabled` flag — can be toggled without dropping the event
- Updates `next_run_date` in `payroll_config` after each successful run

### Roles & Security (5 roles)
| Role | Access Level |
|---|---|
| `payroll_admin` | Full control — run payroll, manage employees, view everything |
| `hr_manager` | Manage employees, allowances, deductions + relevant views |
| `finance_viewer` | Read-only payslips, payroll runs, and financial reports |
| `audit_viewer` | Read-only audit log and audit trail view only |
| `app_service` | Least privilege — only what the application needs at runtime |

---

## Technology Stack

- **Database:** MySQL 8.0+
- **Engine:** InnoDB (all tables)
- **Cloud Hosting:** [Aiven](https://aiven.io) (free tier)
- **Version Control:** GitHub

---

## Project Structure

```
payroll-system/
│
├── payroll_db.sql                    # Main script — tables, indexes, seed data,
│                                     # views, procedures, triggers, event scheduler,
│                                     # roles & security
│
├── verify_payroll_db.sql             # 15 verification tests — triggers, business
│                                     # rules, FK enforcement, role isolation,
│                                     # payslip integrity
│
├── analytics_payroll_db.sql          # 16 analytics queries — payroll cost,
│                                     # compensation, tax reporting, headcount,
│                                     # audit insights (with expected output samples)
│
├── backup_recovery_payroll_db.md     # Backup & recovery guide — mysqldump,
│                                     # binary logs, point-in-time recovery,
│                                     # Aiven backup, schedule and checklist
│
├── performance_tuning_payroll_db.md  # Performance tuning guide — EXPLAIN analysis,
│                                     # index verification, slow query log, InnoDB
│                                     # buffer pool, audit log maintenance, monitoring
│
└── README.md                         # Project documentation
```

---

## Setup Instructions

### Local MySQL

**Prerequisites:** MySQL 8.0+ installed and running.

1. Clone the repository:
```bash
git clone https://github.com/omowaye/payroll-system.git
cd payroll-system
```

2. **Update passwords** in `payroll_db.sql` before running (search for `Change_Me_`):
```sql
-- Example: replace placeholder with a strong password
'Change_Me_Admin!2024' → 'YourStrongPasswordHere'
```

3. Run the main script:
```bash
mysql -u root -p < payroll_db.sql
```

4. Enable the event scheduler if not already on:
```sql
SET GLOBAL event_scheduler = ON;
```

5. Run payroll to populate transactional data:
```sql
USE payroll_db;
CALL sp_run_payroll('2026-06-01', '2026-06-30', '2026-06-28', 1);
```

### Aiven (Cloud MySQL)

**Prerequisites:** An [Aiven](https://aiven.io) account with a MySQL service created (free tier available).

1. From your Aiven console, download the **CA certificate** for your service.

2. **Update passwords** in `payroll_db.sql` before running (search for `Change_Me_`).

3. Connect and run the script:
```bash
mysql --host <your-aiven-host> \
      --port <your-aiven-port> \
      --user avnadmin \
      --password \
      --ssl-ca=ca.pem \
      < payroll_db.sql
```

4. Run payroll to populate transactional data:
```sql
USE payroll_db;
CALL sp_run_payroll('2026-06-01', '2026-06-30', '2026-06-28', 1);
```

> **Note:** If `SET GLOBAL event_scheduler = ON` is blocked on Aiven, enable it via the **Advanced Configuration** panel in your Aiven service settings under `event_scheduler = ON`.

---

## Usage Examples

### Run payroll for a period
```sql
CALL sp_run_payroll('2026-06-01', '2026-06-30', '2026-06-28', 1);
```

### View latest payslips
```sql
SELECT * FROM vw_latest_payslips;
```

### Get a specific employee's payslip
```sql
CALL sp_get_payslip(1, 1);  -- emp_id=1, run_id=1
```

### Update an employee's salary (with audit trail)
```sql
CALL sp_update_salary(2, 780000.00, 1);  -- emp_id, new salary, app_user_id
```

### View full audit trail
```sql
SELECT * FROM vw_audit_trail;
```

### Search employees by name or job title
```sql
CALL sp_search_employees('Engineer');       -- single word, prefix-matched
CALL sp_search_employees('Senior Accountant');  -- phrase, natural language mode
```

### Check department salary costs
```sql
SELECT * FROM vw_department_summary;
```

### Toggle auto payroll on/off
```sql
UPDATE payroll_config SET config_value = 'false' WHERE config_key = 'auto_run_enabled';
```

---

## Verification

Run `verify_payroll_db.sql` after loading the main script to confirm all components work correctly:

```bash
mysql -u root -p payroll_db < verify_payroll_db.sql
```

**What is verified (15 tests):**

| Test | What it checks |
|---|---|
| 1 | All 9 tables exist |
| 2 | Seed data row counts are correct |
| 3 | Circular FK — department managers wired correctly |
| 4 | All 5 views return data |
| 5 | `sp_calculate_tax` returns correct PAYE amount |
| 6 | Payroll run completes with status `completed` |
| 7 | Payslip count matches active employee count |
| 8 | `net_pay = gross - deductions - tax` for every payslip |
| 9 | Employee UPDATE trigger writes to `audit_log` |
| 10 | Payslip UPDATE blocked on completed run |
| 11 | Payroll run status regression blocked |
| 12 | FK RESTRICT blocks department delete with active employees |
| 13 | All 5 role users exist in MySQL |
| 14 | All named indexes exist |
| 15 | Audit log populated after payroll run |

---

## Analytics

Run `analytics_payroll_db.sql` to generate business intelligence reports:

```bash
mysql -u root -p payroll_db < analytics_payroll_db.sql
```

**Sections covered:**

| Section | Queries |
|---|---|
| A — Payroll Cost Analysis | Monthly cost by dept, cost per run, allowance breakdown, deduction breakdown |
| B — Compensation Insights | Salary by job title, top 3 earners per dept, salary bands, net vs base salary |
| C — Tax Reporting | PAYE collected per run, effective tax rate per employee, pension liability |
| D — Headcount & Workforce | Headcount by dept/status, tenure analysis, most recent hires |
| E — Audit & Security | Activity by table, most active DB users, frequently modified records |
| F — Config Reporting | Current system configuration, next scheduled run details |

---

## Key Design Decisions

**Why `RESTRICT` on payslip foreign keys?**
Payslips are financial records. Deleting an employee or payroll run that has associated payslips would destroy historical pay data. `RESTRICT` forces explicit cleanup rather than silent data loss.

**Why split `changed_by` into `db_user` and `app_user_id` in `audit_log`?**
`USER()` captures the MySQL connection identity (the service account), not the actual person who triggered the change. `app_user_id` references `employee` to identify which HR admin or system process initiated the action — giving the audit log real forensic value.

**Why a cursor in `sp_calculate_tax` instead of a single query?**
Nigerian PAYE uses a progressive tax structure where each income band is taxed at a different rate. A cursor iterates through each band in order, taxing only the portion of income that falls within that band — the same logic a tax authority applies manually.

**Why `payroll_config` instead of hardcoding values in procedures?**
Config values like `pay_day`, `pension_rate`, and `auto_run_enabled` change over time. Storing them in a table means a single `UPDATE` changes system behavior without touching stored procedure code.

**Why is `idx_slip_run` omitted?**
The `uq_payslip UNIQUE (run_id, emp_id)` constraint automatically creates a composite index with `run_id` as the leftmost column, making a separate `idx_slip_run` redundant. Keeping duplicate indexes wastes storage and adds write overhead with no query-planning benefit.

**Why least-privilege for `app_service`?**
The application service account only gets `SELECT`, `INSERT`, and `EXECUTE` on the specific tables and procedures it needs at runtime. If the account is ever compromised, the blast radius is limited — it cannot `DROP`, `UPDATE` employee salaries, or read the raw audit log.

---

## Author

**Omowaye**
Aspiring MySQL Database Administrator | MSc Cybersecurity (UTT, September 2026)
GitHub: [github.com/omowaye](https://github.com/omowaye)
