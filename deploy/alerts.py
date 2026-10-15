#!/usr/bin/env python3
"""Deliver fixed, data-minimal Telegram alerts. No customer data or exception text."""
import argparse
import json
import re
import sys
from urllib import request
from common import config

EVENTS = {
    'test': 'TEST: Top Coffee operator alert delivery check. Acknowledge in the pilot register.',
    'backup_failed': 'ACTION: Top Coffee backup or off-site verification failed. Check private backup logs and last verified recovery point.',
    'health_failed': 'ACTION: Top Coffee HTTPS health check failed. Check API, DB, cache, disk and recent failed jobs.',
    'failed_login_spike': 'ACTION: Top Coffee failed-login threshold reached. Investigate account and device security; do not assume fraud.',
    'tls_expiring': 'ACTION: Top Coffee HTTPS certificate is nearing expiry. Check renewal and the certificate served externally.',
    'tls_failed': 'ACTION: Top Coffee certificate verification failed. Check hostname, trust, expiry and connectivity.',
    'backup_stale': 'ACTION: Top Coffee off-site completed backup is missing, stale or unverifiable. Check the independent backup store and last tested recovery point.',
}


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def deliver(settings, event, opener=None):
    token, chat = settings.get('bot_token', ''), settings.get('chat_id', '')
    if not re.fullmatch(r'[0-9]{5,20}:[A-Za-z0-9_-]{20,100}', token) or not re.fullmatch(r'-?[0-9]{1,20}', str(chat)):
        raise ValueError('Configure a real Telegram bot token and numeric chat ID privately.')
    if event not in EVENTS:
        raise ValueError('Unknown alert event.')
    body = json.dumps({'chat_id': str(chat), 'text': EVENTS[event], 'disable_notification': False}).encode()
    req = request.Request('https://api.telegram.org/bot' + token + '/sendMessage', data=body,
                          headers={'Content-Type': 'application/json'}, method='POST')
    opener = opener or request.build_opener(NoRedirect())
    with opener.open(req, timeout=15) as response:
        if response.status != 200:
            raise RuntimeError('Alert provider did not acknowledge delivery.')
        raw = response.read(65537)
    if len(raw) > 65536:
        raise RuntimeError('Oversized alert response.')
    result = json.loads(raw)
    if result.get('ok') is not True or type(result.get('result', {}).get('message_id')) is not int:
        raise RuntimeError('Alert provider rejected the message.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('event', choices=EVENTS)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    try:
        deliver(config(args.config), args.event)
    except Exception:
        # urllib errors contain the bot token in the URL. Never print them.
        parser.exit(1, 'Alert delivery failed. Check private configuration, provider status and network access.\n')
    print('Provider acknowledged alert. Recipient must confirm receipt.')


if __name__ == '__main__':
    main()
