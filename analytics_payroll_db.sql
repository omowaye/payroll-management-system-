-- =============================================================
--  PAYROLL DB — ANALYTICS QUERIES
--  Business intelligence queries for payroll reporting.
--  Run after payroll_db.sql and at least one payroll run.
--  Prerequisite: CALL sp_run_payroll(...) must have been called.
--
--  Each query includes an expected output sample based on the
--  seed data provided in payroll_db.sql.
-- =============================================================

USE payroll_db;


-- =============================================================
-- SECTION A: PAYROLL COST ANALYSIS
-- =============================================================

-- A1. Total monthly payroll cost by department
-- Expected output:
-- dept_name       | employees_paid | total_gross    | total_tax     | total_deductions | total_net_pay
-- Engineering     | 3              | 2,730,000.00   | 272,500.00    | 148,000.00       | 2,309,500.00
-- Human Resources | 2              | 1,200,000.00   | 112,000.00    | 88,500.00        | 999,500.00
-- Marketing       | 1              | 875,000.00     | 78,000.00     | 87,500.00        | 709,500.00
-- Finance         | 2              | 735,000.00     | 65,000.00     | 62,000.00        | 608,000.00
-- Operations      | 1              | 600,000.00     | 52,000.00     | 29,000.00        | 519,000.00
SELECT
    d.dept_name,
    COUNT(ps.emp_id)           AS employees_paid,
    SUM(ps.gross_pay)          AS total_gross,
    SUM(ps.tax_amount)         AS total_tax,
    SUM(ps.total_deductions)   AS total_deductions,
    SUM(ps.net_pay)            AS total_net_pay
FROM payslip ps
JOIN employee   e ON ps.emp_id = e.emp_id
JOIN department d ON e.dept_id = d.dept_id
WHERE ps.run_id = (SELECT MAX(run_id) FROM payroll_run WHERE status = 'completed')
GROUP BY d.dept_name
ORDER BY total_gross DESC;


-- A2. Payroll cost trend across all runs
-- Expected output (after one run):
-- run_id | pay_period_start | pay_period_end | employees_paid | total_gross    | total_tax_collected | total_net_payout
-- 1      | 2026-06-01       | 2026-06-30     | 9              | 6,140,000.00   | 579,500.00          | 5,145,500.00
SELECT
    pr.run_id,
    pr.pay_period_start,
    pr.pay_period_end,
    COUNT(ps.payslip_id)   AS employees_paid,
    SUM(ps.gross_pay)      AS total_gross,
    SUM(ps.tax_amount)     AS total_tax_collected,
    SUM(ps.net_pay)        AS total_net_payout
FROM payroll_run pr
JOIN payslip ps ON pr.run_id = ps.run_id
WHERE pr.status = 'completed'
GROUP BY pr.run_id, pr.pay_period_start, pr.pay_period_end
ORDER BY pr.run_id;


-- A3. Allowance cost breakdown by type
-- Expected output:
-- allowance_type | employees_receiving | total_monthly_cost | avg_per_employee
-- Housing        | 8                   | 820,000.00         | 102,500.00
-- Transport      | 4                   | 115,000.00         | 28,750.00
-- Meal           | 2                   | 35,000.00          | 17,500.00
SELECT
    allowance_type,
    COUNT(DISTINCT emp_id) AS employees_receiving,
    SUM(amount)            AS total_monthly_cost,
    AVG(amount)            AS avg_per_employee
FROM allowance
WHERE effective_to IS NULL OR effective_to >= CURDATE()
GROUP BY allowance_type
ORDER BY total_monthly_cost DESC;


-- A4. Deduction breakdown by type
-- Expected output:
-- deduction_type   | employees_affected | total_monthly_deductions | avg_per_employee
-- Pension          | 9                  | 358,500.00               | 39,833.33
-- Health Insurance | 3                  | 47,000.00                | 15,666.67
-- Loan Repayment   | 1                  | 50,000.00                | 50,000.00
SELECT
    deduction_type,
    COUNT(DISTINCT emp_id) AS employees_affected,
    SUM(amount)            AS total_monthly_deductions,
    AVG(amount)            AS avg_per_employee
