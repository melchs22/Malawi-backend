import logging
from datetime import timedelta

import requests
from celery import shared_task
from django.db.models import Q
from django.utils import timezone

from .models import GaragePayment
from .paychangu import PayChanguClient, PayChanguError

logger = logging.getLogger(__name__)


@shared_task
def reconcile_pending_payments():
    try:
        client = PayChanguClient()
    except PayChanguError:
        logger.exception('Workshop payment reconciliation is not configured.')
        return 0

    now = timezone.now()
    payments = GaragePayment.objects.filter(
        status='PENDING',
        created_at__lte=now - timedelta(minutes=5),
    ).filter(
        Q(last_checked_at__isnull=True)
        | Q(last_checked_at__lte=now - timedelta(minutes=15))
    ).order_by('created_at')[:100]

    checked = 0
    for payment in payments:
        checked += 1
        try:
            data = client.verify_transaction(payment.transaction_reference)
            from .views import apply_verified_payment

            apply_verified_payment(payment, data)
        except (PayChanguError, requests.RequestException, ValueError):
            logger.exception(
                'Could not reconcile workshop payment %s.',
                payment.transaction_reference,
            )
            GaragePayment.objects.filter(
                pk=payment.pk,
                status='PENDING',
            ).update(last_checked_at=timezone.now())
    return checked
