#!/usr/bin/env python3
"""Disposable GitHub Actions Android/API rehearsal. No live target arguments."""
from __future__ import annotations

import json
import os
import signal
from pathlib import Path
import sqlite3
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
FRONTEND = ROOT / 'frontend'
BACKEND = ROOT / 'backend-skeleton'
DATABASE = BACKEND / 'database/ci.sqlite'
API = 'http://127.0.0.1:8000/up'
APP_ID = 'com.example.top_coffee_pos'
EVIDENCE = FRONTEND / 'build/security/offline-rehearsal.json'
DIAGNOSTICS = FRONTEND / 'build/integration-diagnostics'


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def guard() -> None:
    require(os.environ.get('GITHUB_ACTIONS') == 'true', 'CI only: no manual/live execution.')
    require(os.environ.get('APP_ENV') == 'testing', 'APP_ENV must be testing.')
    require(os.environ.get('DB_CONNECTION') == 'sqlite', 'Only disposable SQLite is allowed.')
    require(Path(os.environ.get('DB_DATABASE', '')).resolve() == DATABASE,
            'Only this checkout database/ci.sqlite is allowed.')
    require(DATABASE.is_file(), 'Seed the fresh integration fixture first.')
    # Verify identity before starting any process or changing any fixture.
    with sqlite3.connect(f'file:{DATABASE}?mode=ro', uri=True) as db:
        require(db.execute("SELECT COUNT(*) FROM businesses WHERE name='CI Offline Cafe'").fetchone()[0] == 1,
                'The dedicated disposable fixture is missing.')
        for email in ('offline-a@ci.invalid', 'offline-b@ci.invalid'):
            require(db.execute('SELECT COUNT(*) FROM users WHERE email=?', (email,)).fetchone()[0] == 1,
                    'The dedicated synthetic operators are missing.')
    # Never stop or reuse an existing listener; the runner owns its child only.
    import socket
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 8000))


def run_test(name: str, phase: str | None = None) -> None:
    command = ['flutter', 'test', f'integration_test/{name}.dart',
               '--dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1']
    if phase:
        # flutter test otherwise uninstalls the integration app on teardown.
        # Preserve Android data/Keystore across the four real process launches.
        command += ['--no-uninstall', f'--dart-define=OFFLINE_PHASE={phase}']
    if name == 'operations_readonly_smoke_test':
        command += ['--dart-define=SMOKE_EXPECTED_API=http://10.0.2.2:8000/api/v1',
                    '--dart-define=SMOKE_CI_LOGIN=true']
    # Capture tool startup as well as test output; an install can succeed while
    # VM-service discovery hangs before any Dart assertion is reached.
    command += ['--verbose']
    DIAGNOSTICS.mkdir(parents=True, exist_ok=True)
    label = name + (f'-{phase}' if phase else '')
    output_path = DIAGNOSTICS / f'{label}.log'
    print(f'START: {label}; verbose output: {output_path}', flush=True)
    with output_path.open('w') as output:
        process = subprocess.Popen(command, cwd=FRONTEND, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=900)
            if code:
                raise subprocess.CalledProcessError(code, command)
        except subprocess.TimeoutExpired:
            # End this test's process group, including Flutter tool children.
            # Never kill another job's processes or clear retained device data.
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
            raise
        finally:
            output.flush()
            print('\n'.join(output_path.read_text(errors='replace').splitlines()[-80:]),
                  flush=True)
            if process.returncode != 0:
                # This must run before emulator-runner tears down the emulator.
                # Fixture-only logcat; no real account or target is permitted.
                with (DIAGNOSTICS / f'{label}-logcat.txt').open('w') as device_log:
                    try:
                        subprocess.run(['adb', 'logcat', '-d', '-t', '1500'],
                                       stdout=device_log, stderr=subprocess.STDOUT,
                                       timeout=20, check=False)
                    except (OSError, subprocess.TimeoutExpired) as error:
                        device_log.write(f'Diagnostic capture failed: {type(error).__name__}\\n')


def stop_android() -> None:
    # CI emulator only; preserves app data and Android Keystore. Each next
    # flutter test --no-uninstall launches a new process without clearing data.
    subprocess.run(['adb', 'shell', 'am', 'force-stop', APP_ID], check=True, timeout=15)
    result = subprocess.run(['adb', 'shell', 'pidof', APP_ID],
                            capture_output=True, text=True, timeout=15)
    require(result.returncode == 1 and not result.stdout.strip(),
            'Android application is still running after force-stop.')
    print('PASS: Android process stopped; device data preserved.', flush=True)


