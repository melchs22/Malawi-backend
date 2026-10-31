import logging
import secrets
import uuid
from decimal import Decimal, InvalidOperation
from urllib.parse import urlencode, urlsplit, urlunsplit, parse_qsl

import requests
from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.mail import send_mail
from django.db import transaction
from django.db.models import Avg, Count, Q, Sum
from django.shortcuts import get_object_or_404, redirect
from django.utils import timezone
from rest_framework import generics, permissions, serializers, status
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.response import Response
from rest_framework.views import APIView

from users.models import Notification, PasswordResetToken

from .models import (
    Garage,
    GarageAuditEvent,
    GarageInvoice,
    GaragePayment,
    GarageQuote,
    GarageReview,
    GarageServiceRequest,
    GarageSettlement,
)
from .paychangu import PayChanguClient, PayChanguError
from .permissions import IsPlatformAdmin, IsRider, IsWorkshopOwner
from .serializers import (
    GarageAdminSerializer,
    GarageAdminInvoiceSerializer,
    GarageDeclineSerializer,
    GarageDetailSerializer,
    GarageApplicationStatusSerializer,
    GarageInvoiceSerializer,
    GarageListSerializer,
    GarageProfileSerializer,
    GarageQuoteCreateSerializer,
    GarageQuoteSerializer,
    GarageRegistrationSerializer,
    GarageRegistrationResponseSerializer,
    GarageReviewSerializer,
    GarageServiceRequestSerializer,
    GarageSettlementCreateSerializer,
    GarageStatusResponseSerializer,
    QuoteResponseSerializer,
)

logger = logging.getLogger(__name__)
User = get_user_model()


def create_audit_event(garage, actor, event_type, from_status='', to_status='', reason='', details=None):
    return GarageAuditEvent.objects.create(
        garage=garage,
        actor=actor,
        event_type=event_type,
        from_status=from_status,
        to_status=to_status,
        reason=reason,
        details=details or {},
    )


def create_notification(recipient, title, message):
    if not recipient:
        return
    Notification.objects.create(
        recipient=recipient,
        target_role='SPECIFIC',
        title=title,
        message=message,
        notification_type='SERVICE',
    )


def create_workshop_owner(garage):
    if garage.owner_user_id:
        return garage.owner_user

    owner = User.objects.filter(
        email__iexact=garage.owner_email,
        role='WORKSHOP',
    ).first()
    if owner and hasattr(owner, 'owned_garage'):
        raise serializers.ValidationError(
            {'owner_email': 'This workshop account already owns a service centre.'}
        )

    if owner is None:
        names = garage.owner_name.strip().split(maxsplit=1)
        owner = User.objects.create_user(
            username=f'workshop_{garage.application_tracking_id}'.lower(),
            email=garage.owner_email,
            password=None,
            first_name=names[0],
            last_name=names[1] if len(names) > 1 else '',
            phone=garage.owner_phone,
            role='WORKSHOP',
            is_active=False,
            is_approved=False,
        )
        owner.set_unusable_password()
        owner.save(update_fields=['password'])

    garage.owner_user = owner
    garage.save(update_fields=['owner_user'])
    return owner


def send_workshop_activation_code(owner):
    PasswordResetToken.objects.filter(user=owner, is_used=False).update(is_used=True)
    code = f'{secrets.randbelow(1_000_000):06d}'
    PasswordResetToken.objects.create(user=owner, token=code)
    send_mail(
        'Activate your Smart Mobility Roadcare workshop account',
        (
            f'Your workshop account has been approved. Use this code to set your password: '
            f'{code}. The code expires in 15 minutes. Select the Workshop account type '
            'when setting your password.'
        ),
        None,
        [owner.email],
        fail_silently=False,
    )


def has_workshop_slot_capacity(garage, booking, quote):
    booked_quotes = GarageQuote.objects.filter(
        service_request__garage=garage,
        service_request__status__in=['ACCEPTED', 'IN_PROGRESS'],
        status='ACCEPTED',
        scheduled_date=quote.scheduled_date,
    ).exclude(service_request=booking)
    if quote.scheduled_time:
        booked_quotes = booked_quotes.filter(
            Q(scheduled_time=quote.scheduled_time)
            | Q(scheduled_time__isnull=True)
        )
    return booked_quotes.count() >= garage.mechanics_count


