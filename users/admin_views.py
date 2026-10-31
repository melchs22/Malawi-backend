from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, filters
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.decorators import api_view, permission_classes
from django.db.models import Count, Q, Avg, Sum
from django.utils import timezone
from decimal import Decimal
from .admin_serializers import AdminUserSerializer
from .admin_serializers import AdminCreateSerializer
from .admin_serializers import AdminPaymentSerializer, AdminWithdrawalApprovalSerializer
from django.apps import apps
ServiceRequest = apps.get_model('service_requests', 'ServiceRequest')
from rest_framework import generics, permissions
from .serializers import WalletSerializer, ReferralSerializer, PlatformConfigSerializer, NotificationSerializer
from .models import Wallet, WalletTransaction, Referral, PlatformConfig, Notification, Payment
try:
    from asgiref.sync import async_to_sync
    from channels.layers import get_channel_layer
except Exception:
    async_to_sync = None
    get_channel_layer = None

from .fcm import send_push_notification, broadcast_role_push
User = get_user_model()


class IsAdminRole(permissions.BasePermission):
    def has_permission(self, request, view):
        user = getattr(request, 'user', None)
        return bool(user and getattr(user, 'is_authenticated', False) and getattr(user, 'role', None) == 'ADMIN' and getattr(user, 'is_active', True))


class AdminRegisterView(generics.CreateAPIView):
    serializer_class = AdminCreateSerializer
    permission_classes = [permissions.AllowAny]


class RiderListCreateView(generics.ListCreateAPIView):
    permission_classes = [permissions.AllowAny]
    serializer_class = AdminUserSerializer
    filter_backends = [filters.SearchFilter]
    search_fields = ['first_name', 'last_name', 'email', 'phone', 'username']

    def get_queryset(self):
        return User.objects.filter(role='RIDER', is_deleted=False)

    def perform_create(self, serializer):
        serializer.save(role='RIDER')


class RiderRetrieveUpdateDestroyView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminUserSerializer

    def get_queryset(self):
        return User.objects.filter(role='RIDER', is_deleted=False)
    
    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.is_deleted = True
        instance.is_active = False
        instance.save()
        try:
            if get_channel_layer and async_to_sync:
                channel_layer = get_channel_layer()
                group = f'user_{instance.id}'
                async_to_sync(channel_layer.group_send)(group, {'type': 'user.status', 'is_deleted': True, 'user_id': instance.id})
        except Exception:
            pass
        return Response({'detail': 'Rider deleted successfully.'}, status=200)
    
    def get(self, request, *args, **kwargs):
        """Override GET to include summary statistics"""
        instance = self.get_object()
        serializer = self.get_serializer(instance)
        rider_requests = ServiceRequest.objects.filter(rider=instance)
        total_requests = rider_requests.count()
        
        status_breakdown = rider_requests.values('status').annotate(
            count=Count('status')
        ).order_by('status')
        
        status_dict = {item['status']: item['count'] for item in status_breakdown}
        completed_requests = rider_requests.filter(status='COMPLETED').count()
        active_statuses = ['REQUESTED', 'ACCEPTED', 'EN_ROUTE', 'STARTED']
        active_requests = rider_requests.filter(status__in=active_statuses).count()
        service_breakdown = rider_requests.values(
            'service_type__name', 'service_type__code'
        ).annotate(
            count=Count('id')
        ).order_by('-count')[:5]  
        
        recent_requests = rider_requests.order_by('-created_at')[:5].values(
            'id', 'service_type__name', 'status', 'created_at', 'rodie__username'
        )
        
        completion_rate = (completed_requests / total_requests * 100) if total_requests > 0 else 0

        avg_rating = 5.0
        reviews = []
        try:
            from service_requests.models_rating import Rating
            from service_requests.serializers import RatingSerializer
            avg_rating = Rating.objects.filter(rated_user=instance).aggregate(
                avg_rating=Avg('rating')
            )['avg_rating'] or 0
            avg_rating = round(float(avg_rating), 1) if avg_rating else 5.0
            ratings_qs = Rating.objects.filter(rated_user=instance).select_related(
                'rater', 'rated_user', 'service_request'
            ).order_by('-created_at')[:20]
            reviews = RatingSerializer(ratings_qs, many=True).data
        except Exception:
            pass
        
        summary_data = {
            'stats': {
                'total_requests': total_requests,
                'completed_requests': completed_requests,
                'active_requests': active_requests,
                'cancelled_requests': status_dict.get('CANCELLED', 0),
                'completion_rate': round(completion_rate, 1),
                'status_breakdown': status_dict,
            },
            'service_breakdown': list(service_breakdown),
            'recent_requests': list(recent_requests),
            'created_date': instance.created_at,
            'last_active': rider_requests.order_by('-updated_at').first().updated_at if rider_requests.exists() else instance.updated_at,
            'rating': avg_rating,
            'reviews': reviews,
        }
        
        response_data = serializer.data
        response_data['summary'] = summary_data
        try:
            wallet, _ = Wallet.objects.get_or_create(user=instance)
            response_data['wallet'] = WalletSerializer(wallet).data
        except Exception:
            response_data['wallet'] = None

        try:
            from services.models import RodieService
            services_qs = RodieService.objects.filter(rodie=instance).select_related('service')
            response_data['services'] = [{'service_id': s.service.id, 'service_name': s.service.name} for s in services_qs]
        except Exception:
            response_data['services'] = []
        
        return Response(response_data)


