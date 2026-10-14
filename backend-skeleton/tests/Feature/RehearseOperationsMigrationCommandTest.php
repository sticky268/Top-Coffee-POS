<?php

namespace Tests\Feature;

use Tests\TestCase;

class RehearseOperationsMigrationCommandTest extends TestCase
{
    public function test_rejects_the_cafe_database_name(): void
    {
        $this->artisan('pos:rehearse-migration', ['--database' => 'top_coffee_pos'])
            ->expectsOutputToContain('Target must be an existing')->assertExitCode(1);
    }

    public function test_rejects_production_environment_before_connecting(): void
    {
        $this->app->instance('env', 'production');
        $this->artisan('pos:rehearse-migration', ['--database' => 'top_coffee_pos_pr7_rehearsal_20261013'])
            ->expectsOutputToContain('only in a local or testing environment')->assertExitCode(1);
    }

    public function test_rejects_unsupported_driver(): void
    {
        config(['database.default' => 'sqlite']);
        $this->artisan('pos:rehearse-migration', ['--database' => 'top_coffee_pos_pr7_rehearsal_20261013'])
            ->expectsOutputToContain('A separate MySQL/MariaDB rehearsal database')->assertExitCode(1);
    }
}