def apply_verified_payment(payment, provider_data, actor=None):
    if provider_data.get('tx_ref') != payment.transaction_reference:
        raise ValueError('PayChangu transaction reference does not match.')

    try:
        paid_amount = Decimal(str(provider_data.get('amount')))
    except (InvalidOperation, TypeError, ValueError):
        raise ValueError('PayChangu returned an invalid payment amount.')

    if provider_data.get('currency') != payment.currency or paid_amount != payment.amount:
        raise ValueError('PayChangu payment amount or currency does not match the invoice.')

    provider_status = str(provider_data.get('status', '')).lower()
    if str(provider_data.get('mode', '')).lower() != settings.PAYCHANGU_MODE:
        raise ValueError('PayChangu payment mode does not match the configured environment.')
    with transaction.atomic():
        locked_payment = GaragePayment.objects.select_for_update().select_related(
            'invoice__quote__service_request'
        ).get(pk=payment.pk)
        if locked_payment.status == 'PAID':
            return locked_payment

        if provider_status == 'success':
            locked_payment.status = 'PAID'
            locked_payment.provider_reference = str(provider_data.get('reference') or '') or None
            locked_payment.verified_at = timezone.now()
            locked_payment.failure_reason = ''
            locked_payment.last_checked_at = timezone.now()
            invoice = GarageInvoice.objects.select_for_update().get(pk=locked_payment.invoice_id)
            locked_payment.invoice = invoice
            another_successful_payment_exists = invoice.payments.exclude(
                pk=locked_payment.pk
            ).filter(status='PAID').exists()
            locked_payment.is_excess_payment = another_successful_payment_exists
            locked_payment.save(update_fields=[
                'status', 'provider_reference', 'verified_at', 'last_checked_at',
                'is_excess_payment', 'failure_reason', 'updated_at'
            ])
            request = invoice.quote.service_request
            if another_successful_payment_exists:
                create_audit_event(
                    request.garage,
                    actor,
                    'EXCESS_PAYMENT_RECEIVED',
                    from_status=invoice.status,
                    to_status=invoice.status,
                    reason='A second verified payment was received for an already-paid invoice.',
                    details={
                        'invoice_number': invoice.invoice_number,
                        'transaction_reference': locked_payment.transaction_reference,
                        'amount': str(locked_payment.amount),
                        'currency': locked_payment.currency,
                    },
                )
            else:
                invoice.status = 'PAID'
                invoice.paid_at = timezone.now()
                invoice.save(update_fields=['status', 'paid_at'])
                create_audit_event(
                    request.garage,
                    actor,
                    'PAYMENT_CONFIRMED',
                    from_status='ISSUED',
                    to_status='PAID',
                    details={
                        'invoice_number': invoice.invoice_number,
                        'transaction_reference': locked_payment.transaction_reference,
                    },
                )
                create_notification(
                    request.garage.owner_user,
                    'Workshop invoice paid',
                    f'Invoice {invoice.invoice_number} has been paid by the member.',
                )
        elif provider_status in ('failed', 'cancelled', 'canceled'):
            locked_payment.status = 'FAILED'
            locked_payment.failure_reason = provider_status.upper()
            locked_payment.verified_at = timezone.now()
            locked_payment.last_checked_at = timezone.now()
            locked_payment.save(update_fields=[
                'status', 'failure_reason', 'verified_at', 'last_checked_at', 'updated_at'
            ])
        else:
            locked_payment.last_checked_at = timezone.now()
            locked_payment.save(update_fields=['last_checked_at', 'updated_at'])
        return locked_payment


class GarageRegistrationView(generics.CreateAPIView):
    serializer_class = GarageRegistrationSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'garage_registration'

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        garage = serializer.instance
        response_data = GarageRegistrationResponseSerializer(garage).data
        headers = self.get_success_headers(response_data)
        return Response(response_data, status=status.HTTP_201_CREATED, headers=headers)

    def perform_create(self, serializer):
        request = self.request
        serializer.save(
            registration_ip=request.META.get('REMOTE_ADDR'),
            device_type=request.META.get('HTTP_USER_AGENT', '')[:50],
            terms_accepted_at=timezone.now(),
            terms_accepted_ip=request.META.get('REMOTE_ADDR'),
        )


class GarageApplicationStatusView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'garage_registration'

    def get(self, request):
        serializer = GarageApplicationStatusSerializer(
            data={'application_tracking_id': request.query_params.get('tracking_id', '')}
        )
        serializer.is_valid(raise_exception=True)
        garage = get_object_or_404(
            Garage.objects.select_related('verified_by'),
            application_tracking_id=serializer.validated_data['application_tracking_id'],
        )
        return Response(GarageStatusResponseSerializer(garage).data)


class GarageListView(generics.ListAPIView):
    serializer_class = GarageListSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Garage.objects.filter(
            verification_status='VERIFIED'
        ).annotate(
            average_rating=Avg('service_requests__review__rating'),
            rating_count=Count('service_requests__review', distinct=True),
        ).order_by('name')


class GarageDetailView(generics.RetrieveAPIView):
    serializer_class = GarageDetailSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = Garage.objects.filter(
        verification_status='VERIFIED'
    ).annotate(
        average_rating=Avg('service_requests__review__rating'),
        rating_count=Count('service_requests__review', distinct=True),
    )


class GarageServiceRequestCreateView(generics.CreateAPIView):
    serializer_class = GarageServiceRequestSerializer
    permission_classes = [IsRider]

    @transaction.atomic
    def perform_create(self, serializer):
        booking = serializer.save(rider=self.request.user)
        create_audit_event(
            booking.garage,
            self.request.user,
            'BOOKING_CREATED',
            to_status=booking.status,
            details={'booking_id': booking.id},
        )
        create_notification(
            booking.garage.owner_user,
            'New workshop booking',
            f'A member requested {booking.service_category.replace("_", " ").lower()} at your service centre.',
        )


