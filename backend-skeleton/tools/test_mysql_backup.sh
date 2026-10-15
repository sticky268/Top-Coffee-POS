#!/usr/bin/env bash
set -euo pipefail
# Disposable CI only; never a production backup command.
[[ "${APP_ENV:-}" == testing && "${RUN_OPERATIONS_RELEASE_CHECKS:-}" == 1 && "${DB_DATABASE:-}" == operations_testing ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
printf '[client]\nhost=127.0.0.1\nport=3306\nuser=root\npassword=%s\ndefault-character-set=utf8mb4\n' "$DB_PASSWORD" > "$work/client.cnf"
chmod 600 "$work/client.cnf"
mysql --defaults-extra-file="$work/client.cnf" -e 'CREATE DATABASE backup_ci; CREATE DATABASE backup_ci_restore; CREATE DATABASE backup_ci_encrypted_restore;'
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
age-keygen -o "$work/recovery.agekey" 2>/dev/null
age-keygen -y "$work/recovery.agekey" > "$work/recipients.txt"
python3 tools/encrypted_backup.py backup --credentials "$work/client.cnf" --database backup_ci --assets "$work/assets" --commit "${GITHUB_SHA:-ci}" --writes-drained --recipients "$work/recipients.txt" --output "$work/encrypted/snapshot.age"
[[ $(find "$work/encrypted" -type f | wc -l) == 1 ]]
python3 tools/encrypted_backup.py restore-rehearsal --credentials "$work/client.cnf" --database backup_ci_encrypted_restore --assets "$work/encrypted-restored-assets" --backup "$work/encrypted/snapshot.age" --identity "$work/recovery.agekey" --work-root "$work/recovery"
cmp "$work/assets/logo.png" "$work/encrypted-restored-assets/logo.png"
[[ $(mysql --defaults-extra-file="$work/client.cnf" --batch --skip-column-names backup_ci -e 'SELECT COUNT(*) FROM receipt') == 2 ]]
python3 tools/restore_test.py --credentials "$work/client.cnf" --backup "$work/encrypted/snapshot.age" --identity "$work/recovery.agekey" --work-root "$work/recovery" --drop-on-success
mysql --defaults-extra-file="$work/client.cnf" -e 'DROP DATABASE backup_ci; DROP DATABASE backup_ci_restore; DROP DATABASE backup_ci_encrypted_restore;'
echo 'PASS: MySQL data, Khmer, decimals and assets restored; source and populated-target overwrites refused.'
echo 'PASS: age-encrypted database/assets recovery verified; completed backup directory contains ciphertext only.'