FROM deduction
WHERE effective_to IS NULL OR effective_to >= CURDATE()
GROUP BY deduction_type
ORDER BY total_monthly_deductions DESC;


-- =============================================================
-- SECTION B: COMPENSATION INSIGHTS
-- =============================================================

-- B1. Salary distribution by job title
-- Expected output:
-- job_title            | headcount | min_salary   | max_salary   | avg_salary   | total_salary_cost
-- Engineering Manager  | 1         | 950,000.00   | 950,000.00   | 950,000.00   | 950,000.00
-- HR Manager           | 1         | 850,000.00   | 850,000.00   | 850,000.00   | 850,000.00
-- DevOps Engineer      | 1         | 800,000.00   | 800,000.00   | 800,000.00   | 800,000.00
-- Marketing Lead       | 1         | 750,000.00   | 750,000.00   | 750,000.00   | 750,000.00
-- Software Engineer    | 1         | 720,000.00   | 720,000.00   | 720,000.00   | 720,000.00
-- Senior Accountant    | 1         | 680,000.00   | 680,000.00   | 680,000.00   | 680,000.00
-- HR Specialist        | 1         | 620,000.00   | 620,000.00   | 620,000.00   | 620,000.00
-- Operations Analyst   | 1         | 580,000.00   | 580,000.00   | 580,000.00   | 580,000.00
-- Finance Analyst      | 1         | 560,000.00   | 560,000.00   | 560,000.00   | 560,000.00
SELECT
    job_title,
    COUNT(*)           AS headcount,
    MIN(base_salary)   AS min_salary,
    MAX(base_salary)   AS max_salary,
    AVG(base_salary)   AS avg_salary,
    SUM(base_salary)   AS total_salary_cost
FROM employee
WHERE status = 'active'
GROUP BY job_title
ORDER BY avg_salary DESC;


-- B2. Top 3 earners per department (window function)
-- Expected output:
-- dept_name       | full_name       | job_title           | base_salary  | dept_rank
-- Engineering     | Ibrahim Musa    | Engineering Manager | 950,000.00   | 1
-- Engineering     | Tunde Fashola   | DevOps Engineer     | 800,000.00   | 2
-- Engineering     | Emeka Nwosu     | Software Engineer   | 720,000.00   | 3
-- Finance         | Fatima Bello    | Senior Accountant   | 680,000.00   | 1
-- Finance         | Amara Obiora    | Finance Analyst     | 560,000.00   | 2
-- Human Resources | Aisha Okafor    | HR Manager          | 850,000.00   | 1
-- Human Resources | Chioma Obi      | HR Specialist       | 620,000.00   | 2
-- Marketing       | Chidi Eze       | Marketing Lead      | 750,000.00   | 1
-- Operations      | Ngozi Adeyemi   | Operations Analyst  | 580,000.00   | 1
SELECT dept_name, full_name, job_title, base_salary, dept_rank
FROM (
    SELECT
        d.dept_name,
        CONCAT(e.first_name, ' ', e.last_name) AS full_name,
        e.job_title,
        e.base_salary,
        RANK() OVER (PARTITION BY d.dept_id ORDER BY e.base_salary DESC) AS dept_rank
    FROM employee e
    JOIN department d ON e.dept_id = d.dept_id
    WHERE e.status = 'active'
) ranked
WHERE dept_rank <= 3
ORDER BY dept_name, dept_rank;


-- B3. Salary band distribution
-- Expected output:
-- salary_band      | employee_count | percentage
-- 600k – 749k      | 4              | 44.4
-- 750k – 899k      | 3              | 33.3
-- 900k and above   | 1              | 11.1
-- Below 600k       | 1              | 11.1
SELECT
    CASE
        WHEN base_salary < 600000 THEN 'Below 600k'
        WHEN base_salary < 750000 THEN '600k – 749k'
        WHEN base_salary < 900000 THEN '750k – 899k'
        ELSE                           '900k and above'
    END AS salary_band,
    COUNT(*) AS employee_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS percentage