class RiderGarageRequestsView(generics.ListAPIView):
    serializer_class = GarageServiceRequestSerializer
    permission_classes = [IsRider]

    def get_queryset(self):
        return GarageServiceRequest.objects.filter(
            rider=self.request.user
        ).select_related('garage').prefetch_related('quotes__invoice__payments').order_by('-created_at')


class GarageRequestsView(generics.ListAPIView):
    serializer_class = GarageServiceRequestSerializer
    permission_classes = [IsWorkshopOwner]

    def get_queryset(self):
        queryset = GarageServiceRequest.objects.filter(
            garage=self.request.user.owned_garage
        ).select_related('rider', 'garage').prefetch_related(
            'quotes__invoice__payments', 'review'
        )
        request_status = self.request.query_params.get('status')
        if request_status:
            queryset = queryset.filter(status=request_status.upper())
        search = self.request.query_params.get('search')
        if search:
            queryset = queryset.filter(
                Q(description__icontains=search)
                | Q(rider__username__icontains=search)
            )
        return queryset.order_by('-created_at')


class WorkshopRequestDetailView(generics.RetrieveAPIView):
    serializer_class = GarageServiceRequestSerializer
    permission_classes = [IsWorkshopOwner]

    def get_queryset(self):
        return GarageServiceRequest.objects.filter(
            garage=self.request.user.owned_garage
        ).select_related('rider', 'garage').prefetch_related(
            'quotes__invoice__payments', 'review'
        )


class WorkshopGarageProfileView(generics.RetrieveUpdateAPIView):
    serializer_class = GarageProfileSerializer
    permission_classes = [IsWorkshopOwner]

    def get_object(self):
        return self.request.user.owned_garage

    @transaction.atomic
    def perform_update(self, serializer):
        garage = serializer.save()
        create_audit_event(
            garage,
            self.request.user,
            'PROFILE_UPDATED',
            to_status=garage.verification_status,
        )


class WorkshopQuoteView(APIView):
    permission_classes = [IsWorkshopOwner]

    def post(self, request, pk):
        serializer = GarageQuoteCreateSerializer(data=request.data)
        garage = request.user.owned_garage

        with transaction.atomic():
            booking = get_object_or_404(
                GarageServiceRequest.objects.select_for_update(),
                pk=pk,
                garage=garage,
            )
            if booking.status not in ('PENDING', 'QUOTED'):
                return Response(
                    {'detail': 'A quote can only be created for a pending booking.'},
                    status=status.HTTP_409_CONFLICT,
                )

            serializer.context['booking'] = booking
            serializer.is_valid(raise_exception=True)
            last_quote = booking.quotes.order_by('-revision').first()
            if last_quote and last_quote.status == 'ACCEPTED':
                return Response(
                    {'detail': 'An accepted quote cannot be changed.'},
                    status=status.HTTP_409_CONFLICT,
                )

            if last_quote:
                last_quote.status = 'REPLACED'
                last_quote.responded_at = timezone.now()
                last_quote.save(update_fields=['status', 'responded_at'])

            revision = (last_quote.revision if last_quote else 0) + 1
            items = serializer.validated_data['line_items']
            amount = sum(
                (item['unit_amount'] * item['quantity'] for item in items),
                Decimal('0'),
            )
            quote = GarageQuote.objects.create(
                service_request=booking,
                created_by=request.user,
                revision=revision,
                line_items=[
                    {
                        'description': item['description'],
                        'quantity': item['quantity'],
                        'unit_amount': str(item['unit_amount']),
                    }
                    for item in items
                ],
                amount=amount,
                scheduled_date=serializer.validated_data['scheduled_date'],
                scheduled_time=serializer.validated_data.get('scheduled_time'),
            )
            booking.status = 'QUOTED'
            booking.estimated_cost = amount
            booking.save(update_fields=['status', 'estimated_cost', 'updated_at'])
            create_audit_event(
                garage,
                request.user,
                'QUOTE_ISSUED',
                from_status='PENDING' if not last_quote else 'QUOTED',
                to_status='QUOTED',
                details={
                    'booking_id': booking.id,
                    'quote_id': quote.id,
                    'revision': revision,
                    'amount': str(amount),
                    'currency': quote.currency,
                    'scheduled_date': quote.scheduled_date.isoformat(),
                    'scheduled_time': quote.scheduled_time.isoformat() if quote.scheduled_time else None,
                },
            )
            create_notification(
                booking.rider,
                'Workshop quote received',
                (
                    f'{garage.name} sent you a quote of MWK {amount} for '
                    f'{quote.scheduled_date:%d %b %Y}.'
                ),
            )
        return Response(GarageQuoteSerializer(quote).data, status=status.HTTP_201_CREATED)