class RoadieListCreateView(generics.ListCreateAPIView):
    permission_classes = [permissions.AllowAny]
    serializer_class = AdminUserSerializer
    filter_backends = [filters.SearchFilter]
    search_fields = ['first_name', 'last_name', 'email', 'phone', 'username']

    def get_queryset(self):
        return User.objects.filter(role='RODIE', is_deleted=False)

    def perform_create(self, serializer):
        serializer.save(role='RODIE')


class RoadieRetrieveUpdateDestroyView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminUserSerializer

    def get_queryset(self):
        return User.objects.filter(role='RODIE', is_deleted=False)
    
    def update(self, request, *args, **kwargs):
        """Override update to send WebSocket notification when approval status changes"""
        instance = self.get_object()
        old_approved = instance.is_approved
        print(f"DEBUG: Before update - user {instance.id}, is_approved = {old_approved}")
        
        # Perform the update
        response = super().update(request, *args, **kwargs)
        
        # Refresh instance from database to get latest state
        instance.refresh_from_db()
        new_approved = instance.is_approved
        print(f"DEBUG: After update - user {instance.id}, is_approved = {new_approved}")
        print(f"DEBUG: Approval status changed: {old_approved != new_approved}")
        
        if old_approved != new_approved:
            try:
                if get_channel_layer and async_to_sync:
                    channel_layer = get_channel_layer()
                    # Roadie consumers join group "rodie_{user_id}"
                    group = f'rodie_{instance.id}'
                    
                    if new_approved:
                        # Send approval notification
                        title = "Account Approved"
                        body = "Your Vehix account has been approved! You can now go online."
                        message = {
                            'type': 'account.approved',
                            'user_id': instance.id,
                            'is_approved': True,
                            'message': body
                        }
                        print(f" Sent approval WebSocket to roadie {instance.id}")
                    else:
                        # Send unapproval notification
                        title = "Account Unapproved"
                        body = "Your Vehix account has been unapproved. Please contact support."
                        message = {
                            'type': 'account.unapproved',
                            'user_id': instance.id,
                            'is_approved': False,
                            'message': body
                        }
                        print(f" Sent unapproval WebSocket to roadie {instance.id}")
                    
                    # Create persistent notification in database
                    notif = Notification.objects.create(
                        recipient=instance,
                        title=title,
                        message=body,
                        notification_type='SERVICE'
                    )
                    
                    # Send real-time Push Alert
                    send_push_notification(instance, title, body, {
                        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                        'type': 'account_status',
                        'is_approved': str(new_approved)
                    })
                    
                    async_to_sync(channel_layer.group_send)(group, message)
            except Exception as e:
                print(f" Failed to send approval notification: {e}")
        
        return response
    
    def get(self, request, *args, **kwargs):
        """Override GET to include summary statistics"""
        instance = self.get_object()
        serializer = self.get_serializer(instance)
        roadie_requests = ServiceRequest.objects.filter(rodie=instance)
        total_assigned = roadie_requests.count()
        
        status_breakdown = roadie_requests.values('status').annotate(
            count=Count('status')
        ).order_by('status')
    
        status_dict = {item['status']: item['count'] for item in status_breakdown}
        completed_requests = roadie_requests.filter(status='COMPLETED').count()
        
        active_statuses = ['REQUESTED', 'ACCEPTED', 'EN_ROUTE', 'STARTED']
        active_requests = roadie_requests.filter(status__in=active_statuses).count()
        
        service_breakdown = roadie_requests.values(
            'service_type__name', 'service_type__code'
        ).annotate(
            count=Count('id')
        ).order_by('-count')[:5]  
        
        recent_assignments = roadie_requests.order_by('-created_at')[:5].values(
            'id', 'service_type__name', 'status', 'created_at', 'rider__username',
            'rider_lat', 'rider_lng'
        )
        
        completion_rate = (completed_requests / total_assigned * 100) if total_assigned > 0 else 0
        
        unique_riders_served = roadie_requests.values('rider').distinct().count()
        
        avg_rating = 5.0
        reviews = []
        try:
            from service_requests.models_rating import Rating
            from service_requests.serializers import RatingSerializer
            avg_rating = Rating.objects.filter(rated_user=instance).aggregate(
                avg_rating=Avg('rating')
            )['avg_rating'] or 0
            avg_rating = round(float(avg_rating), 1) if avg_rating else 5.0
            ratings_qs = Rating.objects.filter(rated_user=instance).select_related(
                'rater', 'rated_user', 'service_request'
            ).order_by('-created_at')[:20]
            reviews = RatingSerializer(ratings_qs, many=True).data
        except Exception:
            pass
        
        summary_data = {
            'stats': {
                'total_assignments': total_assigned,
                'completed_assignments': completed_requests,
                'active_assignments': active_requests,
                'cancelled_assignments': status_dict.get('CANCELLED', 0),
                'completion_rate': round(completion_rate, 1),
                'unique_riders_served': unique_riders_served,
                'status_breakdown': status_dict,
            },
            'service_breakdown': list(service_breakdown),
            'recent_assignments': list(recent_assignments),
            'created_date': instance.created_at,
            'last_active': roadie_requests.order_by('-updated_at').first().updated_at if roadie_requests.exists() else instance.updated_at,
            'is_approved': instance.is_approved,
            'rating': avg_rating,
            'reviews': reviews,
        }
        
        response_data = serializer.data
        response_data['summary'] = summary_data
        try:
            wallet, _ = Wallet.objects.get_or_create(user=instance)
            response_data['wallet'] = WalletSerializer(wallet).data
        except Exception:
            response_data['wallet'] = None
        
        return Response(response_data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.is_deleted = True
        instance.is_active = False
        instance.save()
        try:
            if get_channel_layer and async_to_sync:
                channel_layer = get_channel_layer()
                group = f'user_{instance.id}'
                async_to_sync(channel_layer.group_send)(group, {'type': 'user.status', 'is_deleted': True, 'user_id': instance.id})
        except Exception:
            pass
        return Response(status=204)


class RealtimeRidersView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        q = request.query_params.get('q', None)
        qs = User.objects.filter(role='RIDER', is_active=True, is_deleted=False)
        if q:
            qs = qs.filter(Q(username__icontains=q) | Q(first_name__icontains=q) | Q(last_name__icontains=q))
        serializer = AdminUserSerializer(qs, many=True)
        return Response(serializer.data)


class AdminListCreateView(generics.ListCreateAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminCreateSerializer
    filter_backends = [filters.SearchFilter]
    search_fields = ['first_name', 'last_name', 'email', 'phone', 'username']

    def get_queryset(self):
        return User.objects.filter(role='ADMIN', is_deleted=False)

    def perform_create(self, serializer):
        serializer.save(role='ADMIN', is_staff=True, is_superuser=True, is_approved=True)


class AdminRetrieveUpdateDestroyView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.AllowAny]
    serializer_class = AdminUserSerializer

    def get_queryset(self):
        return User.objects.filter(role='ADMIN', is_deleted=False)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.is_deleted = True
        instance.is_active = False
        instance.save()
        try:
            if get_channel_layer and async_to_sync:
                channel_layer = get_channel_layer()
                group = f'user_{instance.id}'
                async_to_sync(channel_layer.group_send)(group, {'type': 'user.status', 'is_deleted': True, 'user_id': instance.id})
        except Exception:
            pass
        return Response(status=204)

class RiderSummaryView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    
    def get(self, request, pk):
        try:
            rider = User.objects.get(id=pk, role='RIDER')
            rider_requests = ServiceRequest.objects.filter(rider=rider)
            
            total_requests = rider_requests.count()
            status_breakdown = rider_requests.values('status').annotate(count=Count('status'))
            
            summary = {
                'rider_id': rider.id,
                'rider_name': f"{rider.first_name} {rider.last_name}",
                'total_requests': total_requests,
                'status_breakdown': {item['status']: item['count'] for item in status_breakdown},
                'completed_requests': rider_requests.filter(status='COMPLETED').count(),
                'active_requests': rider_requests.filter(status__in=['REQUESTED', 'ACCEPTED', 'EN_ROUTE', 'STARTED']).count(),
                'created_at': rider.created_at,
                'last_active': rider_requests.order_by('-updated_at').first().updated_at if rider_requests.exists() else None,
            }
            return Response(summary)
        except User.DoesNotExist:
            return Response({'error': 'Rider not found'}, status=404)


class RoadieSummaryView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    
    def get(self, request, pk):
        try:
            roadie = User.objects.get(id=pk, role='RODIE')
            roadie_requests = ServiceRequest.objects.filter(rodie=roadie)
            
            total_assignments = roadie_requests.count()
            status_breakdown = roadie_requests.values('status').annotate(count=Count('status'))
            
            summary = {
                'roadie_id': roadie.id,
                'roadie_name': f"{roadie.first_name} {roadie.last_name}",
                'total_assignments': total_assignments,
                'status_breakdown': {item['status']: item['count'] for item in status_breakdown},
                'completed_assignments': roadie_requests.filter(status='COMPLETED').count(),
                'active_assignments': roadie_requests.filter(status__in=['REQUESTED', 'ACCEPTED', 'EN_ROUTE', 'STARTED']).count(),
                'unique_riders_served': roadie_requests.values('rider').distinct().count(),
                'is_approved': roadie.is_approved,
                'created_at': roadie.created_at,
                'last_active': roadie_requests.order_by('-updated_at').first().updated_at if roadie_requests.exists() else None,
            }
            return Response(summary)
        except User.DoesNotExist:
            return Response({'error': 'Roadie not found'}, status=404)


class AdminDeletedUsersView(generics.ListAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminUserSerializer

    def get_queryset(self):
        return User.objects.filter(is_deleted=True)


class AdminPendingDeletionListView(generics.ListAPIView):
    """View to list users who have requested account deletion (deletion_status='PENDING')."""
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminUserSerializer
    filter_backends = [filters.SearchFilter]
    search_fields = ['first_name', 'last_name', 'email', 'phone', 'username']

    def get_queryset(self):
        return User.objects.filter(deletion_status='PENDING').order_by('-deletion_requested_at')


class AdminRestoreUserView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]

    def post(self, request, pk):
        try:
            user = User.objects.get(pk=pk, is_deleted=True)
            user.is_deleted = False
            user.is_active = True
            user.save()
            if get_channel_layer and async_to_sync:
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(f'user_{user.id}', {'type': 'user.status', 'is_deleted': False, 'user_id': user.id})
            return Response({'status': 'User restored successfully'})
        except User.DoesNotExist:
            return Response({'error': 'User not found or not deleted'}, status=404)

class AdminWalletListCreateView(generics.ListCreateAPIView):
    permission_classes = [permissions.AllowAny]
    serializer_class = WalletSerializer

    def get_queryset(self):
        return Wallet.objects.all()


class AdminWalletRUDView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.AllowAny]
    serializer_class = WalletSerializer

    def get_queryset(self):
        return Wallet.objects.all()


