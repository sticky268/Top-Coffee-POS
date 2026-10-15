<?php

namespace Tests\Feature;

use Tests\TestCase;

class CorsPolicyTest extends TestCase
{
    public function test_untrusted_origin_gets_no_browser_read_permission(): void
    {
        config(['cors.allowed_origins' => ['https://pos.example.invalid']]);
        $this->withHeader('Origin', 'https://attacker.example.invalid')->getJson('/api/v1/auth/me')
            ->assertUnauthorized()->assertHeaderMissing('Access-Control-Allow-Origin');
    }

    public function test_explicit_browser_origin_still_requires_a_valid_bearer_token(): void
    {
        config(['cors.allowed_origins' => ['https://pos.example.invalid']]);
        $this->withHeader('Origin', 'https://pos.example.invalid')->getJson('/api/v1/auth/me')
            ->assertUnauthorized()->assertHeader('Access-Control-Allow-Origin', 'https://pos.example.invalid')
            ->assertHeaderMissing('Access-Control-Allow-Credentials');
    }

    public function test_native_request_without_origin_is_not_blocked_by_empty_allowlist(): void
    {
        config(['cors.allowed_origins' => []]);
        $this->getJson('/api/v1/auth/me')->assertUnauthorized();
    }
}
