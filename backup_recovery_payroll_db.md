# Backup & Recovery Guide — payroll_db

A payroll database holds legally sensitive financial data. In Nigeria, FIRS and PenCom regulations require financial records to be retained for a minimum of 6 years. This guide documents the backup strategy, verification procedures, restore procedures, and Aiven-specific backup handling for `payroll_db`.

---

## Table of Contents

- [Backup Strategy Overview](#backup-strategy-overview)
- [Backup User Setup](#backup-user-setup)
- [Logical Backups with mysqldump](#logical-backups-with-mysqldump)
  - [Full Database Backup](#full-database-backup)
  - [Schema-Only Backup](#schema-only-backup)
  - [Data-Only Backup](#data-only-backup)
  - [Single Table Backup](#single-table-backup)
- [Binary Log Backup (Point-in-Time Recovery)](#binary-log-backup-point-in-time-recovery)
- [Backup Verification](#backup-verification)
- [Restore Procedures](#restore-procedures)
  - [Full Restore](#full-restore)
  - [Point-in-Time Restore](#point-in-time-restore)
  - [Single Table Restore](#single-table-restore)
- [Aiven Backup & Recovery](#aiven-backup--recovery)
- [Backup Schedule Recommendation](#backup-schedule-recommendation)
- [Backup Checklist](#backup-checklist)

---

## Backup Strategy Overview

`payroll_db` uses a two-layer backup strategy:

| Layer | Method | Frequency | Purpose |
|---|---|---|---|
| **Logical backup** | `mysqldump` | Daily | Full snapshot — portable, human-readable SQL |
| **Binary log backup** | MySQL binlog | Continuous | Point-in-time recovery between daily snapshots |

Together these two layers mean:
- If the database is lost at any point, the daily dump restores the last known good state
- Binary logs fill the gap between the last dump and the moment of failure, recovering every transaction

---

## Backup User Setup

Never run backups as `root` or `payroll_admin`. Create a dedicated backup user with the minimum privileges needed:

```sql
-- Run as root or payroll_admin
CREATE USER IF NOT EXISTS 'backup_user'@'localhost'
    IDENTIFIED BY 'Change_Me_Backup!2024';

-- Minimum privileges for mysqldump
GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES, EVENT
    ON payroll_db.* TO 'backup_user'@'localhost';

-- Required for binary log access (point-in-time recovery)
GRANT REPLICATION CLIENT ON *.* TO 'backup_user'@'localhost';

FLUSH PRIVILEGES;
```

> ⚠️ Change the password before using in any environment. Never commit real credentials to version control.

---

## Logical Backups with mysqldump

### Full Database Backup

A complete backup of all tables, views, procedures, triggers, and events:

```bash
mysqldump \
  --user=backup_user \
  --password \
  --host=127.0.0.1 \
  --port=3306 \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --flush-logs \
  --master-data=2 \
  --databases payroll_db \
  > /backups/payroll_db_$(date +%Y%m%d_%H%M%S).sql
```

**Flag explanations:**

| Flag | Why it matters |
|---|---|
| `--single-transaction` | Takes a consistent snapshot without locking tables (InnoDB only) — critical for a live payroll system |
| `--routines` | Includes stored procedures (`sp_run_payroll`, `sp_calculate_tax`, etc.) |
| `--triggers` | Includes all 7 audit triggers |
| `--events` | Includes the `evt_monthly_payroll` event scheduler |
| `--flush-logs` | Starts a new binary log file at backup time — makes point-in-time recovery cleaner |
| `--master-data=2` | Records the binary log position at backup time as a comment — essential for point-in-time recovery |

### Schema-Only Backup

Backs up table structures, views, procedures, triggers, and events — no data:

```bash
mysqldump \
  --user=backup_user \
  --password \
  --no-data \
  --routines \
  --triggers \
  --events \
  --databases payroll_db \
  > /backups/payroll_db_schema_$(date +%Y%m%d).sql
```

Useful for: version-controlling schema changes, deploying to a new environment, or comparing schema drift between environments.

### Data-Only Backup

Backs up data only — no `CREATE TABLE` or procedure definitions:

```bash
mysqldump \
  --user=backup_user \
  --password \
  --no-create-info \
  --single-transaction \
  --databases payroll_db \
  > /backups/payroll_db_data_$(date +%Y%m%d).sql
```

Useful for: migrating data to an existing schema, seeding a test environment.

### Single Table Backup

Back up a specific table — useful for targeted recovery of reference data:

```bash
# Backup tax_bracket only
mysqldump \
  --user=backup_user \
  --password \
  --single-transaction \
  payroll_db tax_bracket \
  > /backups/tax_bracket_$(date +%Y%m%d).sql

# Backup audit_log only (for archiving before purging old entries)
mysqldump \
  --user=backup_user \
  --password \
  --single-transaction \
  payroll_db audit_log \
  > /backups/audit_log_archive_$(date +%Y%m%d).sql
```

---

## Binary Log Backup (Point-in-Time Recovery)

Binary logs record every data-changing transaction. Combined with a daily dump, they allow recovery to any specific point in time — critical for a payroll system where a bad script run or accidental delete can corrupt records.

### Enable Binary Logging

Add to `/etc/mysql/mysql.conf.d/mysqld.cnf` (local MySQL):

```ini
[mysqld]
log_bin           = /var/log/mysql/mysql-bin.log
binlog_format     = ROW
expire_logs_days  = 14
max_binlog_size   = 100M
server_id         = 1
```

Restart MySQL after editing:

```bash
sudo systemctl restart mysql
```

### Verify Binary Logging is Active

```sql
SHOW VARIABLES LIKE 'log_bin';
-- Value should be: ON

SHOW BINARY LOGS;
-- Lists all current binary log files and their sizes
```

### Back Up Binary Logs

```bash
# Copy all binary logs to backup location
mysqlbinlog \
  --read-from-remote-server \
  --host=127.0.0.1 \
  --user=backup_user \
  --password \
  --raw \
  --to-last-log \
  mysql-bin.000001 \
  --result-file=/backups/binlogs/
```

Run this continuously or on a schedule (every hour recommended for payroll data).

---

## Backup Verification

**A backup that has never been tested is not a backup — it is a hope.**

After every backup, verify it can actually be restored:

### Step 1: Check the backup file is not empty or corrupt

```bash
# Check file size (should be > 0)
ls -lh /backups/payroll_db_*.sql

# Check the file ends correctly
tail -5 /backups/payroll_db_20260628_020000.sql
# Should end with: -- Dump completed on YYYY-MM-DD HH:MM:SS
```

### Step 2: Restore to a test database and verify

```bash
# Create a test database
mysql --user=root --password -e "CREATE DATABASE payroll_db_test;"

# Restore backup into test database
mysql --user=root --password payroll_db_test \
  < /backups/payroll_db_20260628_020000.sql

# Verify table counts match production
mysql --user=root --password payroll_db_test -e "
  SELECT 'employee'     AS tbl, COUNT(*) FROM employee     UNION ALL
  SELECT 'payslip',            COUNT(*) FROM payslip       UNION ALL
  SELECT 'audit_log',          COUNT(*) FROM audit_log     UNION ALL
  SELECT 'payroll_run',        COUNT(*) FROM payroll_run;
"

# Drop test database after verification
mysql --user=root --password -e "DROP DATABASE payroll_db_test;"
```

### Step 3: Verify stored procedures and triggers restored correctly

```sql
USE payroll_db_test;

-- Check procedures exist
SHOW PROCEDURE STATUS WHERE Db = 'payroll_db_test';
-- Should list: sp_calculate_tax, sp_generate_payslip,
--              sp_run_payroll, sp_get_payslip, sp_update_salary

-- Check triggers exist
SHOW TRIGGERS FROM payroll_db_test;
-- Should list all 7 triggers
```

---

## Restore Procedures

### Full Restore

Use when the entire database needs to be recovered from a backup:

```bash
# Step 1: Drop and recreate the database (if it still exists)
mysql --user=root --password -e "
  DROP DATABASE IF EXISTS payroll_db;
  CREATE DATABASE payroll_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
"

# Step 2: Restore from the most recent full backup
mysql --user=root --password \
  < /backups/payroll_db_20260628_020000.sql

# Step 3: Verify restoration
mysql --user=root --password payroll_db -e "
  SELECT COUNT(*) AS employees FROM employee;
  SELECT COUNT(*) AS payslips  FROM payslip;
  SELECT COUNT(*) AS audit_rows FROM audit_log;
"
```

### Point-in-Time Restore

Use when you need to recover to a specific moment — for example, to undo a bad payroll run that completed at 14:35 on 2026-06-28:

```bash
# Step 1: Find the binary log position recorded in the backup
grep "MASTER_LOG_FILE\|MASTER_LOG_POS" /backups/payroll_db_20260628_020000.sql
# Output example:
# -- CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000042', MASTER_LOG_POS=4;

# Step 2: Restore the full backup first
mysql --user=root --password < /backups/payroll_db_20260628_020000.sql

# Step 3: Apply binary logs UP TO the moment before the bad event
# Replace --stop-datetime with the exact moment just before the error
mysqlbinlog \
  --start-position=4 \
  --stop-datetime="2026-06-28 14:34:59" \
  /var/log/mysql/mysql-bin.000042 \
  | mysql --user=root --password payroll_db

# Step 4: Verify the recovered state
mysql --user=root --password payroll_db -e "
  SELECT * FROM payroll_run ORDER BY run_id DESC LIMIT 3;
  SELECT COUNT(*) FROM payslip;
"
```

> **Note:** `--stop-datetime` uses the server's local time. Confirm the timezone of your MySQL server before specifying the recovery point.

### Single Table Restore

Use when only one table needs recovery — for example, if `tax_bracket` was accidentally truncated:

```bash
# Restore just the tax_bracket table from its dedicated backup
mysql --user=root --password payroll_db \
  < /backups/tax_bracket_20260628.sql

# Verify
mysql --user=root --password payroll_db -e "
  SELECT * FROM tax_bracket;
"
```

> ⚠️ Single table restores can violate referential integrity if the restored data references rows that no longer exist in other tables. Always verify FK consistency after a partial restore:
> ```sql
> -- Check for orphaned payslips after partial restore
> SELECT ps.payslip_id FROM payslip ps
> LEFT JOIN payroll_run pr ON ps.run_id = pr.run_id
> WHERE pr.run_id IS NULL;
> ```

---

## Aiven Backup & Recovery

Aiven managed MySQL handles backups differently from self-hosted MySQL. Understanding both is important for a DBA working in cloud environments.

### What Aiven does automatically

| Feature | Detail |
|---|---|
| **Full backups** | Taken daily automatically |
| **Point-in-time recovery (PITR)** | Continuous binary log shipping — recover to any second within the retention window |
| **Retention period** | 2 days on free tier; up to 30 days on paid plans |
| **Backup storage** | Encrypted and stored in cloud object storage (separate from your service) |
| **Restore trigger** | Via Aiven Console or Aiven CLI — not via `mysqldump` |

### How to restore on Aiven

**Option 1 — Point-in-time restore via Aiven Console:**

1. Go to your Aiven Console → Select your MySQL service
2. Click **Backups** in the left panel
3. Select **Restore to point in time**
4. Choose the target date and time
5. Aiven creates a **new service** from the restore point — your original service is untouched until you confirm
6. Verify the restored service, then update your connection string to point to it

**Option 2 — Aiven CLI:**

```bash
# Install Aiven CLI
pip install aiven-client

# Log in
avn user login

# List available backups
avn service backup-list your-mysql-service-name

# Restore to a specific point in time
avn service create your-mysql-service-restored \
  --service-type mysql \
  --cloud google-europe-west1 \
  --plan hobbyist \
  --source-service-name your-mysql-service-name \
  --source-backup-name PITR \
  --source-backup-before "2026-06-28T14:34:59Z"
```

### Supplement Aiven backups with manual mysqldump

Aiven's free tier only retains backups for 2 days. For a payroll system requiring 6-year retention, supplement with manual `mysqldump` exports stored in your own storage (local disk, Google Drive, S3):

```bash
# Export from Aiven and save locally
mysqldump \
  --user=avnadmin \
  --password \
  --host=<your-aiven-host> \
  --port=<your-aiven-port> \
  --ssl-ca=/path/to/ca.pem \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --databases payroll_db \
  > /backups/payroll_db_aiven_$(date +%Y%m%d_%H%M%S).sql
```

---

## Backup Schedule Recommendation

For a production payroll system:

| Backup Type | Frequency | Retention | Storage |
|---|---|---|---|
| Full `mysqldump` | Daily at 02:00 AM | 90 days local, 6 years archive | Local + offsite |
| Schema-only dump | On every schema change | Indefinite | Git repository |
| Binary log backup | Every 1 hour | 14 days | Local + offsite |
| Backup verification test | Weekly | — | Log results |
| Pre-payroll-run snapshot | Before every `sp_run_payroll` | 3 months | Local |

### Automate daily backup with cron (local MySQL)

```bash
# Edit crontab
crontab -e

# Add this line — runs full backup daily at 2:00 AM
0 2 * * * mysqldump --user=backup_user --password=Change_Me_Backup!2024 \
  --single-transaction --routines --triggers --events --flush-logs \
  --databases payroll_db \
  > /backups/payroll_db_$(date +\%Y\%m\%d_\%H\%M\%S).sql 2>> /backups/backup_errors.log
```

> ⚠️ Storing the password directly in crontab is not recommended for production. Use a MySQL options file (`~/.my.cnf`) instead:
> ```ini
> [mysqldump]
> user=backup_user
> password=Change_Me_Backup!2024
> ```
> Then the cron command becomes: `mysqldump --defaults-file=~/.my.cnf ...`

---

## Backup Checklist

Use this checklist before going live with any payroll environment:

- [ ] Binary logging enabled and verified (`SHOW VARIABLES LIKE 'log_bin'`)
- [ ] `backup_user` created with minimum required privileges only
- [ ] Daily full backup cron job configured and tested
- [ ] Hourly binary log backup configured and tested
- [ ] At least one full restore tested successfully on a separate test database
- [ ] Point-in-time recovery tested — confirmed recovery to a specific timestamp works
- [ ] Backup file integrity check automated (file size > 0, ends with dump completion line)
- [ ] Backup storage location is offsite or cloud (not the same server as the database)
- [ ] Backup retention policy documented and storage space allocated for 6-year retention
- [ ] Aiven PITR tested (if using Aiven) — confirmed restore creates new service correctly
- [ ] Pre-payroll-run snapshot procedure documented and understood by team
- [ ] All backup passwords stored in a secrets manager, not in version control
