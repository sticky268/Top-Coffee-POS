#!/usr/bin/env bash
set -euo pipefail
# Disposable CI only; never a production backup command.
[[ "${APP_ENV:-}" == testing && "${RUN_OPERATIONS_RELEASE_CHECKS:-}" == 1 && "${DB_DATABASE:-}" == operations_testing ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
printf '[client]\nhost=127.0.0.1\nport=3306\nuser=root\npassword=%s\ndefault-character-set=utf8mb4\n' "$DB_PASSWORD" > "$work/client.cnf"
chmod 600 "$work/client.cnf"
mysql --defaults-extra-file="$work/client.cnf" -e 'CREATE DATABASE backup_ci; CREATE DATABASE backup_ci_restore;'
mysql --defaults-extra-file="$work/client.cnf" backup_ci -e "CREATE TABLE receipt (id INT PRIMARY KEY, name VARCHAR(100), amount DECIMAL(14,3)); INSERT INTO receipt VALUES (1,'សួស្តី កាហ្វេ',49.978),(2,'Coffee',5.000);"
mkdir "$work/assets"
printf 'logo test data' > "$work/assets/logo.png"
python3 tools/mysql_backup.py --credentials "$work/client.cnf" backup --database backup_ci --assets "$work/assets" --output "$work/backups" --commit "${GITHUB_SHA:-ci}" --writes-drained > "$work/path"
bundle=$(cat "$work/path")
python3 tools/mysql_backup.py --credentials "$work/client.cnf" restore-rehearsal --database backup_ci_restore --assets "$work/restored-assets" --backup "$bundle"
cmp "$work/assets/logo.png" "$work/restored-assets/logo.png"
if python3 tools/mysql_backup.py --credentials "$work/client.cnf" restore-rehearsal --database backup_ci --assets "$work/refused" --backup "$bundle"; then
  echo 'ERROR: Source overwrite was allowed'; exit 1
fi
if python3 tools/mysql_backup.py --credentials "$work/client.cnf" restore-rehearsal --database backup_ci_restore --assets "$work/refused" --backup "$bundle"; then
  echo 'ERROR: Populated restore overwrite was allowed'; exit 1
fi
[[ $(mysql --defaults-extra-file="$work/client.cnf" --batch --skip-column-names backup_ci -e 'SELECT COUNT(*) FROM receipt') == 2 ]]
mysql --defaults-extra-file="$work/client.cnf" -e 'DROP DATABASE backup_ci; DROP DATABASE backup_ci_restore;'
echo 'PASS: MySQL data, Khmer, decimals and assets restored; source and populated-target overwrites refused.'
