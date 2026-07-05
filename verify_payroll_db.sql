-- =============================================================
--  PAYROLL DB — VERIFICATION SCRIPT
--  Run this after payroll_db.sql to confirm everything works.
--  Each section prints a label and expected vs actual result.
--  ✅ = expected behaviour confirmed
--  ❌ = something is wrong — investigate before going live
-- =============================================================

USE payroll_db;


-- =============================================================
-- TEST 1: Tables exist
-- Expected: 9 rows, one per table
-- =============================================================
SELECT '=== TEST 1: Tables ===' AS test;
SELECT table_name AS 'Table', 'EXISTS' AS status
FROM information_schema.tables
WHERE table_schema = 'payroll_db'
ORDER BY table_name;
-- ✅ Should list: allowance, audit_log, deduction, department,
--                employee, payroll_config, payroll_run, payslip, tax_bracket


-- =============================================================
-- TEST 2: Seed data row counts
-- =============================================================
SELECT '=== TEST 2: Seed Data Counts ===' AS test;
SELECT 'department'     AS tbl, COUNT(*) AS row_count FROM department     UNION ALL
SELECT 'employee',               COUNT(*)              FROM employee        UNION ALL
SELECT 'allowance',              COUNT(*)              FROM allowance       UNION ALL
SELECT 'deduction',              COUNT(*)              FROM deduction       UNION ALL
SELECT 'tax_bracket',            COUNT(*)              FROM tax_bracket     UNION ALL
SELECT 'payroll_config',         COUNT(*)              FROM payroll_config;
-- ✅ Expected: department=5, employee=10, allowance=13,
--             deduction=13, tax_bracket=6, payroll_config=9


-- =============================================================
-- TEST 3: Circular FK — department managers wired correctly
-- =============================================================
SELECT '=== TEST 3: Department Managers ===' AS test;
SELECT d.dept_name,
       CONCAT(e.first_name, ' ', e.last_name) AS manager_name,
       e.job_title
FROM department d
JOIN employee e ON d.manager_id = e.emp_id;
-- ✅ Expected: 5 rows with correct manager per department


-- =============================================================
-- TEST 4: Views return data
-- =============================================================
SELECT '=== TEST 4: Views ===' AS test;

SELECT 'vw_active_employees'         AS view_name, COUNT(*) AS row_count FROM vw_active_employees        UNION ALL
SELECT 'vw_employee_payroll_summary', COUNT(*)      AS row_count        FROM vw_employee_payroll_summary UNION ALL
SELECT 'vw_department_summary',       COUNT(*)      AS row_count        FROM vw_department_summary;
-- ✅ Expected: active_employees=9, payroll_summary=9, dept_summary=5
--    (Oluwole is terminated so excluded from active views)


-- =============================================================
-- TEST 5: Tax calculation — known input/output
-- sp_calculate_tax(8640000) = annual gross for Aisha (720k/month)
-- Band 1:  300000 * 0.07 =  21000
-- Band 2:  300000 * 0.11 =  33000
-- Band 3:  500000 * 0.15 =  75000  (600k-1100k, only 500k used)
-- Wait — Aisha base=850k + allowances=150k = 1000k/month gross
-- Annual = 12000000
-- Band 1:   300000 * 0.07 =   21000
-- Band 2:   300000 * 0.11 =   33000
-- Band 3:   500000 * 0.15 =   75000
-- Band 4:   500000 * 0.19 =   95000
-- Band 5:  1600000 * 0.21 =  336000
-- Band 6:  8800000 * 0.24 = 2112000  ← remaining after bands 1-5
-- Total annual tax        = 2672000 → monthly = 222666.67
-- =============================================================
SELECT '=== TEST 5: Tax Calculation ===' AS test;
CALL sp_calculate_tax(12000000, @tax_out);
SELECT
    12000000            AS annual_gross,
    @tax_out            AS annual_tax_calculated,
    2672000.00          AS annual_tax_expected,
    IF(@tax_out = 2672000.00, '✅ PASS', '❌ FAIL') AS result;


-- =============================================================
-- TEST 6: Run payroll and verify payslip generation
-- =============================================================
SELECT '=== TEST 6: Payroll Run ===' AS test;

CALL sp_run_payroll('2026-06-01', '2026-06-30', '2026-06-28', 1);

SELECT run_id, pay_period_start, pay_period_end, status,
       IF(status = 'completed', '✅ PASS', '❌ FAIL') AS result
FROM payroll_run
ORDER BY run_id DESC LIMIT 1;


-- =============================================================
-- TEST 7: Payslip count matches active employee count
-- =============================================================
SELECT '=== TEST 7: Payslip Count ===' AS test;
SELECT
    (SELECT COUNT(*) FROM employee WHERE status = 'active') AS active_employees,
    (SELECT COUNT(*) FROM payslip WHERE run_id = (SELECT MAX(run_id) FROM payroll_run)) AS payslips_generated,
    IF(
        (SELECT COUNT(*) FROM employee WHERE status = 'active') =
        (SELECT COUNT(*) FROM payslip WHERE run_id = (SELECT MAX(run_id) FROM payroll_run)),
        '✅ PASS', '❌ FAIL'
    ) AS result;


-- =============================================================
-- TEST 8: Payslip integrity — net_pay = gross - deductions - tax
-- =============================================================
SELECT '=== TEST 8: Payslip Integrity ===' AS test;
SELECT
    ps.payslip_id,
    CONCAT(e.first_name, ' ', e.last_name) AS employee,
    ps.gross_pay,
    ps.total_deductions,
    ps.tax_amount,
    ps.net_pay,
    ROUND(ps.gross_pay - ps.total_deductions - ps.tax_amount, 2) AS expected_net,
    IF(
        ps.net_pay = ROUND(ps.gross_pay - ps.total_deductions - ps.tax_amount, 2),
        '✅ PASS', '❌ FAIL'
    ) AS result
