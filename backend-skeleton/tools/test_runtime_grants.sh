#!/usr/bin/env bash
set -euo pipefail
[[ "${APP_ENV:-}" == testing && "${RUN_OPERATIONS_RELEASE_CHECKS:-}" == 1 && "${DB_DATABASE:-}" == operations_testing ]]
[[ -n "${MYSQL_TEST_CONTAINER:-}" ]]
work=$(mktemp -d)
trap 'docker exec "$MYSQL_TEST_CONTAINER" rm -f /tmp/pos-grants-ci-client.cnf >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
chmod 700 "$work"
printf '[client]\nhost=127.0.0.1\nport=3306\nuser=root\npassword=%s\n' "$DB_PASSWORD" > "$work/operator.cnf"
printf '[client]\nhost=localhost\nuser=pos_grants_ci\npassword=ci-only-runtime\n' > "$work/runtime.cnf"
chmod 600 "$work/"*.cnf
mysql --defaults-extra-file="$work/operator.cnf" -e "CREATE DATABASE grants_ci; CREATE USER 'pos_grants_ci'@'localhost' IDENTIFIED BY 'ci-only-runtime';"
mysql --defaults-extra-file="$work/operator.cnf" grants_ci -e 'CREATE TABLE audit_logs (id INT PRIMARY KEY, action VARCHAR(64)); CREATE TABLE migrations (id INT PRIMARY KEY); CREATE TABLE orders (id INT PRIMARY KEY, total DECIMAL(12,2));'
python3 tools/runtime_grants.py --credentials "$work/operator.cnf" --database grants_ci --user pos_grants_ci --host localhost > "$work/grants.sql"
mysql --defaults-extra-file="$work/operator.cnf" < "$work/grants.sql" > /dev/null
# Port forwarding changes the host to the Docker bridge. Use a local client
# inside the disposable server to exercise the actual localhost grant identity.
docker cp "$work/runtime.cnf" "$MYSQL_TEST_CONTAINER:/tmp/pos-grants-ci-client.cnf"
runtime_mysql() { docker exec "$MYSQL_TEST_CONTAINER" mysql --defaults-extra-file=/tmp/pos-grants-ci-client.cnf "$@"; }
runtime_mysql grants_ci -e "INSERT INTO audit_logs VALUES (1,'fixture'); INSERT INTO orders VALUES (1,10); UPDATE orders SET total=12 WHERE id=1; DELETE FROM orders WHERE id=1; SELECT * FROM migrations; SELECT * FROM audit_logs;" > /dev/null
for sql in "UPDATE audit_logs SET action='tampered'" 'DELETE FROM audit_logs' 'DELETE FROM migrations' 'CREATE TABLE forbidden (id INT)' 'DROP TABLE audit_logs' "SELECT User FROM mysql.user"; do
  if runtime_mysql grants_ci -e "$sql" 2>/dev/null; then
    echo 'ERROR: Runtime account exceeded its intended permissions.'; exit 1
  fi
done
[[ $(mysql --defaults-extra-file="$work/operator.cnf" --batch --skip-column-names grants_ci -e "SELECT action FROM audit_logs WHERE id=1") == fixture ]]
mysql --defaults-extra-file="$work/operator.cnf" -e "DROP USER 'pos_grants_ci'@'localhost'; DROP DATABASE grants_ci;"
echo 'PASS: Real MySQL runtime CRUD allowed; audit changes, migration writes, DDL and system reads denied.'
