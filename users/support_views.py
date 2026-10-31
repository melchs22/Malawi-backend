from rest_framework import generics, viewsets, filters, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from rest_framework.pagination import PageNumberPagination
from .admin_views import IsAdminRole
try:
    from django_filters.rest_framework import DjangoFilterBackend
except ImportError:
    from django_filters import DjangoFilterBackend
from django.utils import timezone
from decimal import Decimal

from .models import (
    SupportTicket, AdminAuditLog, NotificationHistory, 
    ReferralSummary, Referral, User
)
from .support_serializers import (
    SupportTicketSerializer, AdminAuditLogSerializer, AdminAuditLogCreateSerializer, NotificationHistorySerializer,
    ReferralSummarySerializer, ReferralDetailSerializer, ReferralCreateSerializer
)


class SupportTicketViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing support/inquiry tickets
    - Users can create and view their own tickets
    - Admins can manage all tickets
    """
    serializer_class = SupportTicketSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['status', 'user_type', 'created_at']
    search_fields = ['support_id', 'user__username', 'message']
    ordering_fields = ['created_at', 'status']
    ordering = ['-created_at']
    
    def get_queryset(self):
        user = self.request.user
        if user.is_staff or user.role == 'ADMIN':
            return SupportTicket.objects.all()
        return SupportTicket.objects.filter(user=user)
    
    def perform_create(self, serializer):
        user = self.request.user
        # Determine user type based on role
        user_type = 'RODIE' if user.role == 'RODIE' else 'RIDER'
        serializer.save(user=user, user_type=user_type)
    
    @action(detail=True, methods=['post'], permission_classes=[IsAdminUser])
    def resolve(self, request, pk=None):
        """Mark a ticket as resolved"""
        ticket = self.get_object()
        ticket.status = 'RESOLVED'
        ticket.resolved_at = timezone.now()
        ticket.save()
        return Response({'detail': 'Ticket resolved'})
    
    @action(detail=True, methods=['post'], permission_classes=[IsAdminUser])
    def update_status(self, request, pk=None):
        """Update ticket status"""
        ticket = self.get_object()
        new_status = request.data.get('status')
        if new_status not in ['PENDING', 'ONGOING', 'RESOLVED']:
            return Response(
                {'detail': 'Invalid status'},
                status=status.HTTP_400_BAD_REQUEST
            )
        ticket.status = new_status
        if new_status == 'RESOLVED':
            ticket.resolved_at = timezone.now()
        ticket.save()
        return Response(SupportTicketSerializer(ticket).data)
    
    @action(detail=True, methods=['post'], permission_classes=[IsAdminUser])
    def add_comment(self, request, pk=None):
        """Add internal comment to ticket"""
        ticket = self.get_object()
        comment = request.data.get('comment', '').strip()
        if not comment:
            return Response(
                {'detail': 'Comment cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        if ticket.internal_comments:
            ticket.internal_comments += f"\n\n[{timezone.now().strftime('%Y-%m-%d %H:%M')}] {request.user.username}:\n{comment}"
        else:
            ticket.internal_comments = f"[{timezone.now().strftime('%Y-%m-%d %H:%M')}] {request.user.username}:\n{comment}"
        ticket.save()
        return Response(SupportTicketSerializer(ticket).data)


class AuditLogPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 100


class AdminAuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet for viewing audit logs (read-only for accountability)
    Only admins can access this
    """
    serializer_class = AdminAuditLogSerializer
    pagination_class = AuditLogPagination
    permission_classes = [permissions.IsAuthenticated, IsAdminRole]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['action_type', 'admin_user', 'created_at']
    search_fields = ['admin_user__username', 'action_description', 'target_user__username']
    ordering_fields = ['created_at']
    ordering = ['-created_at']

    def get_queryset(self):
        return AdminAuditLog.objects.all().select_related('admin_user', 'target_user')

    def create(self, request, *args, **kwargs):
        serializer = AdminAuditLogCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        log = serializer.save(
            admin_user=request.user,
            ip_address=request.META.get('REMOTE_ADDR'),
        )
        return Response(
            AdminAuditLogSerializer(log).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=['post'], url_path='clear')
    def clear(self, request):
        qs = self.get_queryset()
        count = qs.count()
        qs.delete()
        return Response({'detail': f'Deleted {count} audit log(s).'})


class NotificationHistoryViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet for viewing notification history
    Users can view their own history, admins can view all
    """
    serializer_class = NotificationHistorySerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['delivery_status', 'was_opened']
    ordering_fields = ['sent_at']
    ordering = ['-sent_at']
    
    def get_queryset(self):
        user = self.request.user
        if user.is_staff or user.role == 'ADMIN':
            return NotificationHistory.objects.all()
        return NotificationHistory.objects.filter(recipient=user)
    
    @action(detail=True, methods=['post'])
    def mark_opened(self, request, pk=None):
        """Mark notification as opened"""
        notification = self.get_object()
        notification.was_opened = True
        notification.opened_at = timezone.now()
        notification.save()
        return Response({'detail': 'Notification marked as opened'})


class ReferralViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing referrals
    - Users can view their referral stats
    - Admins can manage all referrals
    """
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['is_credited', 'created_at']
    search_fields = ['referrer__username', 'referred__username']
    ordering_fields = ['created_at', 'amount']
    ordering = ['-created_at']
    permission_classes = [IsAuthenticated]
    
    def get_serializer_class(self):
        if self.action == 'create':
            return ReferralCreateSerializer
        return ReferralDetailSerializer
    
    def get_queryset(self):
        user = self.request.user
        if user.is_staff or user.role == 'ADMIN':
            return Referral.objects.all()
        # Users can only see referrals they made
        return Referral.objects.filter(referrer=user)
    
    def perform_create(self, serializer):
        # Only admins can create referrals via API
        if not (self.request.user.is_staff or self.request.user.role == 'ADMIN'):
            raise PermissionError("Only admins can create referrals")
        serializer.save()
    
    @action(detail=False, methods=['get'])
    def my_summary(self, request):
        """Get referral summary for current user"""
        user = request.user
        summary, created = ReferralSummary.objects.get_or_create(user=user)
        serializer = ReferralSummarySerializer(summary)
        return Response(serializer.data)
    
    @action(detail=False, methods=['post'], permission_classes=[IsAdminUser])
    def update_summaries(self, request):
        """
        Admin action to recalculate all referral summaries
        (useful for maintenance)
        """
        from django.db.models import Count, Q, Sum
        
        users_with_referrals = User.objects.filter(
            referrals_made__isnull=False
        ).distinct()
        
        for user in users_with_referrals:
            summary, _ = ReferralSummary.objects.get_or_create(user=user)
            total = user.referrals_made.count()
            successful = user.referrals_made.filter(is_credited=True).count()
            pending = total - successful
            total_paid = user.referrals_made.filter(is_credited=True).aggregate(
                Sum('amount')
            )['amount__sum'] or Decimal('0')
            pending_rewards = user.referrals_made.filter(is_credited=False).aggregate(
                Sum('amount')
            )['amount__sum'] or Decimal('0')
            
            summary.total_referrals = total
            summary.successful_referrals = successful
            summary.pending_referrals = pending
            summary.total_rewards_paid = total_paid
            summary.pending_rewards = pending_rewards
            summary.save()
        
        return Response({'detail': 'Referral summaries updated'})


class ReferralSummaryViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet for viewing referral summaries
    Users can view their own, admins can view all
    """
    serializer_class = ReferralSummarySerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    ordering_fields = ['total_referrals', 'total_rewards_paid']
    ordering = ['-total_referrals']
    
    def get_queryset(self):
        user = self.request.user
        if user.is_staff or user.role == 'ADMIN':
            return ReferralSummary.objects.all()
        return ReferralSummary.objects.filter(user=user)
