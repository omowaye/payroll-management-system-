# Performance Tuning Guide — payroll_db

Performance tuning ensures that `payroll_db` remains responsive under real-world conditions —
monthly payroll runs processing all active employees, growing audit logs, concurrent HR
updates, and analytics queries running alongside live transactions. This guide covers query
optimization, InnoDB configuration, slow query log analysis, stored procedure tuning,
audit log maintenance, and key MySQL configuration settings.

---

## Table of Contents

- [Performance Baseline](#performance-baseline)
- [EXPLAIN Analysis](#explain-analysis)
- [Index Effectiveness Verification](#index-effectiveness-verification)
- [Slow Query Log](#slow-query-log)
- [InnoDB Buffer Pool Tuning](#innodb-buffer-pool-tuning)
- [Stored Procedure Optimization](#stored-procedure-optimization)
- [Audit Log Maintenance](#audit-log-maintenance)
- [MySQL Configuration Recommendations](#mysql-configuration-recommendations)
- [Connection Pooling](#connection-pooling)
- [Performance Monitoring Queries](#performance-monitoring-queries)
- [Performance Tuning Checklist](#performance-tuning-checklist)

---

## Performance Baseline

Before tuning anything, establish a baseline. Run these queries and record the results
so you can measure improvement after each change:

```sql
-- 1. Check current InnoDB buffer pool hit rate
--    Target: > 99% — if lower, increase buffer pool size
SELECT
    FORMAT(
        (1 - (
            SELECT variable_value FROM performance_schema.global_status
            WHERE variable_name = 'Innodb_buffer_pool_reads'
        ) /
        (
            SELECT variable_value FROM performance_schema.global_status
            WHERE variable_name = 'Innodb_buffer_pool_read_requests'
        )) * 100, 2
    ) AS buffer_pool_hit_rate_pct;

-- 2. Check table sizes
SELECT
    table_name,
    ROUND(data_length / 1024 / 1024, 2)  AS data_mb,
    ROUND(index_length / 1024 / 1024, 2) AS index_mb,
    table_rows                            AS est_rows
FROM information_schema.tables
WHERE table_schema = 'payroll_db'
ORDER BY data_length DESC;

-- 3. Check for tables with no primary key (should be none)
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'payroll_db'
  AND table_name NOT IN (
      SELECT DISTINCT table_name
      FROM information_schema.statistics
      WHERE table_schema = 'payroll_db'
        AND index_name = 'PRIMARY'
  );
-- Expected: 0 rows — all payroll_db tables have primary keys
```

---

## EXPLAIN Analysis

`EXPLAIN` shows how MySQL executes a query — which indexes it uses, how many rows it
scans, and whether it's doing a full table scan. Always run `EXPLAIN` before and after
any query optimization.

### Key EXPLAIN columns to watch

| Column | What to look for |
|---|---|
| `type` | `const` / `eq_ref` / `ref` = good. `ALL` = full table scan = bad |
| `key` | Should show the index being used. `NULL` = no index used |
| `rows` | Estimated rows scanned — lower is better |
| `Extra` | `Using index` = covering index (fast). `Using filesort` / `Using temporary` = warning signs |

### EXPLAIN on common payroll queries

**Query 1: Active employee lookup by department**

```sql
EXPLAIN
SELECT emp_id, first_name, last_name, base_salary
FROM employee
WHERE dept_id = 2 AND status = 'active';
```

Expected output:
```
type: ref  |  key: idx_emp_dept  |  rows: ~3  |  Extra: Using where
```
Good — `idx_emp_dept` is used. If `key` shows NULL, the index is not being picked up.

**Query 2: Allowance lookup for a payroll run period**

```sql
EXPLAIN
SELECT emp_id, SUM(amount) AS total_allowances
FROM allowance
WHERE emp_id = 1
  AND effective_from <= '2026-06-30'
  AND (effective_to IS NULL OR effective_to >= '2026-06-01')
GROUP BY emp_id;
```

Expected output:
```
type: ref  |  key: idx_allow_emp_date  |  rows: ~2  |  Extra: Using where
```
Good — composite index `idx_allow_emp_date (emp_id, effective_from, effective_to)` covers
all three filter columns.

**Query 3: Audit log lookup for a specific record**

```sql
EXPLAIN
SELECT * FROM audit_log
WHERE table_name = 'employee' AND record_id = 1
ORDER BY changed_at DESC;
```

Expected output:
```
type: ref  |  key: idx_audit_table  |  rows: ~5  |  Extra: Using where; Using filesort
```
`Using filesort` on `changed_at` is acceptable here since the result set is small.
If the audit log grows very large, consider adding a composite index:

```sql
-- Add if audit log ORDER BY changed_at becomes slow
ALTER TABLE audit_log
    ADD INDEX idx_audit_table_date (table_name, record_id, changed_at);
-- This makes idx_audit_table redundant — drop it after adding:
DROP INDEX idx_audit_table ON audit_log;
```

**Query 4: Latest payslip view — check join performance**

```sql
EXPLAIN
SELECT * FROM vw_latest_payslips;
```

Watch for:
- `payroll_run` subquery (`SELECT MAX(run_id)`) — should use PRIMARY key scan, 1 row
- `payslip` join on `run_id` — should use `uq_payslip` unique index
- `employee` join on `emp_id` — should use PRIMARY key
- `department` join on `dept_id` — should use PRIMARY key

If any join shows `type: ALL`, add the missing index on that join column.

**Query 5: FULLTEXT search on employee name**

```sql
-- Correct FULLTEXT syntax — must use MATCH...AGAINST
EXPLAIN
SELECT emp_id, first_name, last_name, job_title
FROM employee
WHERE MATCH(first_name, last_name, job_title) AGAINST ('engineer' IN BOOLEAN MODE);
```

Expected output:
```
type: fulltext  |  key: ft_emp_name_title  |  rows: ~2  |  Extra: Using where
```

> ⚠️ Never use `LIKE '%engineer%'` on large employee tables — it forces a full table scan
> and ignores `ft_emp_name_title`. Always use `MATCH...AGAINST` for name/title searches.

---

## Index Effectiveness Verification

After loading data and running at least one payroll cycle, verify indexes are being used
and identify any that are redundant or missing:

```sql
-- 1. Check all indexes on payroll_db tables
SELECT
    table_name,
    index_name,
    GROUP_CONCAT(column_name ORDER BY seq_in_index) AS columns,
    index_type,
    non_unique
FROM information_schema.statistics
WHERE table_schema = 'payroll_db'
ORDER BY table_name, index_name;

-- 2. Find unused indexes (requires performance_schema — MySQL 8.0+)
SELECT
    object_schema,
    object_name  AS table_name,
    index_name
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = 'payroll_db'
  AND index_name IS NOT NULL
  AND index_name != 'PRIMARY'
  AND count_star = 0
ORDER BY object_name, index_name;
-- Any index appearing here after sustained workload is a candidate for removal

-- 3. Verify idx_slip_run is NOT present (covered by uq_payslip)
SELECT index_name FROM information_schema.statistics
WHERE table_schema = 'payroll_db'
  AND table_name   = 'payslip'
  AND index_name   = 'idx_slip_run';
-- Expected: 0 rows — this index was intentionally omitted

-- 4. Check for duplicate indexes (indexes covering same leading columns)
SELECT
    s1.table_name,
    s1.index_name  AS index_1,
    s2.index_name  AS index_2,
    s1.column_name AS column_name
FROM information_schema.statistics s1
JOIN information_schema.statistics s2
    ON  s1.table_schema  = s2.table_schema
    AND s1.table_name    = s2.table_name
    AND s1.column_name   = s2.column_name
    AND s1.seq_in_index  = s2.seq_in_index
    AND s1.index_name   != s2.index_name
WHERE s1.table_schema = 'payroll_db'
  AND s1.seq_in_index = 1
ORDER BY s1.table_name, s1.index_name;
```

---

## Slow Query Log

The slow query log captures queries that take longer than a defined threshold. For a
payroll system, any query exceeding 1 second during a payroll run is worth investigating.

### Enable slow query log

Add to `/etc/mysql/mysql.conf.d/mysqld.cnf`:

```ini
[mysqld]
slow_query_log         = 1
slow_query_log_file    = /var/log/mysql/slow-queries.log
long_query_time        = 1
log_queries_not_using_indexes = 1
```

Or enable at runtime without restarting (resets on server restart):

```sql
SET GLOBAL slow_query_log        = 'ON';
SET GLOBAL long_query_time       = 1;
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Verify
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';
```

### Analyse slow query log with mysqldumpslow

```bash
# Top 10 slowest queries by average execution time
mysqldumpslow -s at -t 10 /var/log/mysql/slow-queries.log

# Top 10 most frequently appearing slow queries
mysqldumpslow -s c -t 10 /var/log/mysql/slow-queries.log

# Filter slow queries related to payroll_db only
grep -A5 'payroll_db' /var/log/mysql/slow-queries.log | head -50
```

### What to look for in payroll_db slow queries

| Slow query pattern | Likely cause | Fix |
|---|---|---|
| `SELECT ... FROM audit_log WHERE ...` | Table growing too large | Archive old rows (see Audit Log Maintenance) |
| `SELECT ... FROM payslip WHERE run_id = ...` | Missing or unused index | Verify `uq_payslip` is being used |
| `CALL sp_run_payroll(...)` taking > 5s | Cursor loop inefficiency | See Stored Procedure Optimization |
| `SELECT ... FROM allowance WHERE emp_id = ...` | Date range filter not using index | Verify `idx_allow_emp_date` |
| Analytics queries timing out | Full table scans on large result sets | Add `LIMIT`, run analytics during off-peak hours |

---

## InnoDB Buffer Pool Tuning

The InnoDB buffer pool caches table data and indexes in memory. Sizing it correctly is
the single most impactful MySQL performance setting for a payroll workload.

### Check current buffer pool size

```sql
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
-- Default: 128MB — usually too small for production
```

### Recommended sizing

| Environment | RAM | Recommended buffer pool size |
|---|---|---|
| Local dev / portfolio demo | 4 GB | 512 MB – 1 GB |
| Small production (< 1000 employees) | 8 GB | 4 – 5 GB |
| Medium production (1000–10000 employees) | 16 GB | 10 – 12 GB |

General rule: allocate **50–70% of available RAM** to the buffer pool on a dedicated
database server.

### Set buffer pool size

In `/etc/mysql/mysql.conf.d/mysqld.cnf`:

```ini
[mysqld]
innodb_buffer_pool_size = 1G
innodb_buffer_pool_instances = 2   # 1 instance per 1GB of buffer pool
```

Or at runtime (MySQL 8.0+ — takes effect immediately, no restart needed):

```sql
SET GLOBAL innodb_buffer_pool_size = 1073741824;  -- 1 GB in bytes
```

### Monitor buffer pool efficiency

```sql
-- Buffer pool hit rate — target > 99%
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';

-- Reads from disk (bad) vs reads from buffer (good)
SELECT
    variable_name,
    variable_value
FROM performance_schema.global_status
WHERE variable_name IN (
    'Innodb_buffer_pool_reads',
    'Innodb_buffer_pool_read_requests',
    'Innodb_buffer_pool_pages_data',
    'Innodb_buffer_pool_pages_free'
);
```

---

## Stored Procedure Optimization

### sp_run_payroll — cursor loop performance

`sp_run_payroll` uses a cursor to iterate over all active employees and calls
`sp_generate_payslip` for each one. For small employee counts (< 1000) this is
fine. For larger datasets, consider these optimizations:

**1. Verify the cursor uses the status index**

The cursor query is:
```sql
SELECT emp_id FROM employee WHERE status = 'active';
```
This uses `idx_emp_status`. Confirm with:
```sql
EXPLAIN SELECT emp_id FROM employee WHERE status = 'active';
-- key should show: idx_emp_status
```

**2. Wrap the full run in a single transaction**

Currently each `sp_generate_payslip` call commits independently. For better
performance and atomicity on large payrolls, wrap the entire run:

```sql
-- Add to sp_run_payroll after creating the run record:
START TRANSACTION;
-- ... cursor loop calling sp_generate_payslip ...
COMMIT;
```

This reduces the number of disk flushes from N (one per employee) to 1 (at the end),
which can significantly speed up large payroll runs.

**3. Monitor procedure execution time**

```sql
-- Enable profiling (session-level)
SET profiling = 1;

CALL sp_run_payroll('2026-06-01', '2026-06-30', '2026-06-28', 1);

SHOW PROFILES;
-- Shows total execution time

SHOW PROFILE FOR QUERY 1;
-- Shows time breakdown by operation (sending data, sorting, etc.)

SET profiling = 0;
```

### sp_calculate_tax — cursor vs set-based

The tax cursor processes one band at a time. For a small fixed number of tax bands
(6 in FIRS PAYE), the cursor is fast enough. But you can benchmark it against a
set-based alternative:

```sql
-- Set-based alternative for sp_calculate_tax (no cursor)
-- Useful if tax bands grow significantly
SELECT
    SUM(
        CASE
            WHEN p_annual_income >= min_income THEN
                (LEAST(p_annual_income, COALESCE(max_income, p_annual_income))
                 - min_income) * tax_rate
            ELSE 0
        END
    ) AS total_tax
FROM tax_bracket
WHERE p_annual_income > min_income;
```

For 6 bands the difference is negligible. For 50+ bands the set-based approach
would be meaningfully faster.

---

## Audit Log Maintenance

The `audit_log` table grows with every INSERT, UPDATE, and DELETE across the system.
Without maintenance it will eventually slow down queries and consume excessive disk space.

### Monitor audit log growth

```sql
-- Current audit log size and row count
SELECT
    ROUND(data_length / 1024 / 1024, 2) AS data_mb,
    ROUND(index_length / 1024 / 1024, 2) AS index_mb,
    table_rows AS estimated_rows
FROM information_schema.tables
WHERE table_schema = 'payroll_db'
  AND table_name = 'audit_log';

-- Row count by month
SELECT
    DATE_FORMAT(changed_at, '%Y-%m') AS month,
    COUNT(*) AS rows_added
FROM audit_log
GROUP BY month
ORDER BY month;
```

### Archive old audit records

Never delete audit records — archive them to a separate table first:

```sql
-- Create archive table (run once)
CREATE TABLE IF NOT EXISTS audit_log_archive LIKE audit_log;

-- Archive records older than 1 year
INSERT INTO audit_log_archive
SELECT * FROM audit_log
WHERE changed_at < DATE_SUB(NOW(), INTERVAL 1 YEAR);

-- Verify archive count matches before deleting
SELECT COUNT(*) FROM audit_log
WHERE changed_at < DATE_SUB(NOW(), INTERVAL 1 YEAR);

SELECT COUNT(*) FROM audit_log_archive;

-- Delete archived records from live table only after verifying counts match
DELETE FROM audit_log
WHERE changed_at < DATE_SUB(NOW(), INTERVAL 1 YEAR);
```

### Automate audit log archiving with an event

```sql
DELIMITER $$

CREATE EVENT IF NOT EXISTS evt_archive_audit_log
ON SCHEDULE EVERY 1 MONTH
STARTS '2027-01-01 03:00:00'
DO
BEGIN
    -- Archive rows older than 1 year
    INSERT INTO audit_log_archive
    SELECT * FROM audit_log
    WHERE changed_at < DATE_SUB(NOW(), INTERVAL 1 YEAR);

    -- Remove archived rows from live table
    DELETE FROM audit_log
    WHERE changed_at < DATE_SUB(NOW(), INTERVAL 1 YEAR);
END$$

DELIMITER ;
```

### Optimize audit_log after large deletes

After deleting a large number of rows, reclaim disk space and rebuild the index:

```bash
# Rebuild table and indexes (causes brief lock — run during off-peak hours)
mysqlcheck --user=root --password --optimize payroll_db audit_log
```

Or in SQL:

```sql
OPTIMIZE TABLE audit_log;
-- Note: OPTIMIZE TABLE on InnoDB rebuilds the table — brief lock on small tables,
-- longer on large ones. Schedule during off-peak hours (e.g. after payroll run completes)
```

---

## MySQL Configuration Recommendations

Key settings in `/etc/mysql/mysql.conf.d/mysqld.cnf` for a payroll workload:

```ini
[mysqld]

# ── Memory ──────────────────────────────────────────────────────────────────
innodb_buffer_pool_size     = 1G        # 50-70% of RAM on dedicated server
innodb_buffer_pool_instances = 2        # 1 per GB of buffer pool
innodb_log_file_size        = 256M      # Larger = faster writes, slower recovery
innodb_log_buffer_size      = 64M       # Buffer for transaction log writes

# ── Durability vs Performance trade-off ─────────────────────────────────────
# For payroll data: NEVER set innodb_flush_log_at_trx_commit to 0 or 2
# 1 = flush to disk on every commit (safest — required for financial data)
innodb_flush_log_at_trx_commit = 1
sync_binlog                    = 1      # Sync binary log on every commit

# ── Connections ─────────────────────────────────────────────────────────────
max_connections             = 100       # Adjust based on expected concurrent users
thread_cache_size           = 10        # Reuse threads instead of creating new ones
wait_timeout                = 300       # Close idle connections after 5 minutes
interactive_timeout         = 300

# ── Query cache (disabled in MySQL 8.0 — do not set) ────────────────────────
# query_cache_type = 0  ← already removed in MySQL 8.0

# ── Slow query log ──────────────────────────────────────────────────────────
slow_query_log              = 1
slow_query_log_file         = /var/log/mysql/slow-queries.log
long_query_time             = 1
log_queries_not_using_indexes = 1

# ── Binary logging ──────────────────────────────────────────────────────────
log_bin                     = /var/log/mysql/mysql-bin.log
binlog_format               = ROW
expire_logs_days            = 14
max_binlog_size             = 100M
server_id                   = 1

# ── InnoDB I/O ──────────────────────────────────────────────────────────────
innodb_flush_method         = O_DIRECT  # Avoid double-buffering on Linux
innodb_io_capacity          = 200       # IOPS available to InnoDB (SSD: 2000+)
innodb_read_io_threads      = 4
innodb_write_io_threads     = 4
```

> **Aiven note:** Most of these settings are managed by Aiven and cannot be changed
> directly via `my.cnf`. Use the **Advanced Configuration** panel in your Aiven Console
> to adjust available parameters (buffer pool size, `long_query_time`, etc.).

---

## Connection Pooling

The `app_service` account connects to the database at runtime. Without connection
pooling, every API request opens and closes a new MySQL connection — expensive for
a payroll system that may process concurrent HR updates.

### Recommended pooling settings for payroll workloads

| Setting | Recommended value | Reason |
|---|---|---|
| **Minimum pool size** | 5 | Keep connections warm for predictable payroll load |
| **Maximum pool size** | 20 | Avoid overwhelming MySQL `max_connections` |
| **Connection timeout** | 30 seconds | Fail fast rather than queue indefinitely |
| **Idle timeout** | 300 seconds | Match MySQL `wait_timeout` |
| **Max lifetime** | 1800 seconds | Recycle connections to avoid stale state |

### Verify active connections at runtime

```sql
-- See all current connections and their state
SHOW PROCESSLIST;

-- Count connections by user
SELECT user, COUNT(*) AS connections
FROM information_schema.processlist
GROUP BY user
ORDER BY connections DESC;

-- Identify long-running queries (> 10 seconds)
SELECT id, user, host, db, command, time, state, info
FROM information_schema.processlist
WHERE time > 10
  AND command != 'Sleep'
ORDER BY time DESC;
```

### Kill a stuck long-running query

```sql
-- Get the process ID from SHOW PROCESSLIST
KILL QUERY <process_id>;   -- Kills the query but keeps the connection
KILL <process_id>;          -- Kills the connection entirely
```

---

## Performance Monitoring Queries

Run these regularly to monitor database health:

```sql
-- 1. Table row counts and sizes
SELECT
    table_name,
    table_rows          AS estimated_rows,
    ROUND(data_length / 1024 / 1024, 2)  AS data_mb,
    ROUND(index_length / 1024 / 1024, 2) AS index_mb
FROM information_schema.tables
WHERE table_schema = 'payroll_db'
ORDER BY data_length DESC;

-- 2. InnoDB buffer pool hit rate
SELECT
    ROUND((1 - (
        (SELECT variable_value FROM performance_schema.global_status
         WHERE variable_name = 'Innodb_buffer_pool_reads') /
        (SELECT variable_value FROM performance_schema.global_status
         WHERE variable_name = 'Innodb_buffer_pool_read_requests')
    )) * 100, 4) AS buffer_pool_hit_rate_pct;
-- Target: > 99.00%

-- 3. Most expensive queries by total execution time (performance_schema)
SELECT
    ROUND(sum_timer_wait / 1000000000000, 3) AS total_time_sec,
    count_star                                AS executions,
    ROUND(avg_timer_wait / 1000000000000, 3) AS avg_time_sec,
    LEFT(digest_text, 100)                   AS query_sample
FROM performance_schema.events_statements_summary_by_digest
WHERE schema_name = 'payroll_db'
ORDER BY sum_timer_wait DESC
LIMIT 10;

-- 4. Index usage statistics
SELECT
    object_name  AS table_name,
    index_name,
    count_star   AS times_used
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = 'payroll_db'
  AND index_name IS NOT NULL
ORDER BY count_star DESC;

-- 5. Lock wait summary
SELECT * FROM performance_schema.events_waits_summary_global_by_event_name
WHERE event_name LIKE '%lock%'
  AND count_star > 0
ORDER BY sum_timer_wait DESC
LIMIT 10;
```

---

## Performance Tuning Checklist

Use this checklist when deploying or diagnosing `payroll_db`:

- [ ] Buffer pool hit rate verified > 99% under normal load
- [ ] `EXPLAIN` run on all 5 stored procedure queries — no `type: ALL` on large tables
- [ ] Slow query log enabled with `long_query_time = 1`
- [ ] No queries appearing in slow log during normal payroll run
- [ ] `sp_run_payroll` execution time profiled and documented
- [ ] FULLTEXT queries confirmed using `MATCH...AGAINST`, not `LIKE '%...%'`
- [ ] Unused indexes identified via `performance_schema` and removed
- [ ] Duplicate indexes checked and resolved
- [ ] `audit_log` archiving scheduled before table exceeds 1 million rows
- [ ] `OPTIMIZE TABLE` scheduled for audit_log after each archiving run
- [ ] `innodb_flush_log_at_trx_commit = 1` confirmed (never 0 or 2 for payroll data)
- [ ] `sync_binlog = 1` confirmed for financial data durability
- [ ] Connection pool sizing documented and configured for `app_service` account
- [ ] Long-running query detection in place (processlist monitoring or alerting)
- [ ] Performance baseline documented before and after any schema or config change