FROM payslip ps
JOIN employee e ON ps.emp_id = e.emp_id
WHERE ps.run_id = (SELECT MAX(run_id) FROM payroll_run);


-- =============================================================
-- TEST 9: Trigger — employee UPDATE writes to audit_log
-- =============================================================
SELECT '=== TEST 9: Audit Trigger on Employee Update ===' AS test;

-- Capture audit log count before
SET @before_count = (SELECT COUNT(*) FROM audit_log WHERE table_name = 'employee');

-- Trigger the update
UPDATE employee SET base_salary = 860000.00 WHERE emp_id = 1;

-- Capture after
SET @after_count = (SELECT COUNT(*) FROM audit_log WHERE table_name = 'employee');

SELECT
    @before_count AS audit_rows_before,
    @after_count  AS audit_rows_after,
    IF(@after_count > @before_count, '✅ PASS — trigger fired', '❌ FAIL — trigger did not fire') AS result;

-- Show the audit entry
SELECT * FROM audit_log WHERE table_name = 'employee' ORDER BY log_id DESC LIMIT 1;

-- Restore original salary
UPDATE employee SET base_salary = 850000.00 WHERE emp_id = 1;


-- =============================================================
-- TEST 10: Trigger — payslip UPDATE blocked on completed run
-- =============================================================
SELECT '=== TEST 10: Payslip Lock on Completed Run ===' AS test;
-- This should raise error 45000 — wrap in a procedure to catch it
DROP PROCEDURE IF EXISTS test_payslip_lock;
DELIMITER $$
CREATE PROCEDURE test_payslip_lock()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SELECT '✅ PASS — update correctly blocked on completed run' AS result;
    END;
    UPDATE payslip SET gross_pay = 0
    WHERE run_id = (SELECT MAX(run_id) FROM payroll_run WHERE status = 'completed')
    LIMIT 1;
    SELECT '❌ FAIL — update should have been blocked' AS result;
END$$
DELIMITER ;
CALL test_payslip_lock();
DROP PROCEDURE IF EXISTS test_payslip_lock;


-- =============================================================
-- TEST 11: Trigger — payroll_run status regression blocked
-- =============================================================
SELECT '=== TEST 11: Payroll Run Status Guard ===' AS test;
DROP PROCEDURE IF EXISTS test_run_status_guard;
DELIMITER $$
CREATE PROCEDURE test_run_status_guard()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SELECT '✅ PASS — status regression correctly blocked' AS result;
    END;
    UPDATE payroll_run SET status = 'draft'
    WHERE run_id = (SELECT MAX(run_id) FROM payroll_run WHERE status = 'completed');
    SELECT '❌ FAIL — status regression should have been blocked' AS result;
END$$
DELIMITER ;
CALL test_run_status_guard();
DROP PROCEDURE IF EXISTS test_run_status_guard;


-- =============================================================
-- TEST 12: FK enforcement — delete department with active employees
-- =============================================================
SELECT '=== TEST 12: FK RESTRICT on Department Delete ===' AS test;
DROP PROCEDURE IF EXISTS test_fk_restrict;
DELIMITER $$
CREATE PROCEDURE test_fk_restrict()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SELECT '✅ PASS — delete correctly blocked by FK RESTRICT' AS result;
    END;
    DELETE FROM department WHERE dept_id = 2;  -- Engineering has employees
    SELECT '❌ FAIL — delete should have been blocked' AS result;
END$$
DELIMITER ;
CALL test_fk_restrict();
DROP PROCEDURE IF EXISTS test_fk_restrict;


-- =============================================================
-- TEST 13: Role access — finance_viewer cannot read base_salary
-- =============================================================
SELECT '=== TEST 13: Role Permissions ===' AS test;
SELECT
    user  AS db_user,
    host,
    IF(user = 'finance_viewer', 'Should NOT see employee.base_salary directly', '') AS note
FROM mysql.user
WHERE user IN ('payroll_admin','hr_manager','finance_viewer','audit_viewer','app_service')
ORDER BY user;
-- ✅ All 5 users should appear
-- To fully test role isolation, connect as each user and attempt:
--   finance_viewer:  SELECT base_salary FROM employee;  → should be denied
--   audit_viewer:    SELECT * FROM payslip;             → should be denied
--   hr_manager:      CALL sp_run_payroll(...);          → should be denied
--   app_service:     DROP TABLE employee;               → should be denied


-- =============================================================
-- TEST 14: Indexes exist
-- =============================================================
SELECT '=== TEST 14: Indexes ===' AS test;
SELECT table_name, index_name, column_name, seq_in_index
FROM information_schema.statistics
WHERE table_schema = 'payroll_db'
  AND index_name != 'PRIMARY'
ORDER BY table_name, index_name, seq_in_index;
-- ✅ Should show all named indexes including ft_emp_name_title


-- =============================================================
-- TEST 15: Audit log populated after payroll run
-- =============================================================
SELECT '=== TEST 15: Audit Log Populated ===' AS test;
SELECT
    table_name,
    action,
    COUNT(*) AS entries
FROM audit_log
GROUP BY table_name, action
ORDER BY table_name;
-- ✅ Should show payslip/INSERT entries from TEST 6
--    and employee/UPDATE entries from TEST 9


-- =============================================================
-- SUMMARY
-- =============================================================
SELECT '=== VERIFICATION COMPLETE ===' AS '';
SELECT 'Review any ❌ FAIL results above before deploying.' AS note;
