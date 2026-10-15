#!/usr/bin/env bash
set -euo pipefail
[[ "${APP_ENV:-}" == testing && "${RUN_OPERATIONS_RELEASE_CHECKS:-}" == 1 && "${DB_DATABASE:-}" == operations_testing ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
printf '[client]\nhost=127.0.0.1\nport=3306\nuser=root\npassword=%s\n' "$DB_PASSWORD" > "$work/operator.cnf"
printf '[client]\nhost=127.0.0.1\nport=3306\nuser=pos_grants_ci\npassword=ci-only-runtime\n' > "$work/runtime.cnf"
chmod 600 "$work/"*.cnf
mysql --defaults-extra-file="$work/operator.cnf" -e "CREATE DATABASE grants_ci; CREATE USER 'pos_grants_ci'@'127.0.0.1' IDENTIFIED BY 'ci-only-runtime';"
mysql --defaults-extra-file="$work/operator.cnf" grants_ci -e 'CREATE TABLE audit_logs (id INT PRIMARY KEY, action VARCHAR(64)); CREATE TABLE migrations (id INT PRIMARY KEY); CREATE TABLE orders (id INT PRIMARY KEY, total DECIMAL(12,2));'
python3 tools/runtime_grants.py --credentials "$work/operator.cnf" --database grants_ci --user pos_grants_ci --host 127.0.0.1 > "$work/grants.sql"
mysql --defaults-extra-file="$work/operator.cnf" < "$work/grants.sql" > /dev/null
mysql --defaults-extra-file="$work/runtime.cnf" grants_ci -e "INSERT INTO audit_logs VALUES (1,'fixture'); INSERT INTO orders VALUES (1,10); UPDATE orders SET total=12 WHERE id=1; DELETE FROM orders WHERE id=1; SELECT * FROM migrations; SELECT * FROM audit_logs;" > /dev/null
for sql in "UPDATE audit_logs SET action='tampered'" 'DELETE FROM audit_logs' 'DELETE FROM migrations' 'CREATE TABLE forbidden (id INT)' 'DROP TABLE audit_logs' "SELECT User FROM mysql.user"; do
  if mysql --defaults-extra-file="$work/runtime.cnf" grants_ci -e "$sql" 2>/dev/null; then
    echo 'ERROR: Runtime account exceeded its intended permissions.'; exit 1
  fi
done
[[ $(mysql --defaults-extra-file="$work/operator.cnf" --batch --skip-column-names grants_ci -e "SELECT action FROM audit_logs WHERE id=1") == fixture ]]
mysql --defaults-extra-file="$work/operator.cnf" -e "DROP USER 'pos_grants_ci'@'127.0.0.1'; DROP DATABASE grants_ci;"
echo 'PASS: Real MySQL runtime CRUD allowed; audit changes, migration writes, DDL and system reads denied.'
