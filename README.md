# Payroll Management System — MySQL

A fully-featured relational database project built with MySQL 8.0,
demonstrating core Database Administrator skills.

## Features
- 9 normalized tables (3NF) with foreign keys and constraints
- 10 indexes (B-Tree + FULLTEXT) for query optimization
- 4 stored procedures including a transaction-safe payroll generator
- 4 triggers for audit logging and data integrity
- 3 role-based access control levels (admin, officer, viewer)
- MySQL EVENT scheduler for automated monthly payroll runs
- FULLTEXT search with natural language, boolean, and exact modes
- 13 analytical queries using JOINs, CTEs, subqueries, window functions

## Database Schema
![ER Diagram](docs/ER_Diagram.png)
## Tables
| Table | Description |
|---|---|
| department | Company departments and managers |
| employee | All staff records |
| allowance | Housing, transport, meal allowances |
| deduction | Pension, insurance, loan repayments |
| tax_bracket | Progressive PAYE tax bands |
| payroll_run | Monthly payroll batch records |
| payslip | Individual employee pay calculations |
| audit_log | Full change history (JSON) |
| payroll_config | Event scheduler configuration |

## How to Run
```bash
mysql -u root -p < sql/payroll_complete.sql
```

## Key SQL Techniques Demonstrated
- ACID transactions with ROLLBACK on failure
- Cursor-based progressive tax calculation
- Window functions: LAG, SUM OVER, AVG OVER
- CTEs for readable multi-step queries
- FULLTEXT indexing with three search modes
- Role-based security with GRANT/REVOKE

## Tools Used
MySQL 8.0 · MySQL Workbench · Git