class RiderQuoteResponseView(APIView):
    permission_classes = [IsRider]

    def post(self, request, pk, quote_id):
        serializer = QuoteResponseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            booking = get_object_or_404(
                GarageServiceRequest.objects.select_for_update().select_related('garage'),
                pk=pk,
                rider=request.user,
            )
            quote = get_object_or_404(
                GarageQuote.objects.select_for_update(),
                pk=quote_id,
                service_request=booking,
                status='PENDING',
            )
            if booking.status != 'QUOTED':
                return Response(
                    {'detail': 'This booking is not awaiting a quote response.'},
                    status=status.HTTP_409_CONFLICT,
                )

            old_status = booking.status
            now = timezone.now()
            if serializer.validated_data['action'] == 'accept':
                garage = Garage.objects.select_for_update().get(pk=booking.garage_id)
                if has_workshop_slot_capacity(garage, booking, quote):
                    return Response(
                        {'detail': 'The confirmed appointment slot is no longer available.'},
                        status=status.HTTP_409_CONFLICT,
                    )
                quote.status = 'ACCEPTED'
                booking.status = 'ACCEPTED'
                notification_title = 'Workshop quote accepted'
                notification_message = f'The member accepted the quote for booking #{booking.id}.'
            else:
                quote.status = 'DECLINED'
                booking.status = 'DECLINED'
                notification_title = 'Workshop quote declined'
                notification_message = f'The member declined the quote for booking #{booking.id}.'
            quote.responded_at = now
            quote.response_reason = serializer.validated_data.get('reason', '').strip()
            quote.save(update_fields=['status', 'responded_at', 'response_reason'])
            if quote.response_reason:
                booking.response_note = quote.response_reason
            booking_update_fields = ['status', 'updated_at']
            if quote.response_reason:
                booking_update_fields.append('response_note')
            booking.save(update_fields=booking_update_fields)
            create_audit_event(
                booking.garage,
                request.user,
                f'QUOTE_{quote.status}',
                from_status=old_status,
                to_status=booking.status,
                reason=quote.response_reason,
                details={'booking_id': booking.id, 'quote_id': quote.id},
            )
            create_notification(
                booking.garage.owner_user,
                notification_title,
                notification_message,
            )
        return Response(GarageServiceRequestSerializer(booking).data)


class WorkshopRequestDeclineView(APIView):
    permission_classes = [IsWorkshopOwner]

    def post(self, request, pk):
        serializer = GarageDeclineSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        garage = request.user.owned_garage
        with transaction.atomic():
            booking = get_object_or_404(
                GarageServiceRequest.objects.select_for_update().select_related('rider'),
                pk=pk,
                garage=garage,
            )
            if booking.status not in ('PENDING', 'QUOTED'):
                return Response(
                    {'detail': 'Only a pending booking can be declined.'},
                    status=status.HTTP_409_CONFLICT,
                )
            previous_status = booking.status
            booking.status = 'DECLINED'
            booking.response_note = serializer.validated_data['reason']
            booking.save(update_fields=['status', 'response_note', 'updated_at'])
            pending_quote = booking.quotes.filter(status='PENDING').first()
            if pending_quote:
                pending_quote.status = 'REPLACED'
                pending_quote.response_reason = serializer.validated_data['reason']
                pending_quote.responded_at = timezone.now()
                pending_quote.save(update_fields=['status', 'response_reason', 'responded_at'])
            create_audit_event(
                garage,
                request.user,
                'BOOKING_DECLINED',
                from_status=previous_status,
                to_status='DECLINED',
                reason=serializer.validated_data['reason'],
                details={'booking_id': booking.id},
            )
            create_notification(
                booking.rider,
                'Workshop booking declined',
                f'{garage.name} declined your booking. Reason: {booking.response_note}',
            )
        return Response(GarageServiceRequestSerializer(booking).data)


class WorkshopRequestStartView(APIView):
    permission_classes = [IsWorkshopOwner]

    def post(self, request, pk):
        garage = request.user.owned_garage
        with transaction.atomic():
            booking = get_object_or_404(
                GarageServiceRequest.objects.select_for_update().select_related('rider'),
                pk=pk,
                garage=garage,
            )
            if booking.status != 'ACCEPTED':
                return Response(
                    {'detail': 'Only a member-accepted booking can be started.'},
                    status=status.HTTP_409_CONFLICT,
                )
            booking.status = 'IN_PROGRESS'
            booking.save(update_fields=['status', 'updated_at'])
            create_audit_event(
                garage,
                request.user,
                'BOOKING_STARTED',
                from_status='ACCEPTED',
                to_status='IN_PROGRESS',
                details={'booking_id': booking.id},
            )
            create_notification(
                booking.rider,
                'Workshop service started',
                f'{garage.name} has started work on your booking.',
            )
        return Response(GarageServiceRequestSerializer(booking).data)


