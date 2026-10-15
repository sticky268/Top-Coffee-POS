<?php

namespace Tests\Unit;

use App\Services\ProductionReadiness;
use PHPUnit\Framework\TestCase;

class ProductionReadinessTest extends TestCase
{
    public function test_https_requires_a_usable_host_without_embedded_secrets_or_local_endpoints(): void
    {
        $readiness = new ProductionReadiness();
        foreach ([
            '', 'https:/coffee.example.com', 'https://', 'http://coffee.example.com',
            'https://user:password@coffee.example.com', 'https://coffee.example.com?key=test',
            'https://coffee.example.com#fragment', 'https://localhost', 'https://LOCALHOST.',
            'https://api.localhost', 'https://127.0.0.1', 'https://127.0.0.2', 'https://127.1',
            'https://0.0.0.0', 'https://10.0.2.2', 'https://[::1]', 'https://[0:0:0:0:0:0:0:1]',
            'https://[::]', 'https://[::ffff:127.0.0.1]', 'https://[::ffff:0.0.0.0]',
        ] as $url) {
            $this->assertFalse($readiness->hasUsableHttpsUrl($url), 'Unsafe application URL was accepted.');
        }
        foreach (['https://coffee.example.com', 'HTTPS://coffee.example.com',
            'https://coffee.example.com:8443/pos', 'https://api.coffee.example.com/',
        ] as $url) {
            $this->assertTrue($readiness->hasUsableHttpsUrl($url), 'Valid HTTPS application URL was rejected.');
        }
    }
}