class AdminReferralListCreateView(generics.ListCreateAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = ReferralSerializer

    def get_queryset(self):
        return Referral.objects.all()


class AdminReferralRUDView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = ReferralSerializer

    def get_queryset(self):
        return Referral.objects.all()


class AdminPlatformConfigView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        cfg = PlatformConfig.objects.first()
        if not cfg:
            cfg = PlatformConfig.objects.create()
        serializer = PlatformConfigSerializer(cfg)
        return Response(serializer.data)

    def post(self, request):
        cfg = PlatformConfig.objects.first()
        if not cfg:
            cfg = PlatformConfig.objects.create()
        serializer = PlatformConfigSerializer(cfg, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class IsSuperAdminRole(permissions.BasePermission):
    def has_permission(self, request, view):
        user = getattr(request, 'user', None)
        return bool(
            user and getattr(user, 'is_authenticated', False) and
            getattr(user, 'role', None) == 'ADMIN' and
            getattr(user, 'is_active', True) and
            getattr(user, 'is_superuser', False)
        )


class AdminNotificationListCreateView(generics.ListCreateAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.all().order_by('-created_at')
    
    def perform_create(self, serializer):
        notif = serializer.save()
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer
            channel_layer = get_channel_layer()

            payload = {
                'type': 'notification',
                'notification': NotificationSerializer(notif).data
            }

            if notif.target_role == 'ALL':
                async_to_sync(channel_layer.group_send)('notifications', payload)
            elif notif.target_role in ['RIDER', 'RODIE']:
                async_to_sync(channel_layer.group_send)(f'role_{notif.target_role}', payload)
            elif notif.recipient_id:
                async_to_sync(channel_layer.group_send)(f'user_{notif.recipient_id}', payload)
        except Exception as e:
            print(f"DEBUG Error in Broadcast: {str(e)}")


class AdminDeletedRidersView(generics.ListAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminUserSerializer

    def get_queryset(self):
        return User.objects.filter(role='RIDER', is_deleted=True).order_by('-updated_at')


class AdminDeletedRoadiesView(generics.ListAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminUserSerializer

    def get_queryset(self):
        return User.objects.filter(role='RODIE', is_deleted=True).order_by('-updated_at')


class AdminPermanentDeleteUserView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsSuperAdminRole]

    def delete(self, request, pk, role):
        normalized_role = 'RODIE' if role in ('ROADIE', 'RODIE') else role
        try:
            user = User.objects.get(
                Q(is_deleted=True) | Q(deletion_status='PENDING'),
                pk=pk,
                role=normalized_role,
            )
            user.delete()
            return Response({'detail': 'User permanently deleted.'})
        except User.DoesNotExist:
            return Response({'detail': 'Deleted user not found.'}, status=404)


class AdminNotificationRUDView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.all()


class AdminUserPasswordView(APIView):
    """Admin endpoint to change/reset passwords for Riders, Roadies and Admins."""
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]

    def post(self, request, pk):
        try:
            user = User.objects.get(id=pk)
            if user.role not in ('RIDER', 'RODIE', 'ADMIN'):
                return Response({'error': 'Password change only allowed for Riders, Roadies and Admins'}, status=403)
            
            new_password = request.data.get('password')
            if not new_password:
                return Response({'error': 'New password is required'}, status=400)
            
            user.set_password(new_password)
            user.save()
            return Response({'status': 'Password updated successfully'})
        except User.DoesNotExist:
            return Response({'error': 'User not found'}, status=404)


def _format_duration(seconds):
    seconds = int(max(0, seconds))
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m"
    return f"{secs}s"


def _session_duration(log, now=None):
    from django.utils import timezone
    now = now or timezone.now()
    end = log.went_offline_at or now
    return max(0, (end - log.went_online_at).total_seconds())


class RoadieOnlineTimeFleetView(APIView):
    """Aggregate online time across all roadies for admin dashboard."""
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]

    def get(self, request):
        from django.utils import timezone
        from .models import RodieAvailabilityLog

        now = timezone.now()
        days = int(request.query_params.get('days', 30))
        since = now - timezone.timedelta(days=days)

        logs = RodieAvailabilityLog.objects.filter(
            user__role='RODIE',
            went_online_at__gte=since,
        ).select_related('user')

        total_seconds = sum(_session_duration(log, now) for log in logs)
        roadie_ids = logs.values_list('user_id', flat=True).distinct()
        roadie_count = len(set(roadie_ids))
        avg_per_roadie = total_seconds / roadie_count if roadie_count else 0

        return Response({
            'days': days,
            'total_online_seconds': int(total_seconds),
            'total_online_formatted': _format_duration(total_seconds),
            'average_per_roadie_seconds': int(avg_per_roadie),
            'average_per_roadie_formatted': _format_duration(avg_per_roadie),
            'roadies_with_sessions': roadie_count,
            'session_count': logs.count(),
        })


class RoadieOnlineTimeDetailView(APIView):
    """Per-roadie online sessions, averages, and calendar grouping."""
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]

    def get(self, request, pk):
        from django.utils import timezone
        from collections import defaultdict
        from .models import RodieAvailabilityLog

        try:
            roadie = User.objects.get(pk=pk, role='RODIE')
        except User.DoesNotExist:
            return Response({'detail': 'Roadie not found.'}, status=404)

        now = timezone.now()
        date_from = request.query_params.get('date_from')
        date_to = request.query_params.get('date_to')

        logs_qs = RodieAvailabilityLog.objects.filter(user=roadie).order_by('-went_online_at')
        if date_from:
            logs_qs = logs_qs.filter(went_online_at__date__gte=date_from)
        if date_to:
            logs_qs = logs_qs.filter(went_online_at__date__lte=date_to)

        sessions = []
        calendar = defaultdict(lambda: {'total_seconds': 0, 'sessions': []})

        for log in logs_qs:
            duration = _session_duration(log, now)
            session = {
                'id': log.id,
                'went_online_at': log.went_online_at.isoformat(),
                'went_offline_at': log.went_offline_at.isoformat() if log.went_offline_at else None,
                'duration_seconds': int(duration),
                'duration_formatted': _format_duration(duration),
                'still_online': log.went_offline_at is None,
                'device_type': log.device_type,
            }
            sessions.append(session)
            day_key = log.went_online_at.date().isoformat()
            calendar[day_key]['total_seconds'] += int(duration)
            calendar[day_key]['sessions'].append(session)

        total_seconds = sum(s['duration_seconds'] for s in sessions)
        session_count = len(sessions)
        avg_session = total_seconds / session_count if session_count else 0

        calendar_out = {
            day: {
                'date': day,
                'total_seconds': data['total_seconds'],
                'total_formatted': _format_duration(data['total_seconds']),
                'sessions': data['sessions'],
            }
            for day, data in sorted(calendar.items(), reverse=True)
        }

        return Response({
            'roadie_id': roadie.id,
            'roadie_external_id': roadie.external_id,
            'roadie_name': f"{roadie.first_name} {roadie.last_name}".strip() or roadie.username,
            'total_online_seconds': total_seconds,
            'total_online_formatted': _format_duration(total_seconds),
            'average_session_seconds': int(avg_session),
            'average_session_formatted': _format_duration(avg_session),
            'session_count': session_count,
            'sessions': sessions,
            'calendar': calendar_out,
        })


class AdminWithdrawalListView(generics.ListAPIView):
    """
    Admin endpoint to list all withdrawal requests.
    Supports filtering by status and transaction type.
    """
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    serializer_class = AdminPaymentSerializer
    filter_backends = [filters.SearchFilter]
    search_fields = ['user__username', 'user__email', 'user__phone', 'reference']

    def get_serializer_context(self):
        """Ensure request is passed to serializer context for image URL generation"""
        context = super().get_serializer_context()
        context['request'] = self.request
        return context

    def get_queryset(self):
        queryset = Payment.objects.filter(transaction_type='WITHDRAWAL').select_related('user').order_by('-created_at')

        # Filter by status if provided
        status = self.request.query_params.get('status', None)
        if status:
            queryset = queryset.filter(status=status)

        return queryset


class AdminWithdrawalDetailView(APIView):
    """
    Admin endpoint to view, approve, or reject a specific withdrawal request.
    GET: Retrieve withdrawal request details
    PATCH: Approve (COMPLETED) or reject (FAILED/CANCELLED) the withdrawal
    """
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]

    def get(self, request, pk):
        """Get details of a specific withdrawal request."""
        try:
            payment = Payment.objects.select_related('user', 'user__wallet').get(
                pk=pk,
                transaction_type='WITHDRAWAL'
            )
        except Payment.DoesNotExist:
            return Response({'error': 'Withdrawal request not found.'}, status=404)

        serializer = AdminPaymentSerializer(payment, context={'request': request})

        # Add wallet balance info
        response_data = serializer.data
        try:
            wallet = Wallet.objects.get(user=payment.user)
            response_data['user_wallet_balance'] = str(wallet.balance)
        except Wallet.DoesNotExist:
            response_data['user_wallet_balance'] = '0.00'

        return Response(response_data)

    def patch(self, request, pk):
        """Approve or reject a withdrawal request."""
        from django.db import transaction

        serializer = AdminWithdrawalApprovalSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({
                'error': 'Invalid data.',
                'details': serializer.errors
            }, status=400)

        new_status = serializer.validated_data['status']
        rejection_reason = serializer.validated_data.get('rejection_reason', '')

        with transaction.atomic():
            try:
                payment = Payment.objects.select_for_update().get(
                    pk=pk,
                    transaction_type='WITHDRAWAL',
                    status='PENDING'
                )
            except Payment.DoesNotExist:
                return Response({
                    'error': 'Withdrawal request not found or already processed.'
                }, status=404)
            if new_status == 'COMPLETED':
                # Approve the withdrawal - already deducted from wallet in WithdrawView
                payment.status = 'COMPLETED'
                payment.description = f"{payment.description} | Approved by admin"
                payment.save()
                
                # Log the admin action
                try:
                    AdminAuditLog = apps.get_model('users', 'AdminAuditLog')
                    AdminAuditLog.objects.create(
                        admin_user=request.user,
                        action_type='PAYMENT_PROCESS',
                        action_description=f'Approved withdrawal request {payment.reference}',
                        target_user=payment.user,
                        target_entity_type='Payment',
                        target_entity_id=str(payment.id),
                        changes={
                            'old': {'status': 'PENDING'},
                            'new': {
                                'status': 'COMPLETED',
                                'amount': str(payment.amount),
                                'reference': payment.reference,
                            },
                        }
                    )
                except Exception:
                    pass
                
                # Send notification to user
                try:
                    Notification.objects.create(
                        recipient=payment.user,
                        title='Withdrawal Approved',
                        message=f'Your withdrawal request of {payment.amount} has been approved and processed.',
                        notification_type='SERVICE'
                    )
                    
                    # Send push notification
                    send_push_notification(
                        payment.user,
                        'Withdrawal Approved',
                        f'Your withdrawal of {payment.amount} has been processed successfully.',
                        {'type': 'withdrawal_approved', 'reference': payment.reference}
                    )
                except Exception:
                    pass
                
                return Response({
                    'success': True,
                    'message': 'Withdrawal request approved successfully.',
                    'payment': AdminPaymentSerializer(payment).data
                })
            
            else:
                # Reject the withdrawal - refund to wallet
                wallet, created = Wallet.objects.get_or_create(user=payment.user)
                
                # Refund the amount back to wallet
                wallet.balance += payment.amount
                wallet.save()
                
                # Create wallet transaction for the refund
                WalletTransaction.objects.create(
                    wallet=wallet,
                    amount=payment.amount,
                    reason=f"Withdrawal {payment.reference} rejected - refunded"
                )
                
                # Update payment status
                payment.status = new_status
                if rejection_reason:
                    payment.description = f"{payment.description} | Rejected: {rejection_reason}"
                else:
                    payment.description = f"{payment.description} | Rejected by admin"
                payment.save()
                
                # Log the admin action
                try:
                    AdminAuditLog = apps.get_model('users', 'AdminAuditLog')
                    AdminAuditLog.objects.create(
                        admin_user=request.user,
                        action_type='PAYMENT_PROCESS',
                        action_description=f'Rejected withdrawal request {payment.reference}',
                        target_user=payment.user,
                        target_entity_type='Payment',
                        target_entity_id=str(payment.id),
                        changes={
                            'old': {'status': 'PENDING'},
                            'new': {
                                'status': new_status,
                                'amount': str(payment.amount),
                                'reference': payment.reference,
                                'rejection_reason': rejection_reason,
                                'refunded': True,
                            },
                        }
                    )
                except Exception:
                    pass
                
                # Send notification to user
                try:
                    Notification.objects.create(
                        recipient=payment.user,
                        title='Withdrawal Rejected',
                        message=f'Your withdrawal request of {payment.amount} has been rejected. The amount has been refunded to your wallet.',
                        notification_type='SERVICE'
                    )
                    
                    # Send push notification
                    send_push_notification(
                        payment.user,
                        'Withdrawal Rejected',
                        f'Your withdrawal of {payment.amount} has been rejected. Amount refunded to wallet.',
                        {'type': 'withdrawal_rejected', 'reference': payment.reference}
                    )
                except Exception:
                    pass
                
                return Response({
                    'success': True,
                    'message': f'Withdrawal request {new_status.lower()} successfully. Amount refunded to user wallet.',
                    'payment': AdminPaymentSerializer(payment).data
                })
