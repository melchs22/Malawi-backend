import hashlib
import hmac
import json
import uuid
from datetime import date, time, timedelta
from unittest.mock import patch

from django.core import mail
from django.test import SimpleTestCase, TestCase, override_settings
from rest_framework.exceptions import ValidationError
from rest_framework.test import APIClient

from garages.serializers import GarageRegistrationSerializer, normalize_phone_number
from garages.models import (
    Garage,
    GarageInvoice,
    GaragePayment,
    GarageQuote,
    GarageReview,
    GarageServiceRequest,
)
from users.models import User


class WorkshopPhoneNormalizationTests(SimpleTestCase):
    def test_international_phone_numbers_keep_their_country_code(self):
        self.assertEqual(normalize_phone_number('+256742531052'), '+256742531052')
        self.assertEqual(normalize_phone_number('+224612753982'), '+224612753982')

    def test_local_malawi_phone_number_is_normalized(self):
        self.assertEqual(normalize_phone_number('0742531052'), '+265742531052')

    def test_registration_phone_field_allows_local_number_before_normalization(self):
        serializer = GarageRegistrationSerializer()
        value = serializer.fields['emergency_contact_phone'].run_validation('0742531052')
        self.assertEqual(value, '0742531052')
        self.assertEqual(
            serializer.validate_emergency_contact_phone(value),
            '+265742531052',
        )

    def test_rejects_invalid_international_phone_number(self):
        with self.assertRaises(ValidationError):
            normalize_phone_number('+0123456789')


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    PAYCHANGU_MODE='test',
    SECURE_SSL_REDIRECT=False,
)
class WorkshopAPITests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.owner = self.make_user('owner', 'WORKSHOP')
        self.other_owner = self.make_user('other-owner', 'WORKSHOP')
        self.rider = self.make_user('rider', 'RIDER')
        self.other_rider = self.make_user('other-rider', 'RIDER')
        self.admin = self.make_user('admin', 'ADMIN')
        self.garage = self.make_garage(self.owner, 'Primary Workshop')
        self.other_garage = self.make_garage(self.other_owner, 'Other Workshop')
        self.booking = self.make_booking(self.garage, self.rider)
        self.other_booking = self.make_booking(self.other_garage, self.other_rider)

    def make_user(self, username, role, active=True):
        return User.objects.create_user(
            username=username,
            email=f'{username}@example.mw',
            password='Safe-Strong-159!',
            first_name=username.title(),
            last_name='Test',
            phone=f'+26599{len(username):02d}123456',
            role=role,
            is_active=active,
            is_approved=active,
        )

    def make_garage(self, owner, name):
        return Garage.objects.create(
            name=name,
            garage_type='REGISTERED',
            years_in_operation=5,
            physical_address='Lilongwe, Malawi',
            latitude=-13.9626,
            longitude=33.7741,
            operating_hours={'monday': '08:00-17:00'},
            primary_phone='+265991234567',
            business_email=f'{name.lower().replace(" ", ".")}@example.mw',
            owner_name=f'{owner.first_name} Test',
            owner_national_id=f'NID-{uuid.uuid4().hex[:12]}',
            owner_user=owner,
            owner_phone=owner.phone,
            owner_email=owner.email,
            exterior_photo='garage_photos/exterior.jpg',
            interior_workshop_photo='garage_photos/interior.jpg',
            vehicle_types=['MOTORCYCLE'],
            services_offered=['ROUTINE_SERVICING', 'ENGINE_REPAIR'],
            pricing_info={'currency': 'MWK'},
            avg_turnaround_hours=3,
            working_days=['monday'],
            cancellation_policy='Contact the service centre.',
            payment_method='MOBILE_MONEY',
            account_holder_name=owner.first_name,
            account_number='0987654321',
            provider_name='TNM Mpamba',
            terms_accepted=True,
            verification_status='VERIFIED',
        )

    def next_monday(self):
        days_until_monday = (7 - date.today().weekday()) % 7 or 7
        return date.today() + timedelta(days=days_until_monday)

    def make_booking(self, garage, rider):
        return GarageServiceRequest.objects.create(
            rider=rider,
            garage=garage,
            vehicle_type='MOTORCYCLE',
            service_category='ROUTINE_SERVICING',
            description='Scheduled service',
            preferred_date=self.next_monday(),
            preferred_time=time(10, 0),
        )

    def test_workshop_and_member_queries_are_scoped(self):
        self.client.force_authenticate(self.owner)
        response = self.client.get('/api/garages/garage/requests/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual([item['id'] for item in response.data], [self.booking.id])
        self.assertEqual(
            self.client.get(f'/api/garages/garage/requests/{self.other_booking.id}/').status_code,
            404,
        )

        self.client.force_authenticate(self.rider)
        response = self.client.get('/api/garages/requests/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual([item['id'] for item in response.data], [self.booking.id])
        self.assertEqual(
            self.client.get('/api/garages/admin/').status_code,
            403,
        )

    def test_admin_role_can_access_admin_api_without_staff_flag(self):
        self.assertFalse(self.admin.is_staff)
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/garages/admin/stats/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['total_garages'], 2)

    def test_admin_can_place_workshop_under_review_and_disable_portal_access(self):
        self.client.force_authenticate(self.admin)

        response = self.client.post(
            f'/api/garages/admin/{self.garage.id}/verify/',
            {'action': 'under_review'},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.garage.refresh_from_db()
        self.owner.refresh_from_db()
        self.assertEqual(self.garage.verification_status, 'UNDER_REVIEW')
        self.assertFalse(self.owner.is_active)
        self.assertFalse(self.owner.is_approved)

    def test_workshop_approval_activates_owner_and_emails_password_setup_code(self):
        pending_garage = self.make_garage(self.make_user('pending-owner', 'WORKSHOP', active=False), 'Pending Workshop')
        pending_garage.verification_status = 'SUBMITTED'
        pending_garage.save(update_fields=['verification_status'])
        pending_garage.owner_user.set_unusable_password()
        pending_garage.owner_user.save(update_fields=['password'])

        self.client.force_authenticate(self.admin)
        response = self.client.post(
            f'/api/garages/admin/{pending_garage.id}/verify/',
            {'action': 'verify'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        pending_garage.refresh_from_db()
        pending_garage.owner_user.refresh_from_db()
        self.assertEqual(pending_garage.verification_status, 'VERIFIED')
        self.assertTrue(pending_garage.owner_user.is_active)
        self.assertTrue(response.data['owner_activation_email_sent'])
        self.assertEqual(len(mail.outbox), 1)

        activation_code = mail.outbox[0].body.split('code to set your password: ')[1].split('.')[0]
        reset_response = self.client.post(
            '/api/auth/password-reset/confirm/',
            {
                'email': pending_garage.owner_email,
                'role': 'WORKSHOP',
                'code': activation_code,
                'new_password': 'A-Different-Strong-Password-593!',
            },
            format='json',
        )
        self.assertEqual(reset_response.status_code, 200)
        pending_garage.owner_user.refresh_from_db()
        self.assertTrue(pending_garage.owner_user.check_password('A-Different-Strong-Password-593!'))
        login_response = self.client.post(
            '/api/login/workshop/',
            {
                'username': pending_garage.owner_user.username,
                'password': 'A-Different-Strong-Password-593!',
            },
            format='json',
        )
        self.assertEqual(login_response.status_code, 200, login_response.data)
        self.assertEqual(login_response.data['user']['role'], 'WORKSHOP')

    def test_existing_verified_garage_without_owner_can_be_provisioned(self):
        legacy_owner = self.make_user('legacy-owner', 'WORKSHOP', active=False)
        garage = self.make_garage(legacy_owner, 'Legacy Workshop')
        garage.owner_user = None
        garage.owner_email = 'legacy-owner@example.mw'
        garage.save(update_fields=['owner_user', 'owner_email'])
        legacy_owner.delete()
        self.client.force_authenticate(self.admin)

        response = self.client.post(
            f'/api/garages/admin/{garage.id}/verify/',
            {'action': 'verify'},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        owner = User.objects.get(email='legacy-owner@example.mw', role='WORKSHOP')
        garage.refresh_from_db()
        self.assertEqual(garage.owner_user_id, owner.id)
        self.assertTrue(owner.is_active)
        self.assertTrue(owner.is_approved)
        self.assertFalse(owner.has_usable_password())
        self.assertTrue(response.data['owner_activation_email_sent'])

    def test_quote_accept_complete_checkout_verify_and_review(self):
        self.client.force_authenticate(self.owner)
        quote_response = self.client.post(
            f'/api/garages/garage/requests/{self.booking.id}/quote/',
            {
                'line_items': [
                    {'description': 'Labor', 'quantity': 1, 'unit_amount': 20000},
                    {'description': 'Parts', 'quantity': 1, 'unit_amount': 5000},
                ],
                'scheduled_date': self.booking.preferred_date.isoformat(),
                'scheduled_time': '10:00:00',
            },
            format='json',
        )
        self.assertEqual(quote_response.status_code, 201, quote_response.data)
        quote = GarageQuote.objects.get(pk=quote_response.data['id'])
        self.assertEqual(quote.amount, 25000)
        self.assertEqual(quote.currency, 'MWK')
        self.assertEqual(quote.status, 'PENDING')

        self.client.force_authenticate(self.rider)
        accept_response = self.client.post(
            f'/api/garages/requests/{self.booking.id}/quotes/{quote.id}/respond/',
            {'action': 'accept'},
            format='json',
        )
        self.assertEqual(accept_response.status_code, 200)
        self.assertEqual(accept_response.data['status'], 'ACCEPTED')

        self.client.force_authenticate(self.owner)
        start_response = self.client.post(f'/api/garages/garage/requests/{self.booking.id}/start/')
        self.assertEqual(start_response.status_code, 200)
        complete_response = self.client.post(f'/api/garages/garage/requests/{self.booking.id}/complete/')
        self.assertEqual(complete_response.status_code, 201)
        invoice = GarageInvoice.objects.get(quote=quote)
        self.assertEqual(invoice.amount, 25000)
        self.assertEqual(invoice.currency, 'MWK')

        with patch('garages.views.PayChanguClient') as paychangu:
            paychangu.return_value.initiate_transaction.return_value = (
                'https://checkout.paychangu.com/session/real-reference'
            )
            self.client.force_authenticate(self.rider)
            checkout_response = self.client.post(
                f'/api/garages/invoices/{invoice.id}/checkout/',
                format='json',
            )
            self.assertEqual(checkout_response.status_code, 201)
            self.assertEqual(
                self.client.post(f'/api/garages/invoices/{invoice.id}/checkout/').status_code,
                200,
            )
            paychangu.return_value.initiate_transaction.assert_called_once()

            payment = GaragePayment.objects.get(invoice=invoice)
            paychangu.return_value.verify_transaction.return_value = {
                'tx_ref': payment.transaction_reference,
                'status': 'success',
                'mode': 'test',
                'currency': 'MWK',
                'amount': '25000',
                'reference': 'provider-transaction-123',
            }
            verify_response = self.client.post(
                f'/api/garages/payments/{payment.transaction_reference}/verify/'
            )
            self.assertEqual(verify_response.status_code, 200, verify_response.data)

        invoice.refresh_from_db()
        self.assertEqual(invoice.status, 'PAID')

        self.client.force_authenticate(self.admin)
        settlement_response = self.client.post(
            f'/api/garages/admin/invoices/{invoice.id}/settlements/',
            {
                'amount': 24000,
                'transfer_reference': 'BANK-TRANSFER-TEST-001',
                'notes': 'PayChangu fee withheld by settlement provider.',
                'is_final': True,
            },
            format='json',
        )
        self.assertEqual(settlement_response.status_code, 201, settlement_response.data)
        invoice.refresh_from_db()
        self.assertEqual(invoice.status, 'SETTLED')
        settlement = invoice.settlements.get()
        self.assertTrue(settlement.is_final)

        self.client.force_authenticate(self.rider)
        review_response = self.client.post(
            f'/api/garages/requests/{self.booking.id}/review/',
            {'rating': 5, 'comment': 'Service completed as agreed.'},
            format='json',
        )
        self.assertEqual(review_response.status_code, 201, review_response.data)
        self.assertEqual(GarageReview.objects.get(service_request=self.booking).rating, 5)

    @override_settings(
        PAYCHANGU_SECRET_KEY='test-paychangu-secret',
        PAYCHANGU_WEBHOOK_SECRET='test-webhook-secret',
        PAYCHANGU_CALLBACK_URL='https://api.example.mw/api/garages/payments/callback/',
        PAYCHANGU_RETURN_URL='https://portal.example.mw/payments/result',
    )
    def test_webhook_requires_signature_and_reverifies_transaction(self):
        quote = GarageQuote.objects.create(
            service_request=self.booking,
            created_by=self.owner,
            revision=1,
            line_items=[{'description': 'Service', 'quantity': 1, 'unit_amount': '10000'}],
            amount=10000,
            scheduled_date=self.booking.preferred_date,
            status='ACCEPTED',
        )
        invoice = GarageInvoice.objects.create(
            quote=quote,
            invoice_number='SMR-WEBHOOK-TEST',
            amount=10000,
        )
        payment = GaragePayment.objects.create(
            invoice=invoice,
            transaction_reference='SMR-webhook-test-reference',
            amount=10000,
        )
        self.client.force_authenticate(user=None)
        raw_body = json.dumps({'tx_ref': payment.transaction_reference}).encode()

        rejected = self.client.post(
            '/api/garages/payments/webhook/',
            data=raw_body,
            content_type='application/json',
            HTTP_SIGNATURE='invalid',
        )
        self.assertEqual(rejected.status_code, 403)

        signature = hmac.new(
            b'test-webhook-secret',
            raw_body,
            hashlib.sha256,
        ).hexdigest()
        verified_data = {
            'tx_ref': payment.transaction_reference,
            'status': 'success',
            'mode': 'test',
            'currency': 'MWK',
            'amount': '10000',
            'reference': 'provider-webhook-123',
        }
        with patch(
            'garages.views.PayChanguClient.verify_transaction',
            return_value=verified_data,
        ) as verify_transaction:
            response = self.client.post(
                '/api/garages/payments/webhook/',
                data=raw_body,
                content_type='application/json',
                HTTP_SIGNATURE=signature,
            )
            duplicate_response = self.client.post(
                '/api/garages/payments/webhook/',
                data=raw_body,
                content_type='application/json',
                HTTP_SIGNATURE=signature,
            )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(duplicate_response.status_code, 200, duplicate_response.data)
        verify_transaction.assert_any_call(payment.transaction_reference)
        payment.refresh_from_db()
        invoice.refresh_from_db()
        self.assertEqual(payment.status, 'PAID')
        self.assertEqual(invoice.status, 'PAID')

    @override_settings(
        PAYCHANGU_SECRET_KEY='test-paychangu-secret',
        PAYCHANGU_WEBHOOK_SECRET='test-webhook-secret',
        PAYCHANGU_CALLBACK_URL='https://api.example.mw/api/garages/payments/callback/',
        PAYCHANGU_RETURN_URL='https://portal.example.mw/payments/result',
    )
    def test_second_successful_payment_is_flagged_for_reconciliation(self):
        quote = GarageQuote.objects.create(
            service_request=self.booking,
            created_by=self.owner,
            revision=1,
            line_items=[{'description': 'Service', 'quantity': 1, 'unit_amount': '10000'}],
            amount=10000,
            scheduled_date=self.booking.preferred_date,
            status='ACCEPTED',
        )
        invoice = GarageInvoice.objects.create(
            quote=quote,
            invoice_number='SMR-EXCESS-TEST',
            amount=10000,
            status='PAID',
        )
        GaragePayment.objects.create(
            invoice=invoice,
            transaction_reference='SMR-first-successful-payment',
            amount=10000,
            status='PAID',
        )
        excess_payment = GaragePayment.objects.create(
            invoice=invoice,
            transaction_reference='SMR-second-successful-payment',
            amount=10000,
        )
        verified_data = {
            'tx_ref': excess_payment.transaction_reference,
            'status': 'success',
            'mode': 'test',
            'currency': 'MWK',
            'amount': '10000',
            'reference': 'provider-excess-123',
        }

        self.client.force_authenticate(self.rider)
        with patch(
            'garages.views.PayChanguClient.verify_transaction',
            return_value=verified_data,
        ):
            response = self.client.post(
                f'/api/garages/payments/{excess_payment.transaction_reference}/verify/'
            )

        self.assertEqual(response.status_code, 200, response.data)
        excess_payment.refresh_from_db()
        invoice.refresh_from_db()
        self.assertTrue(excess_payment.is_excess_payment)
        self.assertEqual(excess_payment.status, 'PAID')
        self.assertEqual(invoice.status, 'PAID')

    def test_quote_rejects_closed_days_and_workshop_cannot_write_if_unverified(self):
        closed_date = self.booking.preferred_date + timedelta(days=1)
        self.client.force_authenticate(self.owner)
        response = self.client.post(
            f'/api/garages/garage/requests/{self.booking.id}/quote/',
            {
                'line_items': [{'description': 'Labor', 'quantity': 1, 'unit_amount': 1000}],
                'scheduled_date': closed_date.isoformat(),
                'scheduled_time': '10:00:00',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertFalse(GarageQuote.objects.exists())

        self.garage.verification_status = 'SUSPENDED'
        self.garage.save(update_fields=['verification_status'])
        self.assertEqual(
            self.client.get('/api/garages/garage/requests/').status_code,
            403,
        )

    def test_workshop_role_cannot_be_self_registered(self):
        response = self.client.post(
            '/api/register/',
            {
                'username': 'self-registered-workshop',
                'email': 'self@example.mw',
                'phone': '+265991234568',
                'password': 'Safe-Strong-159!',
                'first_name': 'Self',
                'last_name': 'Registered',
                'role': 'WORKSHOP',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertFalse(User.objects.filter(email='self@example.mw', role='WORKSHOP').exists())
