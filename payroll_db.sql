-- =============================================================
--  PAYROLL MANAGEMENT SYSTEM — Nigeria PAYE
--  Database : payroll_db
--  Engine   : InnoDB  |  Charset: utf8mb4
--  Includes : Tables, Indexes, Seed Data, Views,
--             Stored Procedures, Triggers, Event Scheduler,
--             Roles & Security
-- =============================================================

-- =============================================================
-- SECURITY WARNING
-- All passwords below are placeholders only.
-- Change every password before deploying to any environment.
-- Never commit real credentials to version control.
-- =============================================================

DROP DATABASE IF EXISTS payroll_db;
CREATE DATABASE payroll_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE payroll_db;


-- =============================================================
-- 1. TABLES
-- =============================================================

-- 1.1 Department
CREATE TABLE department (
    dept_id    INT          AUTO_INCREMENT PRIMARY KEY,
    dept_name  VARCHAR(100) NOT NULL UNIQUE,
    manager_id INT          DEFAULT NULL,
    created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- 1.2 Employee
CREATE TABLE employee (
    emp_id      INT            AUTO_INCREMENT PRIMARY KEY,
    first_name  VARCHAR(50)    NOT NULL,
    last_name   VARCHAR(50)    NOT NULL,
    email       VARCHAR(100)   NOT NULL UNIQUE,
    phone       VARCHAR(20),
    hire_date   DATE           NOT NULL,
    job_title   VARCHAR(100)   NOT NULL,
    base_salary DECIMAL(12,2)  NOT NULL CHECK (base_salary > 0),
    dept_id     INT            NOT NULL,
    status      ENUM('active','inactive','terminated') DEFAULT 'active',
    created_at  TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_emp_dept FOREIGN KEY (dept_id)
        REFERENCES department(dept_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Resolve circular FK: department.manager_id → employee
ALTER TABLE department
    ADD CONSTRAINT fk_dept_manager FOREIGN KEY (manager_id)
        REFERENCES employee(emp_id)
        ON DELETE SET NULL ON UPDATE CASCADE;

-- 1.3 Allowance
CREATE TABLE allowance (
    allowance_id   INT           AUTO_INCREMENT PRIMARY KEY,
    emp_id         INT           NOT NULL,
    allowance_type VARCHAR(60)   NOT NULL,
    amount         DECIMAL(12,2) NOT NULL CHECK (amount >= 0),
    effective_from DATE          NOT NULL,
    effective_to   DATE          DEFAULT NULL,
    CONSTRAINT chk_allow_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT fk_allow_emp FOREIGN KEY (emp_id)
        REFERENCES employee(emp_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 1.4 Deduction
CREATE TABLE deduction (
    deduction_id   INT           AUTO_INCREMENT PRIMARY KEY,
    emp_id         INT           NOT NULL,
    deduction_type VARCHAR(60)   NOT NULL,
    amount         DECIMAL(12,2) NOT NULL CHECK (amount >= 0),
    effective_from DATE          NOT NULL,
    effective_to   DATE          DEFAULT NULL,
    CONSTRAINT chk_ded_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT fk_ded_emp FOREIGN KEY (emp_id)
        REFERENCES employee(emp_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 1.5 Tax Bracket (FIRS PAYE bands)
CREATE TABLE tax_bracket (
    bracket_id  INT           AUTO_INCREMENT PRIMARY KEY,
    min_income  DECIMAL(12,2) NOT NULL,
    max_income  DECIMAL(12,2) DEFAULT NULL,
    tax_rate    DECIMAL(5,4)  NOT NULL CHECK (tax_rate BETWEEN 0 AND 1),
    description VARCHAR(80),
    CONSTRAINT chk_income_range CHECK (max_income IS NULL OR max_income > min_income)
);

-- 1.6 Payroll Run
CREATE TABLE payroll_run (
    run_id           INT       AUTO_INCREMENT PRIMARY KEY,
    pay_period_start DATE      NOT NULL,
    pay_period_end   DATE      NOT NULL,
    payment_date     DATE      NOT NULL,
    status           ENUM('draft','processing','completed','cancelled','failed') DEFAULT 'draft',
    created_by       INT       DEFAULT NULL,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_period       CHECK (pay_period_end >= pay_period_start),
    CONSTRAINT chk_payment_date CHECK (payment_date >= pay_period_end),
    CONSTRAINT uq_pay_period    UNIQUE (pay_period_start, pay_period_end),
    CONSTRAINT fk_run_creator   FOREIGN KEY (created_by)
        REFERENCES employee(emp_id)
        ON DELETE SET NULL
);

-- 1.7 Payslip
CREATE TABLE payslip (
    payslip_id       INT           AUTO_INCREMENT PRIMARY KEY,
    run_id           INT           NOT NULL,
    emp_id           INT           NOT NULL,
    gross_pay        DECIMAL(12,2) NOT NULL CHECK (gross_pay >= 0),
    total_allowances DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_deductions DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_amount       DECIMAL(12,2) NOT NULL DEFAULT 0,
    net_pay          DECIMAL(12,2) NOT NULL,
    generated_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_payslip  UNIQUE (run_id, emp_id),
    CONSTRAINT fk_slip_run FOREIGN KEY (run_id)
        REFERENCES payroll_run(run_id) ON DELETE RESTRICT,
    CONSTRAINT fk_slip_emp FOREIGN KEY (emp_id)
        REFERENCES employee(emp_id)   ON DELETE RESTRICT
);

-- 1.8 Audit Log (ENUM action, dual-column identity)
CREATE TABLE audit_log (
    log_id      INT          AUTO_INCREMENT PRIMARY KEY,
    table_name  VARCHAR(60)  NOT NULL,
    record_id   INT          NOT NULL,
    action      ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    old_value   JSON         DEFAULT NULL,
    new_value   JSON         DEFAULT NULL,
    db_user     VARCHAR(100) DEFAULT (USER()),
    app_user_id INT          DEFAULT NULL,
    changed_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- 1.9 Payroll Config
CREATE TABLE payroll_config (
    config_key   VARCHAR(60)  PRIMARY KEY,
    config_value VARCHAR(100) NOT NULL,
    description  VARCHAR(200),
    updated_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);


-- =============================================================
-- 2. INDEXES
-- =============================================================

CREATE INDEX idx_emp_dept        ON employee(dept_id);
CREATE INDEX idx_emp_status      ON employee(status);
CREATE INDEX idx_emp_name        ON employee(last_name, first_name);

CREATE INDEX idx_allow_emp_date  ON allowance(emp_id, effective_from, effective_to);
CREATE INDEX idx_ded_emp_date    ON deduction(emp_id, effective_from, effective_to);

-- idx_slip_run omitted: covered by uq_payslip composite unique index (run_id leftmost)
CREATE INDEX idx_slip_emp        ON payslip(emp_id);

CREATE INDEX idx_audit_table     ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_date      ON audit_log(changed_at);

CREATE INDEX idx_tax_min         ON tax_bracket(min_income);

ALTER TABLE employee
    ADD FULLTEXT INDEX ft_emp_name_title (first_name, last_name, job_title);


-- =============================================================
-- 3. SEED DATA
-- =============================================================

-- 3.1 Departments (no managers yet — employees don't exist)
INSERT INTO department (dept_name) VALUES
    ('Human Resources'),
    ('Engineering'),
    ('Finance'),
    ('Marketing'),
    ('Operations');

-- 3.2 Employees
INSERT INTO employee
    (first_name, last_name, email, phone, hire_date, job_title, base_salary, dept_id, status)
VALUES
    ('Aisha',   'Okafor',   'aisha.okafor@company.com',    '08012345678', '2019-03-15', 'HR Manager',          850000.00, 1, 'active'),
    ('Emeka',   'Nwosu',    'emeka.nwosu@company.com',     '08023456789', '2020-06-01', 'Software Engineer',   720000.00, 2, 'active'),
    ('Fatima',  'Bello',    'fatima.bello@company.com',    '08034567890', '2021-01-10', 'Senior Accountant',   680000.00, 3, 'active'),
    ('Chidi',   'Eze',      'chidi.eze@company.com',       '08045678901', '2018-09-20', 'Marketing Lead',      750000.00, 4, 'active'),
    ('Ngozi',   'Adeyemi',  'ngozi.adeyemi@company.com',   '08056789012', '2022-04-05', 'Operations Analyst',  580000.00, 5, 'active'),
    ('Tunde',   'Fashola',  'tunde.fashola@company.com',   '08067890123', '2020-11-15', 'DevOps Engineer',     800000.00, 2, 'active'),
    ('Amara',   'Obiora',   'amara.obiora@company.com',    '08078901234', '2023-02-01', 'Finance Analyst',     560000.00, 3, 'active'),
    ('Ibrahim', 'Musa',     'ibrahim.musa@company.com',    '08089012345', '2017-07-30', 'Engineering Manager', 950000.00, 2, 'active'),
    ('Chioma',  'Obi',      'chioma.obi@company.com',      '08090123456', '2019-12-12', 'HR Specialist',       620000.00, 1, 'active'),
    ('Oluwole', 'Adeyinka', 'oluwole.adeyinka@company.com','08001234567', '2021-08-22', 'Software Engineer',   700000.00, 2, 'terminated');

-- 3.3 Wire up department managers
UPDATE department SET manager_id = 1 WHERE dept_id = 1;  -- Aisha   → HR
UPDATE department SET manager_id = 8 WHERE dept_id = 2;  -- Ibrahim → Engineering
UPDATE department SET manager_id = 3 WHERE dept_id = 3;  -- Fatima  → Finance
UPDATE department SET manager_id = 4 WHERE dept_id = 4;  -- Chidi   → Marketing
UPDATE department SET manager_id = 5 WHERE dept_id = 5;  -- Ngozi   → Operations

-- 3.4 Allowances
INSERT INTO allowance (emp_id, allowance_type, amount, effective_from) VALUES
    (1, 'Housing',    120000.00, '2023-01-01'),
    (1, 'Transport',   30000.00, '2023-01-01'),
    (2, 'Housing',     80000.00, '2023-01-01'),
    (2, 'Meal',        20000.00, '2023-01-01'),
    (3, 'Housing',     80000.00, '2023-01-01'),
    (4, 'Housing',    100000.00, '2023-01-01'),
    (4, 'Transport',   25000.00, '2023-01-01'),
    (5, 'Transport',   20000.00, '2023-01-01'),
    (6, 'Housing',    110000.00, '2023-01-01'),
    (7, 'Meal',        15000.00, '2023-01-01'),
    (8, 'Housing',    150000.00, '2023-01-01'),
    (8, 'Transport',   40000.00, '2023-01-01'),
    (9, 'Housing',     80000.00, '2023-01-01');

-- 3.5 Deductions
INSERT INTO deduction (emp_id, deduction_type, amount, effective_from) VALUES
    (1, 'Pension',          42500.00, '2023-01-01'),
    (1, 'Health Insurance', 15000.00, '2023-01-01'),
    (2, 'Pension',          36000.00, '2023-01-01'),
    (2, 'Health Insurance', 12000.00, '2023-01-01'),
    (3, 'Pension',          34000.00, '2023-01-01'),
    (4, 'Pension',          37500.00, '2023-01-01'),
    (4, 'Loan Repayment',   50000.00, '2023-01-01'),
    (5, 'Pension',          29000.00, '2023-01-01'),
    (6, 'Pension',          40000.00, '2023-01-01'),
    (7, 'Pension',          28000.00, '2023-01-01'),
    (8, 'Pension',          47500.00, '2023-01-01'),
    (8, 'Health Insurance', 20000.00, '2023-01-01'),
    (9, 'Pension',          31000.00, '2023-01-01');

-- 3.6 Tax Brackets (FIRS PAYE)
INSERT INTO tax_bracket (min_income, max_income, tax_rate, description) VALUES
    (0,        300000,  0.0700, 'Band 1 — 7%'),
    (300000,   600000,  0.1100, 'Band 2 — 11%'),
    (600000,  1100000,  0.1500, 'Band 3 — 15%'),
    (1100000, 1600000,  0.1900, 'Band 4 — 19%'),
    (1600000, 3200000,  0.2100, 'Band 5 — 21%'),
    (3200000,     NULL, 0.2400, 'Band 6 — 24%');

-- 3.7 Payroll Config
INSERT INTO payroll_config (config_key, config_value, description) VALUES
    ('pay_frequency',    'monthly',    'How often payroll runs'),
    ('pay_day',          '28',         'Day of month salaries are paid'),
    ('pay_period_start', '1',          'Day payroll period begins'),
    ('pension_rate',     '0.05',       'Employee pension contribution rate'),
    ('nhf_rate',         '0.025',      'National Housing Fund rate'),
    ('tax_year_start',   '01-01',      'Start month-day of tax year'),
    ('auto_run_enabled', 'true',       'Whether event scheduler runs payroll automatically'),
    ('next_run_date',    '2026-07-28', 'Date of next scheduled payroll run'),
    ('max_retries',      '3',          'How many times to retry a failed payroll run');


-- =============================================================
-- 4. VIEWS
-- =============================================================

-- 4.1 Active employee summary with department
CREATE OR REPLACE VIEW vw_active_employees AS
SELECT
    e.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    e.email,
    e.job_title,
    e.base_salary,
    e.hire_date,
    d.dept_name,
    e.status
FROM employee e
JOIN department d ON e.dept_id = d.dept_id
WHERE e.status = 'active';

-- 4.2 Employee payroll summary
CREATE OR REPLACE VIEW vw_employee_payroll_summary AS
SELECT
    e.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    e.base_salary,
    COALESCE(a.total_allowances, 0) AS total_allowances,
    COALESCE(d.total_deductions, 0) AS total_deductions,
    e.base_salary
        + COALESCE(a.total_allowances, 0)
        - COALESCE(d.total_deductions, 0) AS estimated_net
FROM employee e
LEFT JOIN (
    SELECT emp_id, SUM(amount) AS total_allowances
    FROM allowance
    WHERE effective_to IS NULL OR effective_to >= CURDATE()
    GROUP BY emp_id
) a ON e.emp_id = a.emp_id
LEFT JOIN (
    SELECT emp_id, SUM(amount) AS total_deductions
    FROM deduction
    WHERE effective_to IS NULL OR effective_to >= CURDATE()
    GROUP BY emp_id
) d ON e.emp_id = d.emp_id
WHERE e.status = 'active';

-- 4.3 Department headcount and salary cost
CREATE OR REPLACE VIEW vw_department_summary AS
SELECT
    d.dept_id,
    d.dept_name,
    CONCAT(m.first_name, ' ', m.last_name) AS manager_name,
    COUNT(e.emp_id)    AS headcount,
    SUM(e.base_salary) AS total_salary_cost,
    AVG(e.base_salary) AS avg_salary
FROM department d
LEFT JOIN employee e ON d.dept_id   = e.dept_id AND e.status = 'active'
LEFT JOIN employee m ON d.manager_id = m.emp_id
GROUP BY d.dept_id, d.dept_name, m.first_name, m.last_name;

-- 4.4 Latest payslips
CREATE OR REPLACE VIEW vw_latest_payslips AS
SELECT
    ps.payslip_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    d.dept_name,
    pr.pay_period_start,
    pr.pay_period_end,
    pr.payment_date,
    ps.gross_pay,
    ps.total_allowances,
    ps.total_deductions,
    ps.tax_amount,
    ps.net_pay
FROM payslip ps
JOIN payroll_run pr ON ps.run_id  = pr.run_id
JOIN employee    e  ON ps.emp_id  = e.emp_id
JOIN department  d  ON e.dept_id  = d.dept_id
WHERE pr.run_id = (
    SELECT MAX(run_id) FROM payroll_run WHERE status = 'completed'
);

-- 4.5 Audit trail (human-readable)
CREATE OR REPLACE VIEW vw_audit_trail AS
SELECT
    al.log_id,
    al.table_name,
    al.record_id,
    al.action,
    al.old_value,
    al.new_value,
    al.db_user,
    CONCAT(e.first_name, ' ', e.last_name) AS changed_by_name,
    al.changed_at
FROM audit_log al
LEFT JOIN employee e ON al.app_user_id = e.emp_id
ORDER BY al.changed_at DESC;


-- =============================================================
-- 5. STORED PROCEDURES
-- =============================================================

DELIMITER $$

-- 5.1 Calculate PAYE tax (progressive, cursor-based)
CREATE PROCEDURE sp_calculate_tax (
    IN  p_annual_income DECIMAL(12,2),
    OUT p_tax_amount    DECIMAL(12,2)
)
BEGIN
    DECLARE v_remaining DECIMAL(12,2);
    DECLARE v_band_min  DECIMAL(12,2);
    DECLARE v_band_max  DECIMAL(12,2);
    DECLARE v_rate      DECIMAL(5,4);
    DECLARE v_tax       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_taxable   DECIMAL(12,2);
    DECLARE done        INT DEFAULT 0;

    DECLARE cur CURSOR FOR
        SELECT min_income, max_income, tax_rate
        FROM tax_bracket ORDER BY min_income;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    SET v_remaining = p_annual_income;

    OPEN cur;
    band_loop: LOOP
        FETCH cur INTO v_band_min, v_band_max, v_rate;
        IF done OR v_remaining <= 0 THEN LEAVE band_loop; END IF;

        IF v_band_max IS NULL THEN
            SET v_taxable = v_remaining;
        ELSE
            SET v_taxable = LEAST(v_remaining, v_band_max - v_band_min);
        END IF;

        SET v_tax       = v_tax + (v_taxable * v_rate);
        SET v_remaining = v_remaining - v_taxable;
    END LOOP;
    CLOSE cur;

    SET p_tax_amount = ROUND(v_tax, 2);
END$$

-- 5.2 Generate payslip for a single employee
CREATE PROCEDURE sp_generate_payslip (
    IN p_run_id   INT,
    IN p_emp_id   INT,
    IN p_app_user INT
)
BEGIN
    DECLARE v_base_salary  DECIMAL(12,2);
    DECLARE v_allowances   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_deductions   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_gross        DECIMAL(12,2);
    DECLARE v_annual_tax   DECIMAL(12,2);
    DECLARE v_monthly_tax  DECIMAL(12,2);
    DECLARE v_net          DECIMAL(12,2);
    DECLARE v_period_start DATE;
    DECLARE v_period_end   DATE;

    SELECT pay_period_start, pay_period_end
    INTO v_period_start, v_period_end
    FROM payroll_run WHERE run_id = p_run_id;

    SELECT base_salary INTO v_base_salary
    FROM employee WHERE emp_id = p_emp_id AND status = 'active';

    IF v_base_salary IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Employee not found or not active';
    END IF;

    SELECT COALESCE(SUM(amount), 0) INTO v_allowances
    FROM allowance
    WHERE emp_id = p_emp_id
      AND effective_from <= v_period_end
      AND (effective_to IS NULL OR effective_to >= v_period_start);

    SELECT COALESCE(SUM(amount), 0) INTO v_deductions
    FROM deduction
    WHERE emp_id = p_emp_id
      AND effective_from <= v_period_end
      AND (effective_to IS NULL OR effective_to >= v_period_start);

    SET v_gross       = v_base_salary + v_allowances;
    CALL sp_calculate_tax(v_gross * 12, v_annual_tax);
    SET v_monthly_tax = ROUND(v_annual_tax / 12, 2);
    SET v_net         = v_gross - v_deductions - v_monthly_tax;

    -- Stash the initiating app user in a session variable so
    -- trg_payslip_after_insert can attribute the audit entry correctly.
    -- Triggers cannot see stored-procedure local/IN variables directly.
    SET @current_app_user = p_app_user;

    INSERT INTO payslip
        (run_id, emp_id, gross_pay, total_allowances, total_deductions, tax_amount, net_pay)
    VALUES
        (p_run_id, p_emp_id, v_gross, v_allowances, v_deductions, v_monthly_tax, v_net)
    ON DUPLICATE KEY UPDATE
        gross_pay        = v_gross,
        total_allowances = v_allowances,
        total_deductions = v_deductions,
        tax_amount       = v_monthly_tax,
        net_pay          = v_net,
        generated_at     = CURRENT_TIMESTAMP;

    -- Clear the session variable immediately after use so it can never
    -- leak into an unrelated payslip INSERT elsewhere in the session.
    SET @current_app_user = NULL;
END$$

-- 5.3 Run full payroll for all active employees
CREATE PROCEDURE sp_run_payroll (
    IN p_period_start DATE,
    IN p_period_end   DATE,
    IN p_payment_date DATE,
    IN p_created_by   INT
)
BEGIN
    DECLARE v_run_id INT;
    DECLARE v_emp_id INT;
    DECLARE done     INT DEFAULT 0;

    DECLARE emp_cur CURSOR FOR
        SELECT emp_id FROM employee WHERE status = 'active';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- If any employee's payslip generation throws an unhandled error
    -- (e.g. the SIGNAL in sp_generate_payslip), mark this run as 'failed'
    -- instead of leaving it silently stuck at 'processing' forever, then
    -- re-signal so the caller still sees the original error.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CLOSE emp_cur;
        UPDATE payroll_run SET status = 'failed' WHERE run_id = v_run_id;
        RESIGNAL;
    END;

    INSERT INTO payroll_run
        (pay_period_start, pay_period_end, payment_date, status, created_by)
    VALUES
        (p_period_start, p_period_end, p_payment_date, 'processing', p_created_by);

    SET v_run_id = LAST_INSERT_ID();

    OPEN emp_cur;
    emp_loop: LOOP
        FETCH emp_cur INTO v_emp_id;
        IF done THEN LEAVE emp_loop; END IF;
        CALL sp_generate_payslip(v_run_id, v_emp_id, p_created_by);
    END LOOP;
    CLOSE emp_cur;

    UPDATE payroll_run SET status = 'completed' WHERE run_id = v_run_id;

    SELECT v_run_id AS run_id, 'Payroll completed successfully' AS message;
END$$

-- 5.4 Get payslip detail for an employee in a run
CREATE PROCEDURE sp_get_payslip (
    IN p_emp_id INT,
    IN p_run_id INT
)
BEGIN
    SELECT
        CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
        e.job_title,
        d.dept_name,
        pr.pay_period_start,
        pr.pay_period_end,
        pr.payment_date,
        ps.gross_pay,
        ps.total_allowances,
        ps.total_deductions,
        ps.tax_amount,
        ps.net_pay,
        ps.generated_at
    FROM payslip ps
    JOIN employee    e  ON ps.emp_id = e.emp_id
    JOIN department  d  ON e.dept_id = d.dept_id
    JOIN payroll_run pr ON ps.run_id  = pr.run_id
    WHERE ps.emp_id = p_emp_id AND ps.run_id = p_run_id;
END$$

-- 5.5 Update employee salary with audit
CREATE PROCEDURE sp_update_salary (
    IN p_emp_id     INT,
    IN p_new_salary DECIMAL(12,2),
    IN p_app_user   INT
)
BEGIN
    -- Stash the initiating app user in a session variable so
    -- trg_employee_after_update can attribute the audit entry correctly.
    -- The trigger is the single source of truth for employee-change
    -- auditing (salary, status, job_title, dept_id) — this procedure no
    -- longer writes its own audit_log row to avoid a duplicate,
    -- inconsistent entry alongside the trigger's.
    SET @current_app_user = p_app_user;

    UPDATE employee SET base_salary = p_new_salary WHERE emp_id = p_emp_id;

    SET @current_app_user = NULL;
END$$

-- 5.6 Free-text employee search (name and/or job title)
-- Backs ft_emp_name_title. Uses NATURAL LANGUAGE MODE so results are
-- ranked by relevance rather than returned in arbitrary order, and so
-- callers can pass loose/partial search terms (e.g. "chief account")
-- instead of needing an exact match. Falls back to BOOLEAN MODE with a
-- trailing wildcard when the caller passes a single short word, since
-- NATURAL LANGUAGE MODE ignores words below the built-in minimum length
-- (4 characters for InnoDB) and applies the standard stopword list.
CREATE PROCEDURE sp_search_employees (
    IN p_search_term VARCHAR(100)
)
BEGIN
    IF TRIM(p_search_term) = '' OR p_search_term IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Search term cannot be empty';
    END IF;

    IF LOCATE(' ', TRIM(p_search_term)) = 0 THEN
        SELECT
            e.emp_id,
            CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
            e.job_title,
            d.dept_name,
            e.status,
            MATCH(e.first_name, e.last_name, e.job_title)
                AGAINST(CONCAT(p_search_term, '*') IN BOOLEAN MODE) AS relevance
        FROM employee e
        JOIN department d ON e.dept_id = d.dept_id
        WHERE MATCH(e.first_name, e.last_name, e.job_title)
              AGAINST(CONCAT(p_search_term, '*') IN BOOLEAN MODE)
        ORDER BY relevance DESC;
    ELSE
        SELECT
            e.emp_id,
            CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
            e.job_title,
            d.dept_name,
            e.status,
            MATCH(e.first_name, e.last_name, e.job_title)
                AGAINST(p_search_term IN NATURAL LANGUAGE MODE) AS relevance
        FROM employee e
        JOIN department d ON e.dept_id = d.dept_id
        WHERE MATCH(e.first_name, e.last_name, e.job_title)
              AGAINST(p_search_term IN NATURAL LANGUAGE MODE)
        ORDER BY relevance DESC;
    END IF;
END$$

DELIMITER ;


-- =============================================================
-- 6. TRIGGERS
-- =============================================================

DELIMITER $$

-- 6.1 Audit: employee UPDATE
CREATE TRIGGER trg_employee_after_update
AFTER UPDATE ON employee FOR EACH ROW
BEGIN
    IF OLD.base_salary <> NEW.base_salary
    OR OLD.status      <> NEW.status
    OR OLD.job_title   <> NEW.job_title
    OR OLD.dept_id     <> NEW.dept_id
    THEN
        INSERT INTO audit_log
            (table_name, record_id, action, old_value, new_value, db_user, app_user_id)
        VALUES (
            'employee', OLD.emp_id, 'UPDATE',
            JSON_OBJECT(
                'base_salary', OLD.base_salary, 'status', OLD.status,
                'job_title',   OLD.job_title,   'dept_id', OLD.dept_id),
            JSON_OBJECT(
                'base_salary', NEW.base_salary, 'status', NEW.status,
                'job_title',   NEW.job_title,   'dept_id', NEW.dept_id),
            USER(),
            @current_app_user
        );
    END IF;
END$$

-- 6.2 Audit: employee DELETE
CREATE TRIGGER trg_employee_after_delete
AFTER DELETE ON employee FOR EACH ROW
BEGIN
    INSERT INTO audit_log
        (table_name, record_id, action, old_value, db_user, app_user_id)
    VALUES (
        'employee', OLD.emp_id, 'DELETE',
        JSON_OBJECT(
            'first_name', OLD.first_name, 'last_name',   OLD.last_name,
            'email',      OLD.email,      'base_salary', OLD.base_salary,
            'status',     OLD.status),
        USER(),
        @current_app_user
    );
END$$

-- 6.3 Audit: payslip INSERT
CREATE TRIGGER trg_payslip_after_insert
AFTER INSERT ON payslip FOR EACH ROW
BEGIN
    INSERT INTO audit_log
        (table_name, record_id, action, new_value, db_user, app_user_id)
    VALUES (
        'payslip', NEW.payslip_id, 'INSERT',
        JSON_OBJECT(
            'run_id',           NEW.run_id,
            'emp_id',           NEW.emp_id,
            'gross_pay',        NEW.gross_pay,
            'total_allowances', NEW.total_allowances,
            'total_deductions', NEW.total_deductions,
            'tax_amount',       NEW.tax_amount,
            'net_pay',          NEW.net_pay),
        USER(),
        @current_app_user
    );
END$$

-- 6.4 Prevent payslip edits on completed runs
CREATE TRIGGER trg_payslip_before_update
BEFORE UPDATE ON payslip FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT status INTO v_status FROM payroll_run WHERE run_id = OLD.run_id;
    IF v_status = 'completed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot modify payslip: payroll run is already completed';
    END IF;
END$$

-- 6.5 Prevent payroll_run status regression
CREATE TRIGGER trg_payroll_run_before_update
BEFORE UPDATE ON payroll_run FOR EACH ROW
BEGIN
    IF OLD.status = 'completed' AND NEW.status NOT IN ('completed','cancelled') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot revert a completed payroll run';
    END IF;
END$$

-- 6.6 Audit: allowance INSERT
CREATE TRIGGER trg_allowance_after_insert
AFTER INSERT ON allowance FOR EACH ROW
BEGIN
    INSERT INTO audit_log
        (table_name, record_id, action, new_value, db_user, app_user_id)
    VALUES (
        'allowance', NEW.allowance_id, 'INSERT',
        JSON_OBJECT(
            'emp_id', NEW.emp_id, 'allowance_type', NEW.allowance_type,
            'amount', NEW.amount),
        USER(),
        @current_app_user
    );
END$$

-- 6.7 Audit: deduction INSERT
CREATE TRIGGER trg_deduction_after_insert
AFTER INSERT ON deduction FOR EACH ROW
BEGIN
    INSERT INTO audit_log
        (table_name, record_id, action, new_value, db_user, app_user_id)
    VALUES (
        'deduction', NEW.deduction_id, 'INSERT',
        JSON_OBJECT(
            'emp_id', NEW.emp_id, 'deduction_type', NEW.deduction_type,
            'amount', NEW.amount),
        USER(),
        @current_app_user
    );
END$$

DELIMITER ;


-- =============================================================
-- 7. EVENT SCHEDULER (automated monthly payroll)
-- =============================================================

SET GLOBAL event_scheduler = ON;

-- MySQL/MariaDB do not allow subqueries inside a CREATE EVENT's
-- ON SCHEDULE/STARTS clause. Compute the configured pay_day into a
-- session variable first (a plain SET, not restricted), then reference
-- that variable directly in STARTS as a scalar expression.
SET @evt_pay_day = (SELECT config_value FROM payroll_config WHERE config_key = 'pay_day');

DELIMITER $$

CREATE EVENT IF NOT EXISTS evt_monthly_payroll
ON SCHEDULE EVERY 1 MONTH
STARTS STR_TO_DATE(
    CONCAT(
        YEAR(CURDATE()), '-',
        LPAD(MONTH(CURDATE()), 2, '0'), '-',
        @evt_pay_day
    ), '%Y-%m-%d'
)
DO
BEGIN
    DECLARE v_period_start DATE;
    DECLARE v_period_end   DATE;
    DECLARE v_payment_date DATE;
    DECLARE v_pay_day      INT;
    DECLARE v_enabled      VARCHAR(10);

    SELECT config_value INTO v_enabled
    FROM payroll_config WHERE config_key = 'auto_run_enabled';

    IF v_enabled = 'true' THEN
        SELECT CAST(config_value AS UNSIGNED) INTO v_pay_day
        FROM payroll_config WHERE config_key = 'pay_day';

        SET v_period_start = DATE_FORMAT(CURDATE(), '%Y-%m-01');
        SET v_period_end   = LAST_DAY(CURDATE());
        SET v_payment_date = DATE_FORMAT(CURDATE(),
                                CONCAT('%Y-%m-', LPAD(v_pay_day, 2, '0')));

        CALL sp_run_payroll(v_period_start, v_period_end, v_payment_date, NULL);

        UPDATE payroll_config
        SET config_value = DATE_FORMAT(
                DATE_ADD(CURDATE(), INTERVAL 1 MONTH),
                CONCAT('%Y-%m-', LPAD(v_pay_day, 2, '0')))
        WHERE config_key = 'next_run_date';
    END IF;
END$$

DELIMITER ;


-- =============================================================
-- 8. ROLES & SECURITY
-- =============================================================

-- ⚠️  IMPORTANT: Change ALL passwords before deploying to any environment.
--     Never commit real credentials to version control.

-- -------------------------------------------------------------
-- 8.1 payroll_admin
--     Full control: run payroll, manage employees, view everything
-- -------------------------------------------------------------
CREATE USER IF NOT EXISTS 'payroll_admin'@'%' IDENTIFIED BY 'Change_Me_Admin!2024';

GRANT ALL PRIVILEGES ON payroll_db.* TO 'payroll_admin'@'%';

-- -------------------------------------------------------------
-- 8.2 hr_manager
--     Manage employees, allowances, deductions
--     Cannot execute payroll runs or view audit log
-- -------------------------------------------------------------
CREATE USER IF NOT EXISTS 'hr_manager'@'%' IDENTIFIED BY 'Change_Me_HR!2024';

GRANT SELECT, INSERT, UPDATE ON payroll_db.employee    TO 'hr_manager'@'%';
GRANT SELECT, INSERT, UPDATE ON payroll_db.allowance   TO 'hr_manager'@'%';
GRANT SELECT, INSERT, UPDATE ON payroll_db.deduction   TO 'hr_manager'@'%';
GRANT SELECT                 ON payroll_db.department  TO 'hr_manager'@'%';
GRANT SELECT                 ON payroll_db.vw_active_employees        TO 'hr_manager'@'%';
GRANT SELECT                 ON payroll_db.vw_employee_payroll_summary TO 'hr_manager'@'%';
GRANT SELECT                 ON payroll_db.vw_department_summary       TO 'hr_manager'@'%';
GRANT EXECUTE                ON PROCEDURE payroll_db.sp_update_salary  TO 'hr_manager'@'%';

-- -------------------------------------------------------------
-- 8.3 finance_viewer
--     Read-only access to payslips, payroll runs, and reports
--     Cannot see raw employee salary data directly
-- -------------------------------------------------------------
CREATE USER IF NOT EXISTS 'finance_viewer'@'%' IDENTIFIED BY 'Change_Me_Finance!2024';

GRANT SELECT ON payroll_db.payroll_run              TO 'finance_viewer'@'%';
GRANT SELECT ON payroll_db.payslip                  TO 'finance_viewer'@'%';
GRANT SELECT ON payroll_db.vw_latest_payslips       TO 'finance_viewer'@'%';
GRANT SELECT ON payroll_db.vw_department_summary    TO 'finance_viewer'@'%';
GRANT EXECUTE ON PROCEDURE payroll_db.sp_get_payslip TO 'finance_viewer'@'%';

-- -------------------------------------------------------------
-- 8.4 audit_viewer
--     Read-only access to audit log only
--     Suitable for compliance and security review
-- -------------------------------------------------------------
CREATE USER IF NOT EXISTS 'audit_viewer'@'%' IDENTIFIED BY 'Change_Me_Audit!2024';

GRANT SELECT ON payroll_db.audit_log        TO 'audit_viewer'@'%';
GRANT SELECT ON payroll_db.vw_audit_trail   TO 'audit_viewer'@'%';

-- -------------------------------------------------------------
-- 8.5 app_service
--     Application service account — least privilege
--     Only what the payroll application needs at runtime
-- -------------------------------------------------------------
CREATE USER IF NOT EXISTS 'app_service'@'%' IDENTIFIED BY 'Change_Me_App!2024';

GRANT SELECT        ON payroll_db.employee       TO 'app_service'@'%';
GRANT SELECT        ON payroll_db.department     TO 'app_service'@'%';
GRANT SELECT        ON payroll_db.allowance      TO 'app_service'@'%';
GRANT SELECT        ON payroll_db.deduction      TO 'app_service'@'%';
GRANT SELECT        ON payroll_db.tax_bracket    TO 'app_service'@'%';
GRANT SELECT        ON payroll_db.payroll_config TO 'app_service'@'%';
GRANT SELECT,INSERT ON payroll_db.payroll_run    TO 'app_service'@'%';
GRANT SELECT,INSERT ON payroll_db.payslip        TO 'app_service'@'%';
GRANT INSERT        ON payroll_db.audit_log      TO 'app_service'@'%';
GRANT EXECUTE ON PROCEDURE payroll_db.sp_run_payroll      TO 'app_service'@'%';
GRANT EXECUTE ON PROCEDURE payroll_db.sp_generate_payslip TO 'app_service'@'%';
GRANT EXECUTE ON PROCEDURE payroll_db.sp_get_payslip      TO 'app_service'@'%';
GRANT EXECUTE ON PROCEDURE payroll_db.sp_calculate_tax    TO 'app_service'@'%';

FLUSH PRIVILEGES;


-- =============================================================
-- 9. VERIFICATION QUERIES (uncomment to test after loading)
-- =============================================================

-- SHOW TABLES;
-- SELECT * FROM vw_active_employees;
-- SELECT * FROM vw_employee_payroll_summary;
-- SELECT * FROM vw_department_summary;
-- SELECT * FROM payroll_config;

-- -- Run payroll and verify output
-- CALL sp_run_payroll('2026-06-01','2026-06-30','2026-06-28', 1);
-- SELECT * FROM vw_latest_payslips;
-- SELECT * FROM audit_log;

-- -- Test role access (connect as each user and run):
-- -- CALL sp_get_payslip(1, 1);
-- -- SELECT * FROM vw_audit_trail;