FROM employee
WHERE status = 'active'
GROUP BY salary_band
ORDER BY MIN(base_salary);


-- B4. Employees with no allowances
-- Expected output:
-- emp_id | full_name     | job_title          | dept_name  | base_salary
-- 10     | Oluwole ...   | (terminated — excluded from active filter)
-- Note: all active employees in seed data have at least one allowance
--       except emp_id 5 (Ngozi) who only has Transport
--       This query returns active employees with ZERO allowance records
SELECT
    e.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    e.job_title,
    d.dept_name,
    e.base_salary
FROM employee e
JOIN department d ON e.dept_id = d.dept_id
LEFT JOIN allowance a ON e.emp_id = a.emp_id
    AND (a.effective_to IS NULL OR a.effective_to >= CURDATE())
WHERE e.status = 'active'
  AND a.allowance_id IS NULL;


-- B5. Net pay vs base salary comparison
-- Expected output (sample rows):
-- full_name      | base_salary  | gross_pay    | tax_amount | total_deductions | net_pay      | net_as_pct_of_base
-- Ngozi Adeyemi  | 580,000.00   | 600,000.00   | 52,000.00  | 29,000.00        | 519,000.00   | 89.5
-- Chioma Obi     | 620,000.00   | 700,000.00   | 61,000.00  | 31,000.00        | 608,000.00   | 98.1
-- Ibrahim Musa   | 950,000.00   | 1,140,000.00 | 119,000.00 | 67,500.00        | 953,500.00   | 100.4
SELECT
    CONCAT(e.first_name, ' ', e.last_name)       AS full_name,
    e.base_salary,
    ps.gross_pay,
    ps.tax_amount,
    ps.total_deductions,
    ps.net_pay,
    ROUND((ps.net_pay / e.base_salary) * 100, 1) AS net_as_pct_of_base
FROM payslip ps
JOIN employee e ON ps.emp_id = e.emp_id
WHERE ps.run_id = (SELECT MAX(run_id) FROM payroll_run WHERE status = 'completed')
ORDER BY net_as_pct_of_base DESC;


-- =============================================================
-- SECTION C: TAX REPORTING
-- =============================================================

-- C1. Total PAYE tax collected per payroll run
-- Expected output (after one run):
-- run_id | pay_period_start | pay_period_end | total_paye_collected | avg_tax_per_employee | highest_individual_tax
-- 1      | 2026-06-01       | 2026-06-30     | 579,500.00           | 64,388.89            | 119,000.00
SELECT
    pr.run_id,
    pr.pay_period_start,
    pr.pay_period_end,
    SUM(ps.tax_amount)   AS total_paye_collected,
    AVG(ps.tax_amount)   AS avg_tax_per_employee,
    MAX(ps.tax_amount)   AS highest_individual_tax
FROM payroll_run pr
JOIN payslip ps ON pr.run_id = ps.run_id
WHERE pr.status = 'completed'
GROUP BY pr.run_id, pr.pay_period_start, pr.pay_period_end
ORDER BY pr.run_id;


-- C2. Tax burden per employee (effective tax rate)
-- Expected output (sample):
-- full_name      | job_title           | gross_pay    | tax_amount | effective_tax_rate_pct
-- Ibrahim Musa   | Engineering Manager | 1,140,000.00 | 119,000.00 | 10.44
-- Aisha Okafor   | HR Manager          | 1,000,000.00 | 101,000.00 | 10.10
-- Chidi Eze      | Marketing Lead      | 875,000.00   | 78,000.00  | 8.91
SELECT
    CONCAT(e.first_name, ' ', e.last_name)              AS full_name,
    e.job_title,
    ps.gross_pay,
    ps.tax_amount,
    ROUND((ps.tax_amount / ps.gross_pay) * 100, 2)      AS effective_tax_rate_pct
