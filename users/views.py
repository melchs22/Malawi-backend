import secrets
from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser
from django.contrib.auth import get_user_model
from django.db import models

from .serializers import RegisterSerializer, UserSerializer
from .serializers import WalletSerializer, ReferralSerializer, PlatformConfigSerializer, NotificationSerializer, DepositSerializer, WithdrawSerializer, PaymentSerializer, TransactionHistorySerializer, RoadiePaymentSummarySerializer, UserProfileUpdateSerializer, UserProfilePhotoSerializer
from .models import Wallet, Referral, PlatformConfig, Notification, Payment, WalletTransaction, PasswordResetToken
from .fcm import send_push_notification
from rest_framework import generics, permissions, status
from rest_framework.response import Response
try:
    from asgiref.sync import async_to_sync
    from channels.layers import get_channel_layer
except Exception:
    async_to_sync = None
    get_channel_layer = None

from django.utils import timezone
from decimal import Decimal

User = get_user_model()


class RegisterView(generics.CreateAPIView):
    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]


class MeView(APIView):
    def get(self, request):
        serializer = UserSerializer(request.user, context={'request': request})
        return Response(serializer.data)


class UserProfileUpdateView(APIView):
    """
    Update authenticated user's profile information
    GET: Get user profile details
    PATCH: Update profile fields (name, email, phone, username, fcm_token)
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        """Get current user profile"""
        serializer = UserSerializer(request.user, context={'request': request})
        return Response(serializer.data)

    def patch(self, request):
        """Update user profile"""
        serializer = UserProfileUpdateSerializer(
            request.user,
            data=request.data,
            partial=True
        )
        if serializer.is_valid():
            serializer.save()
            return Response({
                'success': True,
                'message': 'Profile updated successfully',
                'user': UserSerializer(request.user, context={'request': request}).data
            }, status=status.HTTP_200_OK)
        return Response({
            'success': False,
            'errors': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)


class RegisterFcmTokenView(APIView):
    """Register or update the authenticated user's FCM token."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        token = request.data.get('fcm_token')
        if not token:
            return Response({'success': False, 'message': 'fcm_token is required.'}, status=status.HTTP_400_BAD_REQUEST)

        request.user.fcm_token = token
        request.user.save(update_fields=['fcm_token'])
        return Response({'success': True, 'message': 'FCM token registered successfully.'}, status=status.HTTP_200_OK)