def assert_ledger(expected: int) -> dict:
    # Read the server DB independently of Flutter/API result parsing.
    with sqlite3.connect(f'file:{DATABASE}?mode=ro', uri=True) as db:
        db.row_factory = sqlite3.Row
        tenant = db.execute("SELECT id FROM businesses WHERE name='CI Offline Cafe'").fetchone()['id']
        operator = db.execute("SELECT id FROM users WHERE email='offline-a@ci.invalid'").fetchone()['id']
        branches = db.execute('SELECT id,code FROM branches WHERE business_id=? ORDER BY code', (tenant,)).fetchall()
        require(len(branches) == 2, 'Expected exactly two offline fixture branches.')
        orders = db.execute('SELECT o.* FROM orders o JOIN branches b ON b.id=o.branch_id WHERE b.business_id=?', (tenant,)).fetchall()
        require(len(orders) == expected, 'Offline order count changed unexpectedly.')
        payments = db.execute('SELECT p.* FROM payments p JOIN orders o ON o.id=p.order_id JOIN branches b ON b.id=o.branch_id WHERE b.business_id=?', (tenant,)).fetchall()
        require(len(payments) == expected, 'Duplicate or missing offline payment.')
        movements = db.execute("SELECT s.* FROM stock_movements s JOIN branches b ON b.id=s.branch_id WHERE b.business_id=? AND s.type='sale_deduction'", (tenant,)).fetchall()
        require(len(movements) == expected, 'Duplicate or missing inventory deduction.')
        if expected:
            order, payment, movement = orders[0], payments[0], movements[0]
            require(order['status'] == 'completed' and float(order['total']) == 3.5
                    and order['user_id'] == operator and order['branch_id'] == branches[0]['id'],
                    'Wrong financial amount/operator/branch.')
            item = db.execute('SELECT product_name,quantity FROM order_items WHERE order_id=?', (order['id'],)).fetchall()
            require(len(item) == 1 and item[0]['product_name'] == 'CI Offline Stable Latte'
                    and item[0]['quantity'] == 1, 'The conflicted sale must not become a server order.')
            shift = db.execute('SELECT * FROM cashier_shifts WHERE id=?', (payment['shift_id'],)).fetchone()
            require(shift is not None and shift['user_id'] == operator and shift['branch_id'] == branches[0]['id']
                    and shift['status'] == 'open' and float(shift['opening_cash']) == 20,
                    'Payment did not retain the original verified shift.')
            require(payment['method'] == 'cash' and float(payment['amount']) == 3.5
                    and float(payment['tendered']) == 5 and float(payment['change_due']) == 1.5,
                    'Payment amount/change does not match the cash sale.')
            require(movement['reference_id'] == order['id'] and float(movement['quantity']) == -0.25
                    and movement['created_by'] == operator and movement['branch_id'] == branches[0]['id'],
                    'Inventory deduction has the wrong source/quantity/actor/branch.')
        balances = []
        for index, branch in enumerate(branches):
            ingredient = db.execute('SELECT id,current_stock FROM ingredients WHERE branch_id=?', (branch['id'],)).fetchone()
            balance = db.execute('SELECT SUM(quantity) FROM stock_movements WHERE ingredient_id=?', (ingredient['id'],)).fetchone()[0]
            target = 20 - (0.25 if expected and index == 0 else 0)
            require(float(ingredient['current_stock']) == target == float(balance),
                    'Cached stock and movement ledger disagree, or another branch changed.')
            balances.append(target)
        return {'orders': len(orders), 'payments': len(payments),
                'sale_deductions': len(movements), 'branch_balances': balances}


def change_fixture_price() -> None:
    # Called only while the owned API is stopped, after both offline snapshots.
    # Realistic server conflict, never a backdoor endpoint or financial edit.
    with sqlite3.connect(DATABASE) as db:
        changed = db.execute("UPDATE products SET base_price=4.50 WHERE name='CI Offline Changed Latte' AND base_price=3.50 AND business_id=(SELECT id FROM businesses WHERE name='CI Offline Cafe')")
        require(changed.rowcount == 1, 'Refusing to change an unexpected fixture/product.')


def main() -> None:
    guard()
    EVIDENCE.unlink(missing_ok=True)
    server: subprocess.Popen | None = None
    evidence = {'disposable_only': True, 'phases': []}
    with Path('/tmp/operations-api.log').open('w') as log:
        def start_api() -> None:
            nonlocal server
            server = subprocess.Popen(['php', '-S', '127.0.0.1:8000', '-t', 'public', 'public/index.php'],
                                      cwd=BACKEND, stdout=log, stderr=subprocess.STDOUT)
            for _ in range(50):
                require(server.poll() is None, 'The owned disposable API exited.')
                try:
                    with urllib.request.urlopen(API, timeout=1) as response:
                        if response.status == 200:
                            return
                except (urllib.error.URLError, TimeoutError):
                    time.sleep(0.2)
            raise RuntimeError('The disposable API did not become healthy.')

        def stop_api() -> None:
            nonlocal server
            if server is not None:
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=5)
                server = None
            try:
                urllib.request.urlopen(API, timeout=1).close()
            except urllib.error.URLError:
                return
            raise RuntimeError('The API is unexpectedly reachable during the outage.')

        try:
            start_api()
            for name in ('daily_operations_test', 'operations_readonly_smoke_test', 'manager_approval_test'):
                run_test(name)
            require(assert_ledger(0)['orders'] == 0, 'Offline fixture was already used.')
            run_test('offline_sale_recovery_test', 'prepare')
            stop_android()
            stop_api()
            for phase in ('queue', 'restart'):
                run_test('offline_sale_recovery_test', phase)
                stop_android()
                evidence['phases'].append({'phase': phase, 'ledger': assert_ledger(0)})
            change_fixture_price()
            start_api()
            run_test('offline_sale_recovery_test', 'recover')
            stop_android()
            evidence['phases'].append({'phase': 'recover', 'ledger': assert_ledger(1)})
            run_test('printer_queue_recovery_test')
        finally:
            if server is not None:
                stop_api()
    evidence['result'] = 'pass'
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(json.dumps(evidence, indent=2) + '\n')
    print('PASS: outage/restart/replay/scope/conflict rehearsal and independent ledger checks.', flush=True)


if __name__ == '__main__':
    main()
