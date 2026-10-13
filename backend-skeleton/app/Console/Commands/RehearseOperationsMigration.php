<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Throwable;

class RehearseOperationsMigration extends Command
{
    protected $signature = 'pos:rehearse-migration {--database= : Existing restored top_coffee_pos_pr7_rehearsal_YYYYMMDD database}';
    protected $description = 'Migrate a restored local rehearsal database and verify all original record values';

    public function handle(): int
    {
        $target = (string) $this->option('database');
        if (! app()->environment(['local', 'testing'])) {
            $this->error('Run this rehearsal only in a local or testing environment.');
            return self::FAILURE;
        }
        if (! preg_match('/\Atop_coffee_pos_pr7_rehearsal_[0-9]{8}(?:_[0-9]{6})?\z/', $target)) {
            $this->error('Target must be an existing top_coffee_pos_pr7_rehearsal_YYYYMMDD database.');
            return self::FAILURE;
        }
        $original = DB::getDefaultConnection();
        $source = DB::connection($original)->getConfig();
        if (! in_array($source['driver'], ['mysql', 'mariadb'], true) || $target === $source['database']) {
            $this->error('A separate MySQL/MariaDB rehearsal database is required.');
            return self::FAILURE;
        }
        $alias = 'pos_migration_rehearsal';
        // A connection URL or read/write override must never point this alias
        // back to the original database, including when config is cached.
        unset($source['read'], $source['write']);
        $source['url'] = null;
        $source['database'] = $target;
        config(['database.connections.'.$alias => $source]);
        DB::purge($alias);
        try {
            $connection = DB::connection($alias);
            if ($connection->selectOne('SELECT DATABASE() AS name')->name !== $target) {
                throw new \RuntimeException('Connected database does not match the rehearsal target.');
            }
            $schema = Schema::connection($alias);
            foreach (['migrations', 'orders', 'payments'] as $required) {
                if (! $schema->hasTable($required)) throw new \RuntimeException('Restore a complete backup into the rehearsal database first.');
            }
            $before = [];
            foreach ($connection->select("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'") as $entry) {
                $table = array_values((array) $entry)[0];
                if ($table === 'migrations') continue;
                $columns = $schema->getColumnListing($table);
                $before[$table] = ['columns' => $columns, 'snapshot' => $this->snapshot($connection, $table, $columns)];
            }
            $this->info('Verified target: '.$target);
            $this->line('Original records captured from '.count($before).' tables.');
            DB::setDefaultConnection($alias);
            Schema::clearResolvedInstance('db.schema');
            $result = $this->call('migrate', ['--database' => $alias, '--force' => true]);
            if ($result !== self::SUCCESS) return self::FAILURE;
            foreach ($before as $table => $record) {
                if (! $schema->hasTable($table) || $record['snapshot'] !== $this->snapshot($connection, $table, $record['columns'])) {
                    throw new \RuntimeException('Original records changed in '.$table.'. Inspect the rehearsal copy before any rollout.');
                }
            }
            $this->info('PASS: all original record values are unchanged.');
            $this->line('Orders: '.$connection->table('orders')->count().'; payments: '.$connection->table('payments')->count().'.');
            $this->line('The configured original database was not migrated.');
            return self::SUCCESS;
        } catch (Throwable $error) {
            $this->error('Rehearsal failed: '.$error->getMessage());
            return self::FAILURE;
        } finally {
            DB::setDefaultConnection($original);
            Schema::clearResolvedInstance('db.schema');
            DB::purge($alias);
        }
    }

    private function snapshot($connection, string $table, array $columns): array
    {
        $hashes = [];
        foreach ($connection->table($table)->select($columns)->cursor() as $row) {
            // Row multiset hashing also supports tables without a primary key
            // and binary values without printing private records.
            $hashes[] = hash('sha256', serialize((array) $row));
        }
        sort($hashes, SORT_STRING);
        return ['rows' => count($hashes), 'digest' => hash('sha256', implode('', $hashes))];
    }
}