class UserProfilePhotoUploadView(APIView):
    """
    Upload or update user's profile photo
    POST: Upload a new profile photo
    GET: Get profile photo URL
    """
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def get(self, request):
        """Get user's profile photo"""
        from images.models import UserImage
        try:
            profile_image = UserImage.objects.filter(
                user=request.user,
                image_type='PROFILE'
            ).order_by('-created_at').first()
            
            if profile_image:
                return Response({
                    'profile_photo_url': request.build_absolute_uri(profile_image.original_image.url),
                    'thumbnail_url': request.build_absolute_uri(profile_image.thumbnail.url) if profile_image.thumbnail else None,
                    'created_at': profile_image.created_at,
                    'id': profile_image.id
                })
            return Response({
                'profile_photo_url': None,
                'message': 'No profile photo uploaded yet'
            }, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            return Response(
                {'error': str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    def post(self, request):
        """Upload a new profile photo"""
        serializer = UserProfilePhotoSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({
                'success': False,
                'errors': serializer.errors
            }, status=status.HTTP_400_BAD_REQUEST)

        try:
            from images.models import UserImage
            
            # Delete old profile photos
            UserImage.objects.filter(
                user=request.user,
                image_type='PROFILE'
            ).delete()
            
            # Create new profile photo
            profile_image = UserImage.objects.create(
                user=request.user,
                external_id=request.user.external_id or '',
                image_type='PROFILE',
                original_image=serializer.validated_data['profile_photo'],
                original_filename=serializer.validated_data['profile_photo'].name
            )
            
            return Response({
                'success': True,
                'message': 'Profile photo uploaded successfully',
                'profile_photo': {
                    'id': profile_image.id,
                    'url': request.build_absolute_uri(profile_image.original_image.url),
                    'thumbnail_url': request.build_absolute_uri(profile_image.thumbnail.url) if profile_image.thumbnail else None,
                    'created_at': profile_image.created_at
                }
            }, status=status.HTTP_201_CREATED)
        except Exception as e:
            return Response({
                'success': False,
                'error': str(e)
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class MyWalletView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        wallet, _ = Wallet.objects.get_or_create(user=request.user)
        
        # Get all payments
        payments = Payment.objects.filter(user=request.user).order_by('-created_at')
        
        # Get wallet transactions that are NOT redundant with payments
        # (Deposits and Withdrawals are already represented by Payment objects)
        from django.db.models import Q
        transactions = WalletTransaction.objects.filter(wallet=wallet).exclude(
            Q(reason__startswith='Deposit ') | 
            Q(reason__startswith='Withdrawal request ')
        ).order_by('-created_at')
        
        # Combine and serialize using the history serializer
        combined = list(payments) + list(transactions)
        combined.sort(key=lambda x: x.created_at, reverse=True)
        
        from .serializers import WalletSerializer, TransactionHistorySerializer
        history_data = TransactionHistorySerializer(combined, many=True).data
        wallet_data = WalletSerializer(wallet).data
        wallet_data['transactions'] = history_data  # Overlay combined history
        
        return Response(wallet_data)


class MyReferralsView(generics.ListAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = ReferralSerializer

    def get_queryset(self):
        return Referral.objects.filter(referrer=self.request.user).order_by('-created_at')


class NotificationListCreateView(generics.ListCreateAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user).order_by('-created_at')

    def perform_create(self, serializer):
        notif = serializer.save(recipient=self.request.user)
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer
            channel_layer = get_channel_layer()
            async_to_sync(channel_layer.group_send)(f'user_{self.request.user.id}', {'type': 'notification', 'notification': NotificationSerializer(notif).data})
        except Exception:
            pass


class NotificationRUDView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user)


class RoadieStatusUpdateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if request.user.role != 'RODIE':
            return Response({'error': 'Only roadies can update status'}, status=status.HTTP_403_FORBIDDEN)
        is_online = request.data.get('is_online')
        if is_online is None:
            return Response({'error': 'is_online field required'}, status=status.HTTP_400_BAD_REQUEST)
        
        # 1. Enforce account approval for going online
        if bool(is_online) and not request.user.is_approved:
            return Response({
                'error': 'Account Pending Approval'
            }, status=status.HTTP_403_FORBIDDEN)
            
        # 2. Enforce service selection for going online
        if bool(is_online) and not getattr(request.user, 'services_selected', False):
            return Response({
                'error': 'Select a service to provide'
            }, status=status.HTTP_403_FORBIDDEN)

        from .models import RodieAvailabilityLog
        from django.utils import timezone
        
        is_online_bool = bool(is_online)
        get_user_model().objects.filter(id=request.user.id).update(is_online=is_online_bool)
        request.user.is_online = is_online_bool  # Update in-memory for the response

        # Logging logic
        if is_online_bool:
            # Check for existing open log to avoid duplicates
            if not RodieAvailabilityLog.objects.filter(user=request.user, went_offline_at__isnull=True).exists():
                RodieAvailabilityLog.objects.create(user=request.user, went_online_at=timezone.now())
        else:
            # Close all open logs
            RodieAvailabilityLog.objects.filter(user=request.user, went_offline_at__isnull=True).update(went_offline_at=timezone.now())

        try:
            if get_channel_layer and async_to_sync:
                channel_layer = get_channel_layer()
                group_user = f'user_{request.user.id}'
                group_rodie = f'rodie_{request.user.id}'
                group_riders = 'role_RIDER'

                status_payload = {
                    'type': 'rodie.status', 
                    'is_online': request.user.is_online, 
                    'rodie_id': request.user.id,
                    'username': request.user.username,
                    'lat': float(request.user.lat) if (request.user.is_online and request.user.lat) else None,
                    'lng': float(request.user.lng) if (request.user.is_online and request.user.lng) else None,
                }

                async_to_sync(channel_layer.group_send)(group_user, status_payload)
                async_to_sync(channel_layer.group_send)(group_rodie, status_payload)
                # Broadcast to all riders so their maps update instantly
                async_to_sync(channel_layer.group_send)(group_riders, status_payload)
        except Exception:
            pass
        return Response({'is_online': request.user.is_online})


class PlatformConfigView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        cfg = PlatformConfig.objects.first()
        if not cfg:
            cfg = PlatformConfig.objects.create()
        serializer = PlatformConfigSerializer(cfg)
        return Response(serializer.data)

    def post(self, request):
        if not request.user.is_authenticated or request.user.role != 'ADMIN':
            return Response({'detail': 'Admin access required'}, status=status.HTTP_403_FORBIDDEN)
        cfg = PlatformConfig.objects.first()
        if not cfg:
            cfg = PlatformConfig.objects.create()
        serializer = PlatformConfigSerializer(cfg, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class DepositView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        import uuid
        from .pesapal import PesapalClient

        amount = request.data.get('amount')
        if not amount or float(amount) <= 0:
            return Response({'error': 'A valid deposit amount is required.'}, status=status.HTTP_400_BAD_REQUEST)
            
        reference = f"DEP-{uuid.uuid4().hex[:12].upper()}"
        payment = Payment.objects.create(
            user=request.user,
            amount=amount,
            transaction_type='DEPOSIT',
            status='PENDING',
            reference=reference,
            description=f"Wallet deposit by {request.user.username}"
        )

        try:
            client = PesapalClient()
            # Correct redirect URL for the user after payment
            callback_url = request.build_absolute_uri('/api/wallet/')
            # IPN URL for server-to-server confirmation
            ipn_url = request.build_absolute_uri('/api/pesapal/ipn/')
            
            response = client.submit_order(payment, callback_url, phone_number=None)
            # If Pesapal returns an error payload, fail the payment and surface a clear 502
            if response and isinstance(response, dict) and response.get('error'):
                payment.status = 'FAILED'
                payment.save()
                err = response.get('error') or {}
                err_type = err.get('error_type') or err.get('type')
                code = err.get('code')
                # Map known Pesapal test-limit errors to a user-friendly 400
                if err_type == 'test_transactions_exceeded' or code == 'maximum_amount_limit_exceeded':
                    return Response({
                        'error': 'Pesapal test transactions limit exceeded',
                        'message': 'Pesapal rejected this request: test transactions limit exceeded. Use live (production) credentials or contact Pesapal to increase your test limits.'
                    }, status=status.HTTP_400_BAD_REQUEST)

                # Otherwise surface the Pesapal response as a 502 for visibility
                return Response({
                    'error': 'Pesapal error',
                    'pesapal_response': response
                }, status=status.HTTP_502_BAD_GATEWAY)

            tracking_id = response.get('order_tracking_id')
            payment.processor_id = tracking_id
            payment.save()

            redirect_url = response.get('redirect_url')
            if not redirect_url:
                payment.status = 'FAILED'
                payment.save()
                return Response({
                    'error': 'Could not generate payment link.',
                    'pesapal_response': response, # Temporary for debugging
                }, status=status.HTTP_502_BAD_GATEWAY)

            return Response({
                'payment_id': payment.id,
                'redirect_url': redirect_url,
                'reference': reference,
            })
        except Exception as e:
            payment.status = 'FAILED'
            payment.save()
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class WithdrawView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        from django.db import transaction
        
        serializer = WithdrawSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        amount = serializer.validated_data['amount']
        phone_number = serializer.validated_data.get('phone_number', request.user.phone)

        try:
            with transaction.atomic():
                # Lock the wallet row for this user
                wallet = Wallet.objects.select_for_update().filter(user=request.user).first()
                if not wallet:
                    wallet = Wallet.objects.create(user=request.user)
                
                # Check sufficient funds (WITH LOCK)
                if wallet.balance < amount:
                    return Response({
                        'error': 'Insufficient funds', 
                        'available_balance': str(wallet.balance),
                        'requested_amount': str(amount)
                    }, status=status.HTTP_400_BAD_REQUEST)

                # Deduct amount from wallet
                wallet.balance -= amount
                wallet.save()

                # Create withdrawal request
                import uuid
                reference = f"WTH-{uuid.uuid4().hex[:12].upper()}"
                
                payment = Payment.objects.create(
                    user=request.user,
                    amount=amount,
                    transaction_type='WITHDRAWAL',
                    status='PENDING', 
                    reference=reference,
                    description=f"Withdrawal request to {phone_number}"
                )

                # Create wallet transaction
                WalletTransaction.objects.create(
                    wallet=wallet,
                    amount=-amount,
                    reason=f"Withdrawal request {reference}"
                )

                # Manual Payout Process
                # The payment remains in PENDING status. Admin will process it manually
                # and mark it as COMPLETED or FAILED in the Django Admin panel.
                message = 'Withdrawal request submitted successfully'

                return Response({
                    'success': True,
                    'message': message,
                    'reference': reference,
                    'amount': str(amount),
                    'phone_number': phone_number,
                    'new_balance': str(wallet.balance)
                })

        except Exception as e:
            return Response({
                'error': 'Failed to process withdrawal request',
                'details': str(e)
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class RoadiePaymentsView(APIView):
    """
    GET: Retrieve payment history and wallet summary for roadies
    POST: Initiate a deposit payment
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        # Only roadies can access their payments
        if request.user.role != 'RODIE':
            return Response(
                {'error': 'Only roadies can access this endpoint'},
                status=status.HTTP_403_FORBIDDEN
            )

        # Get wallet
        wallet, _ = Wallet.objects.get_or_create(user=request.user)

        # Get all payments - exclude completed deposits as they are redundant with WalletTransactions
        # Keep all withdrawals so we can see their PENDING/COMPLETED status
        payments_history = Payment.objects.filter(user=request.user).exclude(
            transaction_type='DEPOSIT', status='COMPLETED'
        ).order_by('-created_at')

        # Get wallet transactions - exclude those that already have a Payment record (withdrawals)
        # to avoid double-counting in the history list.
        transactions = WalletTransaction.objects.filter(wallet=wallet).exclude(
            reason__icontains='Withdrawal request'
        ).order_by('-created_at')

        # Combine and serialize
        combined = list(payments_history) + list(transactions)
        combined.sort(key=lambda x: x.created_at, reverse=True)

        # Serialize transaction history
        history_serializer = TransactionHistorySerializer(combined, many=True)

        # Calculate summary stats
        # Total earned includes all successful deposits
        total_deposits = WalletTransaction.objects.filter(
            wallet=wallet,
            amount__gt=0
        ).aggregate(
            total=models.Sum('amount')
        )['total'] or 0

        # Total withdrawn includes all withdrawals that have been deducted from balance (PENDING or COMPLETED)
        total_withdrawals = Payment.objects.filter(
            user=request.user,
            transaction_type='WITHDRAWAL'
        ).exclude(status='FAILED').exclude(status='CANCELLED').aggregate(
            total=models.Sum('amount')
        )['total'] or 0

        pending_deposits = Payment.objects.filter(
            user=request.user,
            transaction_type='DEPOSIT',
            status='PENDING'
        ).aggregate(total=models.Sum('amount'))['total'] or 0

        pending_withdrawals = Payment.objects.filter(
            user=request.user,
            transaction_type='WITHDRAWAL',
            status='PENDING'
        ).aggregate(total=models.Sum('amount'))['total'] or 0
        
        summary = {
            'current_balance': wallet.balance,
            'total_earned': total_deposits, # In context of Roadie, deposits are often income or balance topups
            'total_withdrawn': total_withdrawals,
            'pending_deposits': pending_deposits,
            'pending_withdrawals': pending_withdrawals,
            'transaction_count': len(combined)
        }

        return Response({
            'summary': summary,
            'transactions': history_serializer.data,
            'wallet_id': wallet.id,
            'user_id': request.user.id,
            'user_external_id': request.user.external_id
        })

    def post(self, request):
        # Only roadies can make deposits here (though they can also use /wallet/deposit/ now)
        if request.user.role != 'RODIE':
            return Response(
                {'error': 'Only roadies can make deposits'},
                status=status.HTTP_403_FORBIDDEN
            )

        import uuid
        from .pesapal import PesapalClient

        reference = f"DEP-{uuid.uuid4().hex[:12].upper()}"
        payment = Payment.objects.create(
            user=request.user,
            amount=0, # Placeholder, updated via IPN/Status check
            transaction_type='DEPOSIT',
            status='PENDING',
            reference=reference,
            description=f"Wallet deposit by {request.user.username}"
        )
        try:
            client = PesapalClient()
            # Redirect URL for roadies
            callback_url = request.build_absolute_uri('/api/roadie/payments/')
            response = client.submit_order(payment, callback_url, phone_number=None)
            tracking_id = response.get('order_tracking_id')
            payment.processor_id = tracking_id
            payment.save()

            return Response({
                'success': True,
                'payment_id': payment.id,
                'redirect_url': response.get('redirect_url'),
                'reference': reference,
                'message': 'Payment initiated. Proceed to Pesapal to complete your deposit.'
            }, status=status.HTTP_201_CREATED)
        except Exception as e:
            payment.status = 'FAILED'
            payment.save()
            return Response({
                'success': False,
                'error': str(e),
                'message': 'Failed to initiate payment.'
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class PaymentStatusView(APIView):
    """
    GET: Check the status of a specific payment
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, reference):
        try:
            payment = Payment.objects.get(reference=reference, user=request.user)
            
            # If payment is still pending, try to get updated status from Pesapal
            if payment.status == 'PENDING' and payment.processor_id:
                try:
                    from .pesapal import PesapalClient
                    from django.db import transaction as db_transaction
                    client = PesapalClient()
                    status_data = client.get_transaction_status(payment.processor_id)
                    print(f"Pesapal Polling Status for {payment.reference}: {status_data}")
                    
                    if status_data:
                        pesapal_status = status_data.get('payment_status_description', '').upper()
                        # Also handle status_code 1 which means Completed in V3
                        status_code = status_data.get('status_code')
                        
                        if pesapal_status == 'COMPLETED' or status_code == 1:
                            actual_amount = status_data.get('amount', payment.amount)
                            
                            with db_transaction.atomic():
                                # Re-fetch with row lock to prevent double-crediting
                                payment = Payment.objects.select_for_update().get(id=payment.id)
                                if payment.status == 'COMPLETED':
                                    pass  # Already processed by IPN or another poll
                                else:
                                    payment.amount = actual_amount
                                    payment.status = 'COMPLETED'
                                    payment.save()
                                    
                                    # Credit wallet if this is a deposit
                                    if payment.transaction_type == 'DEPOSIT':
                                        wallet, _ = Wallet.objects.get_or_create(user=payment.user)
                                        wallet.balance += Decimal(str(actual_amount))
                                        wallet.save()
                                        WalletTransaction.objects.create(
                                            wallet=wallet,
                                            amount=actual_amount,
                                            reason=f"Deposit {payment.reference}"
                                        )
                        elif pesapal_status == 'FAILED':
                            payment.status = 'FAILED'
                            payment.save()
                except Exception as e:
                    print(f"Failed to update payment status: {e}")

            return Response({
                'success': True,
                'payment': {
                    'id': payment.id,
                    'reference': payment.reference,
                    'amount': str(payment.amount),
                    'status': payment.status,
                    'transaction_type': payment.transaction_type,
                    'created_at': payment.created_at,
                    'updated_at': payment.updated_at
                }
            })

        except Payment.DoesNotExist:
            return Response({
                'success': False,
                'error': 'Payment not found'
            }, status=status.HTTP_404_NOT_FOUND)


class PesapalIPNView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        tracking_id = request.query_params.get('OrderTrackingId')
        merchant_reference = request.query_params.get('OrderMerchantReference')
        
        if not tracking_id or not merchant_reference:
            return Response({'status': 'ignored', 'message': 'Missing parameters'}, status=status.HTTP_200_OK)

        from .pesapal import PesapalClient
        from django.db import transaction

        try:
            with transaction.atomic():
                # Lock the payment row to prevent double-processing/race conditions
                try:
                    payment = Payment.objects.select_for_update().get(reference=merchant_reference)
                except Payment.DoesNotExist:
                    return Response({'status': 'not found', 'message': 'Payment not found'}, status=status.HTTP_404_NOT_FOUND)

                client = PesapalClient()
                status_data = client.get_transaction_status(tracking_id)
                
                if not status_data:
                    if payment.status == 'PENDING':
                        payment.status = 'FAILED'
                        payment.save()
                    return Response({'status': 'failed', 'message': 'Could not verify payment status'}, status=status.HTTP_400_BAD_REQUEST)
                
                pesapal_status = status_data.get('payment_status_description', '').upper()
                status_code = status_data.get('status_code')
                actual_amount = status_data.get('amount', payment.amount)
                
                # Check if already processed to avoid double crediting
                if payment.status == 'COMPLETED':
                    return Response({'status': 'already_processed', 'payment_status': 'COMPLETED'})

                payment.amount = actual_amount
                print(f"Pesapal IPN - Payment {payment.reference} status: {pesapal_status}, Code: {status_code}, Amount: {actual_amount}")
                
                if pesapal_status == 'COMPLETED' or status_code == 1:
                    payment.status = 'COMPLETED'
                    payment.save()
                    
                    if payment.transaction_type == 'DEPOSIT':
                        wallet, _ = Wallet.objects.get_or_create(user=payment.user)
                        wallet.balance += Decimal(str(actual_amount))
                        wallet.save()
                        WalletTransaction.objects.create(
                            wallet=wallet,
                            amount=actual_amount,
                            reason=f"Deposit {payment.reference}"
                        )
                        print(f"Deposit completed: {payment.amount} added to {payment.user.username}'s wallet")
                        
                elif pesapal_status == 'FAILED':
                    payment.status = 'FAILED'
                    payment.save()
                    print(f"Payment failed: {payment.reference}")
                    
        except Exception as e:
            print(f"Pesapal IPN Error: {e}")
            import logging; logging.exception("Pesapal IPN critical error")
            return Response({'status': 'error', 'message': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        return Response({
            'orderNotificationType': request.query_params.get('OrderNotificationType'),
            'orderTrackingId': tracking_id,
            'orderMerchantReference': merchant_reference,
            'status': 200,
            'payment_status': payment.status
        })



@api_view(['POST'])
@permission_classes([IsAuthenticated])
def submit_feedback(request):
    """
    Submit user feedback/inquiries as a SupportTicket to the CRM
    """
    try:
        message = request.data.get('message', '').strip()
        
        if not message:
            return Response(
                {'error': 'Message cannot be empty'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        from .models import SupportTicket
        
        # Create a support ticket in the database (CRM)
        ticket = SupportTicket.objects.create(
            user=request.user,
            user_type=request.user.role if request.user.role in ['RIDER', 'RODIE'] else 'RIDER',
            subject="App Feedback/Inquiry",
            message=message,
            status='PENDING'
        )
        
        print(f"✅ Support Ticket {ticket.support_id} created for {request.user.username}")
        
        return Response({
            'success': True,
            'message': 'Feedback submitted successfully',
            'support_id': ticket.support_id
        }, status=status.HTTP_200_OK)
    except Exception as e:
        print(f"❌ Feedback Error: {e}")
        return Response({
            'error': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


from django.core.mail import send_mail

class PasswordResetRequestView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'password_reset'

    def post(self, request):
        email = request.data.get('email')
        role = request.data.get('role')

        if not email or not role:
            return Response({'error': 'Email and role are required'}, status=status.HTTP_400_BAD_REQUEST)

        user = User.objects.filter(email=email, role=role).first()
        if not user or not user.is_active:
            # We return 200 even if user not found for security (don't reveal registered emails)
            return Response({'message': 'If an account exists, a code has been sent.'}, status=status.HTTP_200_OK)

        # Generate 6-digit OTP
        PasswordResetToken.objects.filter(user=user, is_used=False).update(is_used=True)
        token_str = f'{secrets.randbelow(1_000_000):06d}'
        PasswordResetToken.objects.create(user=user, token=token_str)

        # Send email
        try:
            send_mail(
                'Vehix Password Reset Code',
                f'Your password reset code is: {token_str}. It will expire in 15 minutes.',
                None,  # Uses DEFAULT_FROM_EMAIL from settings
                [email],
                fail_silently=False,
            )
        except Exception as e:
            return Response({'error': 'Failed to send email. Please contact support.'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        return Response({'message': 'If an account exists, a code has been sent.'}, status=status.HTTP_200_OK)


class PasswordResetConfirmView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'password_reset_confirm'

    def post(self, request):
        email = request.data.get('email')
        role = request.data.get('role')
        token_str = request.data.get('code')
        new_password = request.data.get('new_password')

        if not all([email, role, token_str, new_password]):
            return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)

        user = User.objects.filter(email=email, role=role).first()
        if not user or not user.is_active:
            return Response({'error': 'Invalid request'}, status=status.HTTP_400_BAD_REQUEST)

        reset_token = PasswordResetToken.objects.filter(user=user, token=token_str, is_used=False).last()

        if not reset_token or not reset_token.is_valid():
            return Response({'error': 'Invalid or expired code'}, status=status.HTTP_400_BAD_REQUEST)

        from django.contrib.auth.password_validation import validate_password
        from django.core.exceptions import ValidationError as DjangoValidationError

        try:
            validate_password(new_password, user=user)
        except DjangoValidationError as error:
            return Response({'error': error.messages}, status=status.HTTP_400_BAD_REQUEST)

        # Update password
        user.set_password(new_password)
        user.save(update_fields=['password'])

        # Invalidate token
        reset_token.is_used = True
        reset_token.save()

        return Response({'message': 'Password has been reset successfully'}, status=status.HTTP_200_OK)


class UserProfilePasswordChangeView(APIView):
    """
    Allow authenticated user to change their own password
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        current_password = request.data.get('current_password')
        new_password = request.data.get('new_password')
        
        if not current_password or not new_password:
            return Response(
                {'error': 'Current and new password are required'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
            
        user = request.user
        
        # Verify current password
        if not user.check_password(current_password):
            return Response(
                {'error': 'Invalid current password'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Optional: Additional password strength validation
        if len(new_password) < 6:
            return Response(
                {'error': 'New password must be at least 6 characters'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Set and save new password
        user.set_password(new_password)
        user.save(update_fields=['password'])
        
        return Response({
            'success': True,
            'message': 'Password updated successfully'
        })

class AccountDeletionEligibilityView(APIView):
    """
    Check if the authenticated user is eligible for account deletion.
    Returns a list of reasons if ineligible.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        reasons = []
        
        from django.apps import apps
        ServiceRequest = apps.get_model('service_requests', 'ServiceRequest')
        Dispute = apps.get_model('service_requests', 'Dispute')
        
        # 1. Check for active request/job
        if user.role == 'RIDER':
            active_requests = ServiceRequest.objects.filter(
                rider=user,
                status__in=['REQUESTED', 'ACCEPTED', 'EN_ROUTE', 'ARRIVED', 'STARTED']
            ).exists()
        else:
            active_requests = ServiceRequest.objects.filter(
                rodie=user,
                status__in=['ACCEPTED', 'EN_ROUTE', 'ARRIVED', 'STARTED']
            ).exists()
            
        if active_requests:
            reasons.append("You have an active request or job in progress.")
            
        # 2. Check for pending transaction
        pending_tx = Payment.objects.filter(user=user, status='PENDING').exists()
        if pending_tx:
            reasons.append("You have a pending payment or withdrawal transaction.")
            
        # 3. Check wallet balance
        wallet, _ = Wallet.objects.get_or_create(user=user)
        if wallet.balance > 0:
            reasons.append(f"Your wallet balance is UGX {wallet.balance}. It must be zero to delete your account.")
        elif wallet.balance < 0:
            reasons.append(f"You have a negative balance of UGX {wallet.balance}. Please clear your debt before deletion.")
            
        # 4. Check for unpaid service fees (for Roadies)
        if user.role in ['RODIE', 'MECHANIC']:
            unpaid_fees = ServiceRequest.objects.filter(
                rodie=user,
                status='COMPLETED',
                fee_charged=False
            ).exists()
            if unpaid_fees:
                reasons.append("You have unpaid service fees for completed jobs.")
                
        # 5. Check for unresolved disputes (use separate queries for better performance)
        has_dispute_raised = Dispute.objects.filter(raised_by=user, status='PENDING').exists()
        has_dispute_as_rider = Dispute.objects.filter(request__rider=user, status='PENDING').exists()
        has_dispute_as_rodie = Dispute.objects.filter(request__rodie=user, status='PENDING').exists()
        if has_dispute_raised or has_dispute_as_rider or has_dispute_as_rodie:
            reasons.append("You have one or more unresolved disputes.")
            
        return Response({
            'eligible': len(reasons) == 0,
            'reasons': reasons
        })

class RequestAccountDeletionView(APIView):
    """
    Submit a request for account deletion.
    User must be eligible.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user = request.user
        reason_text = request.data.get('reason', '')
        
        # Re-check eligibility server-side for safety
        eligibility_view = AccountDeletionEligibilityView()
        eligibility_response = eligibility_view.get(request)
        if not eligibility_response.data.get('eligible'):
            return Response({
                'success': False,
                'message': 'Account is not eligible for deletion.',
                'reasons': eligibility_response.data.get('reasons')
            }, status=status.HTTP_400_BAD_REQUEST)
            
        # Broadcast session invalidation to active websocket connections before deactivation
        try:
            from channels.layers import get_channel_layer
            from asgiref.sync import async_to_sync
            channel_layer = get_channel_layer()
            if channel_layer:
                group_name = f"rider_{user.id}" if user.role == 'RIDER' else f"rodie_{user.id}"
                async_to_sync(channel_layer.group_send)(
                    group_name,
                    {
                        "type": "session_invalidated",
                        "message": "Your account has been deleted. You have been logged out."
                    }
                )
        except Exception as e:
            print(f"DEBUG DELETION: Could not send session_invalidated WebSocket event: {e}", flush=True)

        # Set deletion status
        user.deletion_status = 'PENDING'
        user.deletion_requested_at = timezone.now()
        user.deletion_reason = reason_text
        user.is_active = False  # Deactivate immediately
        user.is_deleted = True  # Soft delete to hide from active lists
        user.save(update_fields=['deletion_status', 'deletion_requested_at', 'deletion_reason', 'is_active', 'is_deleted'])
        
        # Log out effectively by clearing any session or token related data if needed
        # In JWT world, we can't easily invalidate tokens without a blacklist, 
        # but we can clear the current_login_id to force logout if our auth uses it.
        user.current_login_id = None
        user.save(update_fields=['current_login_id'])
        
        return Response({
            'success': True,
            'message': 'Account deletion request submitted. You have been logged out.'
        })

from rest_framework import viewsets
from rest_framework.decorators import action
from .models import Notification
from .serializers import NotificationSerializer

class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet for viewing and managing user notifications
    """
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user)

    @action(detail=True, methods=['post'])
    def mark_as_read(self, request, pk=None):
        notification = self.get_object()
        notification.is_read = True
        notification.save()
        return Response({'status': 'marked as read'})

    @action(detail=False, methods=['post'])
    def mark_all_as_read(self, request):
        Notification.objects.filter(recipient=self.request.user, is_read=False).update(is_read=True)
        return Response({'status': 'all marked as read'})