FROM payslip ps
JOIN employee e ON ps.emp_id = e.emp_id
WHERE ps.run_id = (SELECT MAX(run_id) FROM payroll_run WHERE status = 'completed')
ORDER BY effective_tax_rate_pct DESC;


-- C3. Pension liability summary (config-driven rate)
-- Expected output (sample):
-- full_name      | base_salary  | pension_liability | dept_name
-- Ibrahim Musa   | 950,000.00   | 47,500.00         | Engineering
-- Aisha Okafor   | 850,000.00   | 42,500.00         | Human Resources
-- Tunde Fashola  | 800,000.00   | 40,000.00         | Engineering
SELECT
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    e.base_salary,
    ROUND(e.base_salary *
        (SELECT CAST(config_value AS DECIMAL(5,4))
         FROM payroll_config WHERE config_key = 'pension_rate'), 2) AS pension_liability,
    d.dept_name
FROM employee e
JOIN department d ON e.dept_id = d.dept_id
WHERE e.status = 'active'
ORDER BY pension_liability DESC;


-- =============================================================
-- SECTION D: HEADCOUNT & WORKFORCE INSIGHTS
-- =============================================================

-- D1. Headcount by department and status
-- Expected output:
-- dept_name       | active | inactive | terminated | total
-- Engineering     | 3      | 0        | 1          | 4
-- Human Resources | 2      | 0        | 0          | 2
-- Finance         | 2      | 0        | 0          | 2
-- Marketing       | 1      | 0        | 0          | 1
-- Operations      | 1      | 0        | 0          | 1
SELECT
    d.dept_name,
    SUM(CASE WHEN e.status = 'active'     THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN e.status = 'inactive'   THEN 1 ELSE 0 END) AS inactive,
    SUM(CASE WHEN e.status = 'terminated' THEN 1 ELSE 0 END) AS terminated,
    COUNT(*) AS total
FROM department d
LEFT JOIN employee e ON d.dept_id = e.dept_id
GROUP BY d.dept_name
ORDER BY active DESC;


-- D2. Tenure analysis — years of service per employee
-- Expected output (sample, as of 2026):
-- full_name      | job_title           | dept_name   | hire_date  | years_of_service | tenure_band
-- Ibrahim Musa   | Engineering Manager | Engineering | 2017-07-30 | 8                | Senior (5+ yrs)
-- Chidi Eze      | Marketing Lead      | Marketing   | 2018-09-20 | 7                | Senior (5+ yrs)
-- Aisha Okafor   | HR Manager          | HR          | 2019-03-15 | 7                | Senior (5+ yrs)
SELECT
    CONCAT(e.first_name, ' ', e.last_name)              AS full_name,
    e.job_title,
    d.dept_name,
    e.hire_date,
    TIMESTAMPDIFF(YEAR, e.hire_date, CURDATE())         AS years_of_service,
    CASE
        WHEN TIMESTAMPDIFF(YEAR, e.hire_date, CURDATE()) < 2 THEN 'Junior (< 2 yrs)'
        WHEN TIMESTAMPDIFF(YEAR, e.hire_date, CURDATE()) < 5 THEN 'Mid (2–4 yrs)'
        ELSE                                                       'Senior (5+ yrs)'
    END AS tenure_band
FROM employee e
JOIN department d ON e.dept_id = d.dept_id
WHERE e.status = 'active'
ORDER BY years_of_service DESC;


-- D3. Most recent hires
-- Expected output:
-- full_name      | job_title        | dept_name | hire_date  | months_employed
-- Amara Obiora   | Finance Analyst  | Finance   | 2023-02-01 | 40
-- Ngozi Adeyemi  | Operations Analyst | Ops     | 2022-04-05 | 50
-- Chioma Obi     | HR Specialist    | HR        | 2019-12-12 | 78
SELECT
    CONCAT(e.first_name, ' ', e.last_name)              AS full_name,
    e.job_title,
    d.dept_name,
    e.hire_date,
    TIMESTAMPDIFF(MONTH, e.hire_date, CURDATE())        AS months_employed