class WorkshopRequestCompleteView(APIView):
    permission_classes = [IsWorkshopOwner]

    def post(self, request, pk):
        garage = request.user.owned_garage
        with transaction.atomic():
            booking = get_object_or_404(
                GarageServiceRequest.objects.select_for_update().select_related('rider'),
                pk=pk,
                garage=garage,
            )
            if booking.status != 'IN_PROGRESS':
                return Response(
                    {'detail': 'Only an in-progress booking can be completed.'},
                    status=status.HTTP_409_CONFLICT,
                )
            quote = booking.quotes.filter(status='ACCEPTED').first()
            if not quote:
                return Response(
                    {'detail': 'An accepted quote is required before completing a booking.'},
                    status=status.HTTP_409_CONFLICT,
                )
            invoice_number = f'SMR-{timezone.now():%Y%m%d}-{uuid.uuid4().hex[:8].upper()}'
            invoice = GarageInvoice.objects.create(
                quote=quote,
                invoice_number=invoice_number,
                amount=quote.amount,
                currency=quote.currency,
            )
            booking.status = 'COMPLETED'
            booking.actual_cost = quote.amount
            booking.save(update_fields=['status', 'actual_cost', 'updated_at'])
            create_audit_event(
                garage,
                request.user,
                'BOOKING_COMPLETED',
                from_status='IN_PROGRESS',
                to_status='COMPLETED',
                details={
                    'booking_id': booking.id,
                    'invoice_number': invoice.invoice_number,
                    'amount': str(invoice.amount),
                },
            )
            create_notification(
                booking.rider,
                'Workshop service completed',
                f'Your service at {garage.name} is complete. Invoice {invoice.invoice_number} is ready for payment.',
            )
        return Response({
            'booking': GarageServiceRequestSerializer(booking).data,
            'invoice': GarageInvoiceSerializer(invoice).data,
        }, status=status.HTTP_201_CREATED)


class RiderGarageRequestCancelView(APIView):
    permission_classes = [IsRider]

    def post(self, request, pk):
        with transaction.atomic():
            booking = get_object_or_404(
                GarageServiceRequest.objects.select_for_update().select_related('garage'),
                pk=pk,
                rider=request.user,
            )
            if booking.status not in ('PENDING', 'QUOTED'):
                return Response(
                    {'detail': 'This booking can no longer be cancelled in the app.'},
                    status=status.HTTP_409_CONFLICT,
                )
            old_status = booking.status
            booking.status = 'CANCELLED'
            booking.save(update_fields=['status', 'updated_at'])
            create_audit_event(
                booking.garage,
                request.user,
                'BOOKING_CANCELLED',
                from_status=old_status,
                to_status='CANCELLED',
                details={'booking_id': booking.id},
            )
            create_notification(
                booking.garage.owner_user,
                'Workshop booking cancelled',
                f'The member cancelled booking #{booking.id}.',
            )
        return Response(GarageServiceRequestSerializer(booking).data)


class RiderGarageReviewCreateView(APIView):
    permission_classes = [IsRider]

    def post(self, request, pk):
        serializer = GarageReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        booking = get_object_or_404(
            GarageServiceRequest.objects.select_related('garage').filter(
                rider=request.user,
                status='COMPLETED',
                quotes__status='ACCEPTED',
                quotes__invoice__status__in=['PAID', 'SETTLED'],
            ).distinct(),
            pk=pk,
        )
        if GarageReview.objects.filter(service_request=booking).exists():
            return Response(
                {'detail': 'A review has already been submitted for this booking.'},
                status=status.HTTP_409_CONFLICT,
            )
        with transaction.atomic():
            review = serializer.save(service_request=booking, rider=request.user)
            create_audit_event(
                booking.garage,
                request.user,
                'WORKSHOP_REVIEW_SUBMITTED',
                details={'booking_id': booking.id, 'review_id': review.id, 'rating': review.rating},
            )
            create_notification(
                booking.garage.owner_user,
                'New workshop review',
                f'A member left a {review.rating}-star review for {booking.garage.name}.',
            )
        return Response(GarageReviewSerializer(review).data, status=status.HTTP_201_CREATED)


class AdminGarageListView(generics.ListCreateAPIView):
    serializer_class = GarageAdminSerializer
    permission_classes = [IsPlatformAdmin]

    def get_queryset(self):
        queryset = Garage.objects.all().select_related('owner_user', 'verified_by').order_by('-registration_date')
        verification_status = self.request.query_params.get('status')
        if verification_status:
            queryset = queryset.filter(verification_status=verification_status.upper())
        search = self.request.query_params.get('search')
        if search:
            queryset = queryset.filter(
                Q(name__icontains=search)
                | Q(owner_name__icontains=search)
                | Q(owner_email__icontains=search)
                | Q(primary_phone__icontains=search)
            )
        return queryset

    @transaction.atomic
    def perform_create(self, serializer):
        garage = serializer.save()
        create_audit_event(
            garage,
            self.request.user,
            'WORKSHOP_CREATED_BY_ADMIN',
            to_status=garage.verification_status,
        )


class AdminGarageDetailView(generics.RetrieveUpdateAPIView):
    serializer_class = GarageAdminSerializer
    permission_classes = [IsPlatformAdmin]
    queryset = Garage.objects.all().select_related('owner_user', 'verified_by')

    @transaction.atomic
    def perform_update(self, serializer):
        garage = serializer.save()
        create_audit_event(
            garage,
            self.request.user,
            'WORKSHOP_UPDATED_BY_ADMIN',
            to_status=garage.verification_status,
        )


