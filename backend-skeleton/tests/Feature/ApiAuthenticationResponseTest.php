<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class ApiAuthenticationResponseTest extends TestCase
{
    use RefreshDatabase;

    public function test_api_browser_probe_without_accept_header_returns_json_401(): void
    {
        $this->get('/api/v1/auth/me')
            ->assertUnauthorized()
            ->assertHeader('Content-Type', 'application/json')
            ->assertJsonPath('message', 'Unauthenticated.')
            ->assertJsonMissingPath('exception');
    }

    public function test_api_authentication_does_not_depend_on_browser_accept_headers(): void
    {
        foreach (['text/html', '*/*', 'application/json'] as $accept) {
            $this->get('/api/v1/auth/me', ['Accept' => $accept])
                ->assertUnauthorized()
                ->assertHeader('Content-Type', 'application/json')
                ->assertJsonPath('message', 'Unauthenticated.')
                ->assertJsonMissingPath('exception');
        }
    }

    public function test_invalid_bearer_token_returns_json_without_redirecting_to_web_login(): void
    {
        $this->get('/api/v1/auth/me', [
            'Authorization' => 'Bearer invalid-token',
            'Accept' => 'text/html',
        ])->assertUnauthorized()
            ->assertJsonPath('message', 'Unauthenticated.')
            ->assertJsonMissingPath('exception');
    }

    public function test_other_protected_api_routes_keep_the_same_json_authentication_contract(): void
    {
        $this->get('/api/v1/orders', ['Accept' => 'text/html'])
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Unauthenticated.');
    }

    public function test_web_authentication_still_redirects_html_guests_to_the_login_route(): void
    {
        // The POS has no web login page. Define one only for this control test
        // to prove an eventual web flow keeps the framework's redirect behavior.
        Route::get('/test-login', fn () => 'Sign in')->name('login');
        Route::middleware('web')->middleware('auth')->get(
            '/test-private-page',
            fn () => 'Private'
        );

        $this->get('/test-private-page', ['Accept' => 'text/html'])
            ->assertRedirect('/test-login');
        $this->get('/test-private-page', ['Accept' => 'application/json'])
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Unauthenticated.');
    }
}
