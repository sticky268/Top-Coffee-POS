<?php

namespace App\Services;

use Illuminate\Database\Connection;

class ProductionReadiness
{
    public function hasUsableHttpsUrl(string $url): bool
    {
        if (filter_var($url, FILTER_VALIDATE_URL) === false) return false;
        $parts = parse_url($url);
        if ($parts === false || strtolower($parts['scheme'] ?? '') !== 'https'
            || empty($parts['host']) || isset($parts['user']) || isset($parts['pass'])
            || isset($parts['query']) || isset($parts['fragment'])) return false;

        $host = rtrim(strtolower(trim($parts['host'], '[]')), '.');
        if ($host === '' || $host === 'localhost' || str_ends_with($host, '.localhost')
            || $host === '10.0.2.2' || preg_match('/^127(?:\.\d+){0,3}$/', $host)) return false;

        $address = @inet_pton($host);
        if ($address !== false) {
            if (strlen($address) === 4) {
                if (ord($address[0]) === 127 || $address === str_repeat("\0", 4)) return false;
            } else {
                if ($address === str_repeat("\0", 16) || $address === str_repeat("\0", 15)."\1") return false;
                // IPv4-mapped IPv6 must not bypass the loopback/unspecified checks.
                if (substr($address, 0, 12) === str_repeat("\0", 10)."\xff\xff"
                    && (ord($address[12]) === 127 || substr($address, 12) === str_repeat("\0", 4))) return false;
            }
        }
        return true;
    }

    public function hasTransactionalTables(Connection $connection): bool
    {
        $driver = $connection->getDriverName();
        if ($driver === 'pgsql') return true;
        if (! in_array($driver, ['mysql', 'mariadb'], true)) return false;

        // A MySQL connection alone does not make MyISAM tables transactional.
        // Inspect only; never convert tables or repair a live schema here.
        $tables = $connection->select(
            "SELECT TABLE_NAME AS name, ENGINE AS engine FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'BASE TABLE'",
            [$connection->getDatabaseName()],
        );
        if ($tables === []) return false;
        foreach ($tables as $table) {
            if (strtoupper((string) $table->engine) !== 'INNODB') return false;
        }
        return true;
    }
}