class AdminGarageVerificationView(APIView):
    permission_classes = [IsPlatformAdmin]

    def post(self, request, pk):
        action = request.data.get('action')
        reason = str(request.data.get('reason', '')).strip()
        if action not in ('under_review', 'verify', 'reject', 'suspend'):
            return Response(
                {'detail': 'Action must be under_review, verify, reject, or suspend.'},
                status=400,
            )
        if action in ('reject', 'suspend') and not reason:
            return Response({'detail': 'A reason is required for rejection or suspension.'}, status=400)

        with transaction.atomic():
            garage = get_object_or_404(Garage.objects.select_for_update(), pk=pk)
            previous_status = garage.verification_status
            new_status = {
                'under_review': 'UNDER_REVIEW',
                'verify': 'VERIFIED',
                'reject': 'REJECTED',
                'suspend': 'SUSPENDED',
            }[action]
            if previous_status == new_status:
                if action == 'verify':
                    owner_was_unlinked = garage.owner_user_id is None
                    owner = create_workshop_owner(garage)
                    if (
                        owner_was_unlinked
                        or not owner.is_active
                        or not owner.is_approved
                        or not owner.has_usable_password()
                    ):
                        owner.is_active = True
                        owner.is_approved = True
                        owner.save(update_fields=['is_active', 'is_approved'])
                        if not owner.has_usable_password():
                            send_workshop_activation_code(owner)
                        create_audit_event(
                            garage,
                            request.user,
                            'WORKSHOP_OWNER_ACTIVATED',
                            from_status=previous_status,
                            to_status=new_status,
                            details={'owner_user_id': owner.id},
                        )
                        create_notification(
                            owner,
                            'Workshop account approved',
                            f'{garage.name} is approved. Check your email for the code to activate your workshop login.',
                        )
                        return Response({
                            'id': garage.id,
                            'verification_status': garage.verification_status,
                            'owner_account_id': owner.id,
                            'owner_activation_email_sent': not owner.has_usable_password(),
                        })
                return Response({'detail': f'Workshop is already {new_status.lower()}.'}, status=409)

            owner = garage.owner_user
            if action != 'under_review':
                owner = create_workshop_owner(garage)
            garage.verification_status = new_status
            garage.rejection_reason = reason if action == 'reject' else ''
            garage.suspension_reason = reason if action == 'suspend' else ''
            update_fields = [
                'verification_status', 'rejection_reason', 'suspension_reason',
            ]
            if action != 'under_review':
                garage.verified_by = request.user
                garage.verified_at = timezone.now()
                update_fields.extend(['verified_by', 'verified_at'])
            garage.save(update_fields=update_fields)
            if owner:
                owner.is_active = action == 'verify'
                owner.is_approved = action == 'verify'
                owner.save(update_fields=['is_active', 'is_approved'])
            create_audit_event(
                garage,
                request.user,
                f'WORKSHOP_{new_status}',
                from_status=previous_status,
                to_status=new_status,
                reason=reason,
                details={'owner_user_id': owner.id if owner else None},
            )
            if action == 'verify' and owner:
                if not owner.has_usable_password():
                    send_workshop_activation_code(owner)
                create_notification(
                    owner,
                    'Workshop account approved',
                    f'{garage.name} is approved. Check your email for the code to activate your workshop login.',
                )
        return Response({
            'id': garage.id,
            'verification_status': garage.verification_status,
            'owner_account_id': owner.id if owner else None,
            'owner_activation_email_sent': bool(
                action == 'verify' and owner and not owner.has_usable_password()
            ),
        })


class AdminWorkshopRequestListView(generics.ListAPIView):
    serializer_class = GarageServiceRequestSerializer
    permission_classes = [IsPlatformAdmin]

    def get_queryset(self):
        queryset = GarageServiceRequest.objects.select_related(
            'garage', 'rider'
        ).prefetch_related('quotes__invoice__payments', 'review').order_by('-created_at')
        request_status = self.request.query_params.get('status')
        if request_status:
            queryset = queryset.filter(status=request_status.upper())
        garage_id = self.request.query_params.get('garage')
        if garage_id:
            queryset = queryset.filter(garage_id=garage_id)
        return queryset


class AdminGarageReviewListView(generics.ListAPIView):
    serializer_class = GarageReviewSerializer
    permission_classes = [IsPlatformAdmin]

    def get_queryset(self):
        return GarageReview.objects.select_related(
            'rider', 'service_request__garage'
        ).order_by('-created_at')


class AdminGarageAuditListView(generics.ListAPIView):
    permission_classes = [IsPlatformAdmin]

    def get_queryset(self):
        return GarageAuditEvent.objects.filter(
            garage_id=self.kwargs['pk']
        ).select_related('actor').order_by('-created_at')

    def list(self, request, *args, **kwargs):
        queryset = self.get_queryset()
        results = [{
            'id': event.id,
            'actor_id': event.actor_id,
            'actor_name': event.actor.username if event.actor else None,
            'event_type': event.event_type,
            'from_status': event.from_status,
            'to_status': event.to_status,
            'reason': event.reason,
            'details': event.details,
            'created_at': event.created_at,
        } for event in queryset]
        return Response(results)


class AdminGarageStatsView(APIView):
    permission_classes = [IsPlatformAdmin]

    def get(self, request):
        return Response({
            'total_garages': Garage.objects.count(),
            'verified_garages': Garage.objects.filter(verification_status='VERIFIED').count(),
            'pending_garages': Garage.objects.filter(verification_status='SUBMITTED').count(),
            'under_review': Garage.objects.filter(verification_status='UNDER_REVIEW').count(),
            'rejected_garages': Garage.objects.filter(verification_status='REJECTED').count(),
            'suspended_garages': Garage.objects.filter(verification_status='SUSPENDED').count(),
            'pending_bookings': GarageServiceRequest.objects.filter(status__in=['PENDING', 'QUOTED']).count(),
            'unpaid_invoices': GarageInvoice.objects.filter(status='ISSUED').count(),
            'unsettled_paid_invoices': GarageInvoice.objects.filter(status='PAID').count(),
            'excess_payments': GaragePayment.objects.filter(is_excess_payment=True).count(),
        })


