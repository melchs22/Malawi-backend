import hashlib
import hmac
from urllib.parse import quote, urlparse

import requests
from django.conf import settings


class PayChanguError(Exception):
    pass


class PayChanguClient:
    def __init__(self):
        self.secret_key = settings.PAYCHANGU_SECRET_KEY
        self.base_url = settings.PAYCHANGU_BASE_URL.rstrip('/')
        self.expected_mode = settings.PAYCHANGU_MODE
        if not self.secret_key:
            raise PayChanguError('PayChangu is not configured.')
        if not settings.PAYCHANGU_WEBHOOK_SECRET:
            raise PayChanguError('PayChangu webhook signing secret is not configured.')
        if not settings.PAYCHANGU_CALLBACK_URL or not settings.PAYCHANGU_RETURN_URL:
            raise PayChanguError('PayChangu callback and return URLs must be configured.')
        parsed_base_url = urlparse(self.base_url)
        if parsed_base_url.scheme != 'https' or not parsed_base_url.netloc:
            raise PayChanguError('PayChangu API base URL must use HTTPS.')
        if self.expected_mode not in ('live', 'test'):
            raise PayChanguError('PAYCHANGU_MODE must be either live or test.')
        for callback_url in (
            settings.PAYCHANGU_CALLBACK_URL,
            settings.PAYCHANGU_RETURN_URL,
        ):
            parsed_url = urlparse(callback_url)
            if parsed_url.scheme != 'https' or not parsed_url.netloc:
                raise PayChanguError('PayChangu callback and return URLs must use HTTPS.')

    def initiate_transaction(self, payment, user):
        payload = {
            'amount': int(payment.amount),
            'currency': payment.currency,
            'email': user.email,
            'first_name': user.first_name or user.username,
            'last_name': user.last_name or '',
            'callback_url': settings.PAYCHANGU_CALLBACK_URL,
            'return_url': settings.PAYCHANGU_RETURN_URL,
            'tx_ref': payment.transaction_reference,
            'customization': {
                'title': 'Smart Mobility Roadcare',
                'description': f'Workshop invoice {payment.invoice.invoice_number}',
            },
            'meta': {
                'invoice_number': payment.invoice.invoice_number,
                'garage_id': payment.invoice.quote.service_request.garage_id,
            },
        }

        response = requests.post(
            f'{self.base_url}/payment',
            json=payload,
            headers=self._headers(),
            timeout=(5, 20),
        )
        response.raise_for_status()
        try:
            body = response.json()
        except requests.exceptions.JSONDecodeError as error:
            raise PayChanguError('PayChangu returned an invalid checkout response.') from error
        if not isinstance(body, dict):
            raise PayChanguError('PayChangu returned an invalid checkout response.')
        data = body.get('data') if isinstance(body, dict) else None
        checkout_url = data.get('checkout_url') if isinstance(data, dict) else None
        transaction_data = data.get('data') if isinstance(data, dict) else None
        parsed_url = urlparse(checkout_url or '')
        if (
            body.get('status') != 'success'
            or not isinstance(transaction_data, dict)
            or transaction_data.get('mode') != self.expected_mode
            or not parsed_url.scheme == 'https'
            or not parsed_url.hostname
            or not (
                parsed_url.hostname == 'paychangu.com'
                or parsed_url.hostname.endswith('.paychangu.com')
            )
        ):
            raise PayChanguError('PayChangu did not return a valid checkout session.')

        return checkout_url

    def verify_transaction(self, transaction_reference):
        response = requests.get(
            f'{self.base_url}/verify-payment/{quote(transaction_reference, safe="")}',
            headers=self._headers(),
            timeout=(5, 20),
        )
        response.raise_for_status()
        try:
            body = response.json()
        except requests.exceptions.JSONDecodeError as error:
            raise PayChanguError('PayChangu returned an invalid verification response.') from error
        if not isinstance(body, dict):
            raise PayChanguError('PayChangu returned an invalid verification response.')
        data = body.get('data') if isinstance(body, dict) else None
        if body.get('status') != 'success' or not isinstance(data, dict):
            raise PayChanguError('PayChangu could not verify the transaction.')
        return data

    def verify_webhook_signature(self, payload, signature):
        webhook_secret = settings.PAYCHANGU_WEBHOOK_SECRET
        if not webhook_secret or not signature:
            return False
        expected = hmac.new(
            webhook_secret.encode('utf-8'),
            payload,
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    def _headers(self):
        return {
            'Accept': 'application/json',
            'Authorization': f'Bearer {self.secret_key}',
            'Content-Type': 'application/json',
        }