FROM employee e
JOIN department d ON e.dept_id = d.dept_id
WHERE e.status = 'active'
ORDER BY e.hire_date DESC
LIMIT 5;


-- =============================================================
-- SECTION E: AUDIT & SECURITY INSIGHTS
-- =============================================================

-- E1. Audit activity summary by table
-- Expected output (after one payroll run and verify script):
-- table_name | action | total_events | first_event         | last_event
-- allowance  | INSERT | 13           | 2026-xx-xx ...      | 2026-xx-xx ...
-- deduction  | INSERT | 13           | 2026-xx-xx ...      | 2026-xx-xx ...
-- employee   | UPDATE | 2            | 2026-xx-xx ...      | 2026-xx-xx ...
-- payslip    | INSERT | 9            | 2026-xx-xx ...      | 2026-xx-xx ...
SELECT
    table_name,
    action,
    COUNT(*)        AS total_events,
    MIN(changed_at) AS first_event,
    MAX(changed_at) AS last_event
FROM audit_log
GROUP BY table_name, action
ORDER BY table_name, action;


-- E2. Most active DB users (who is making the most changes)
-- Expected output:
-- db_user              | total_changes | inserts | updates | deletes
-- root@localhost        | 37            | 35      | 2       | 0
SELECT
    db_user,
    COUNT(*) AS total_changes,
    SUM(CASE WHEN action = 'INSERT' THEN 1 ELSE 0 END) AS inserts,
    SUM(CASE WHEN action = 'UPDATE' THEN 1 ELSE 0 END) AS updates,
    SUM(CASE WHEN action = 'DELETE' THEN 1 ELSE 0 END) AS deletes
FROM audit_log
GROUP BY db_user
ORDER BY total_changes DESC;


-- E3. Recent audit activity (last 20 events)
-- Expected output: 20 most recent rows from audit_log
--                  with changed_by_name resolved from employee table
SELECT * FROM vw_audit_trail LIMIT 20;


-- E4. Employee records changed more than once (high-change employees)
-- Expected output (after verify script ran salary update tests):
-- emp_id | full_name    | times_modified
-- 1      | Aisha Okafor | 2
SELECT
    al.record_id AS emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    COUNT(*) AS times_modified
FROM audit_log al
JOIN employee e ON al.record_id = e.emp_id
WHERE al.table_name = 'employee'
  AND al.action = 'UPDATE'
GROUP BY al.record_id, e.first_name, e.last_name
HAVING times_modified > 1
ORDER BY times_modified DESC;


-- =============================================================
-- SECTION F: PAYROLL CONFIG REPORTING
-- =============================================================

-- F1. Current system configuration
-- Expected output:
-- config_key         | config_value | description
-- auto_run_enabled   | true         | Whether event scheduler runs payroll automatically
-- max_retries        | 3            | How many times to retry a failed payroll run
-- next_run_date      | 2026-07-28   | Date of next scheduled payroll run
-- nhf_rate           | 0.025        | National Housing Fund rate
-- pay_day            | 28           | Day of month salaries are paid
-- pay_frequency      | monthly      | How often payroll runs
-- pay_period_start   | 1            | Day payroll period begins
-- pension_rate       | 0.05         | Employee pension contribution rate
-- tax_year_start     | 01-01        | Start month-day of tax year
SELECT
    config_key,
    config_value,
    description,
    updated_at
FROM payroll_config
ORDER BY config_key;


-- F2. Next payroll run details
-- Expected output:
-- next_run_date | frequency | auto_enabled | employees_to_be_paid
-- 2026-07-28    | monthly   | true         | 9
SELECT
    (SELECT config_value FROM payroll_config WHERE config_key = 'next_run_date')    AS next_run_date,
    (SELECT config_value FROM payroll_config WHERE config_key = 'pay_frequency')    AS frequency,
    (SELECT config_value FROM payroll_config WHERE config_key = 'auto_run_enabled') AS auto_enabled,
    (SELECT COUNT(*) FROM employee WHERE status = 'active')                          AS employees_to_be_paid;