class RiderInvoiceCheckoutView(APIView):
    permission_classes = [IsRider]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'workshop_payment'

    def post(self, request, pk):
        try:
            client = PayChanguClient()
        except PayChanguError as error:
            return Response({'detail': str(error)}, status=status.HTTP_503_SERVICE_UNAVAILABLE)

        with transaction.atomic():
            invoice = get_object_or_404(
                GarageInvoice.objects.select_for_update().select_related(
                    'quote__service_request__garage', 'quote__service_request__rider'
                ),
                pk=pk,
                quote__service_request__rider=request.user,
            )
            if invoice.status != 'ISSUED':
                return Response(
                    {'detail': 'Only an unpaid invoice can be checked out.'},
                    status=status.HTTP_409_CONFLICT,
                )
            existing = invoice.payments.filter(status='PENDING').first()
            if existing:
                if not existing.checkout_url:
                    return Response(
                        {'detail': 'A checkout session is already being created. Try again shortly.'},
                        status=status.HTTP_409_CONFLICT,
                    )
                return Response({
                    'transaction_reference': existing.transaction_reference,
                    'checkout_url': existing.checkout_url,
                })

            payment = GaragePayment.objects.create(
                invoice=invoice,
                transaction_reference=f'SMR-{uuid.uuid4()}',
                amount=invoice.amount,
                currency=invoice.currency,
            )
            try:
                checkout_url = client.initiate_transaction(payment, request.user)
            except (requests.RequestException, PayChanguError, ValueError):
                logger.exception(
                    'PayChangu checkout initialization failed for %s',
                    payment.transaction_reference,
                )
                payment.status = 'FAILED'
                payment.failure_reason = 'CHECKOUT_INITIALIZATION_FAILED'
                payment.save(update_fields=['status', 'failure_reason', 'updated_at'])
                return Response(
                    {'detail': 'Could not create a PayChangu checkout. No payment was taken.'},
                    status=status.HTTP_502_BAD_GATEWAY,
                )
            payment.checkout_url = checkout_url
            payment.save(update_fields=['checkout_url', 'updated_at'])
            create_audit_event(
                invoice.quote.service_request.garage,
                request.user,
                'PAYMENT_CHECKOUT_CREATED',
                details={
                    'invoice_number': invoice.invoice_number,
                    'transaction_reference': payment.transaction_reference,
                },
            )
        return Response({
            'transaction_reference': payment.transaction_reference,
            'checkout_url': payment.checkout_url,
        }, status=status.HTTP_201_CREATED)


class RiderInvoicePaymentVerifyView(APIView):
    permission_classes = [IsRider]

    def post(self, request, tx_ref):
        payment = get_object_or_404(
            GaragePayment.objects.select_related('invoice__quote__service_request'),
            transaction_reference=tx_ref,
            invoice__quote__service_request__rider=request.user,
        )
        try:
            data = PayChanguClient().verify_transaction(payment.transaction_reference)
            payment = apply_verified_payment(payment, data, actor=request.user)
        except PayChanguError as error:
            return Response({'detail': str(error)}, status=status.HTTP_502_BAD_GATEWAY)
        except requests.RequestException:
            logger.exception('PayChangu verification failed for %s', tx_ref)
            return Response(
                {'detail': 'Payment verification is temporarily unavailable.'},
                status=status.HTTP_502_BAD_GATEWAY,
            )
        except ValueError as error:
            logger.warning('PayChangu verification mismatch for %s: %s', tx_ref, error)
            return Response({'detail': str(error)}, status=status.HTTP_409_CONFLICT)
        return Response({
            'transaction_reference': payment.transaction_reference,
            'payment_status': payment.status,
            'invoice_status': payment.invoice.status,
        })


class PayChanguCallbackView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        tx_ref = request.query_params.get('tx_ref', '').strip()
        if not tx_ref:
            return Response({'detail': 'tx_ref is required.'}, status=status.HTTP_400_BAD_REQUEST)
        payment = get_object_or_404(GaragePayment, transaction_reference=tx_ref)
        result = payment.status.lower()
        try:
            data = PayChanguClient().verify_transaction(tx_ref)
            payment = apply_verified_payment(payment, data)
            result = payment.status.lower()
        except PayChanguError as error:
            return Response({'detail': str(error)}, status=status.HTTP_502_BAD_GATEWAY)
        except requests.RequestException:
            logger.exception('PayChangu callback verification failed for %s', tx_ref)
            return Response(
                {'detail': 'Payment verification is temporarily unavailable.'},
                status=status.HTTP_502_BAD_GATEWAY,
            )
        except ValueError as error:
            logger.warning('PayChangu callback mismatch for %s: %s', tx_ref, error)
            return Response({'detail': str(error)}, status=status.HTTP_409_CONFLICT)

        parsed_url = urlsplit(settings.PAYCHANGU_RETURN_URL)
        query = dict(parse_qsl(parsed_url.query))
        query.update({'tx_ref': tx_ref, 'payment_status': result})
        return redirect(urlunsplit((
            parsed_url.scheme,
            parsed_url.netloc,
            parsed_url.path,
            urlencode(query),
            parsed_url.fragment,
        )))


class PayChanguWebhookView(APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    def post(self, request):
        try:
            client = PayChanguClient()
        except PayChanguError as error:
            return Response({'detail': str(error)}, status=503)
        signature = request.headers.get('Signature', '')
        if not client.verify_webhook_signature(request.body, signature):
            return Response({'detail': 'Invalid PayChangu webhook signature.'}, status=403)
        payload = request.data
        if not isinstance(payload, dict):
            return Response({'detail': 'Invalid PayChangu webhook payload.'}, status=400)
        nested_payload = payload.get('data')
        nested_tx_ref = nested_payload.get('tx_ref') if isinstance(nested_payload, dict) else None
        tx_ref = str(
            payload.get('tx_ref')
            or nested_tx_ref
            or payload.get('reference')
            or ''
        ).strip()
        if not tx_ref:
            logger.warning('PayChangu webhook has no transaction reference.')
            return Response({'received': True, 'ignored': True}, status=200)
        payment = (
            GaragePayment.objects.filter(
                Q(transaction_reference=tx_ref) | Q(provider_reference=tx_ref)
            ).first()
        )
        if not payment:
            return Response({'received': True, 'ignored': True}, status=200)
        try:
            verified = client.verify_transaction(payment.transaction_reference)
            apply_verified_payment(payment, verified)
        except PayChanguError as error:
            logger.error('PayChangu verification rejected webhook for %s: %s', tx_ref, error)
            return Response({'detail': 'PayChangu transaction verification failed.'}, status=502)
        except requests.RequestException:
            logger.exception('PayChangu webhook verification failed for %s', tx_ref)
            return Response({'detail': 'PayChangu verification is temporarily unavailable.'}, status=502)
        except ValueError as error:
            logger.warning('PayChangu webhook mismatch for %s: %s', tx_ref, error)
            return Response({'detail': str(error)}, status=409)
        return Response({'received': True}, status=200)


class AdminGarageInvoiceListView(generics.ListAPIView):
    serializer_class = GarageAdminInvoiceSerializer
    permission_classes = [IsPlatformAdmin]

    def get_queryset(self):
        queryset = GarageInvoice.objects.select_related(
            'quote__service_request__garage'
        ).prefetch_related('payments', 'settlements')
        invoice_status = self.request.query_params.get('status')
        if invoice_status:
            queryset = queryset.filter(status=invoice_status.upper())
        return queryset.order_by('-issued_at')


class AdminGarageInvoiceSettlementView(APIView):
    permission_classes = [IsPlatformAdmin]

    def post(self, request, pk):
        serializer = GarageSettlementCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            invoice = get_object_or_404(
                GarageInvoice.objects.select_for_update().select_related(
                    'quote__service_request__garage'
                ),
                pk=pk,
            )
            if invoice.status not in ('PAID', 'SETTLED'):
                return Response(
                    {'detail': 'Only a paid invoice can be settled.'},
                    status=status.HTTP_409_CONFLICT,
                )
            if invoice.status == 'SETTLED':
                return Response(
                    {'detail': 'This invoice has already been marked fully settled.'},
                    status=status.HTTP_409_CONFLICT,
                )
            data = serializer.validated_data
            previous_total = invoice.settlements.aggregate(total=Sum('amount'))['total'] or Decimal('0')
            new_total = previous_total + data['amount']
            if new_total > invoice.amount:
                return Response(
                    {'detail': 'Settlement total cannot exceed the invoice amount.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if data['is_final'] and new_total < invoice.amount and not data['notes'].strip():
                return Response(
                    {'detail': 'Explain any final settlement difference in notes.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            settlement = GarageSettlement.objects.create(
                invoice=invoice,
                amount=data['amount'],
                transfer_reference=data['transfer_reference'],
                settled_by=request.user,
                notes=data['notes'],
                is_final=data['is_final'],
            )
            if data['is_final']:
                invoice.status = 'SETTLED'
                invoice.save(update_fields=['status'])
            garage = invoice.quote.service_request.garage
            create_audit_event(
                garage,
                request.user,
                'WORKSHOP_SETTLEMENT_RECORDED',
                from_status='PAID',
                to_status=invoice.status,
                reason=data['notes'],
                details={
                    'invoice_number': invoice.invoice_number,
                    'settlement_id': settlement.id,
                    'amount': str(settlement.amount),
                    'transfer_reference': settlement.transfer_reference,
                    'is_final': data['is_final'],
                },
            )
        return Response({
            'id': settlement.id,
            'invoice_number': invoice.invoice_number,
            'amount': settlement.amount,
            'transfer_reference': settlement.transfer_reference,
            'invoice_status': invoice.status,
        }, status=status.HTTP_201_CREATED)
