from rest_framework import serializers
from .models import SupportTicket, AdminAuditLog, NotificationHistory, ReferralSummary, Referral, User


class SupportTicketSerializer(serializers.ModelSerializer):
    """Serializer for support tickets with user details"""
    user_email = serializers.CharField(source='user.email', read_only=True)
    user_phone = serializers.CharField(source='user.phone', read_only=True)
    user_name = serializers.SerializerMethodField()
    
    class Meta:
        model = SupportTicket
        fields = (
            'id', 'support_id', 'user', 'user_name', 'user_email', 'user_phone',
            'user_type', 'subject', 'message', 'status', 'internal_comments',
            'created_at', 'updated_at', 'resolved_at'
        )
        read_only_fields = ('support_id', 'created_at', 'updated_at')
    
    def get_user_name(self, obj):
        return f"{obj.user.first_name} {obj.user.last_name}".strip() or obj.user.username


class AdminAuditLogSerializer(serializers.ModelSerializer):
    """Serializer for admin audit logs"""
    admin_username = serializers.SerializerMethodField()
    target_username = serializers.CharField(source='target_user.username', read_only=True, allow_null=True)
    
    class Meta:
        model = AdminAuditLog
        fields = (
            'id', 'admin_user', 'admin_username', 'action_type', 'action_description',
            'target_user', 'target_username', 'target_entity_type', 'target_entity_id',
            'changes', 'created_at', 'ip_address'
        )
        read_only_fields = ('created_at',)

    def get_admin_username(self, obj):
        return obj.admin_user.username if obj.admin_user else "System"


class AdminAuditLogCreateSerializer(serializers.ModelSerializer):
    """Validate audit records submitted by authenticated admin dashboard actions."""

    action_type = serializers.CharField(max_length=50)

    class Meta:
        model = AdminAuditLog
        fields = (
            'action_type', 'action_description', 'target_entity_type',
            'target_entity_id', 'changes'
        )
        extra_kwargs = {
            'target_entity_type': {'required': False},
            'target_entity_id': {'required': False},
            'changes': {'required': False},
        }

    def validate_changes(self, value):
        if not isinstance(value, dict):
            raise serializers.ValidationError("Changes must be an object.")
        return value


class NotificationHistorySerializer(serializers.ModelSerializer):
    """Serializer for notification history"""
    recipient_username = serializers.CharField(source='recipient.username', read_only=True, allow_null=True)
    notification_title = serializers.CharField(source='notification.title', read_only=True)
    notification_message = serializers.CharField(source='notification.message', read_only=True)
    
    class Meta:
        model = NotificationHistory
        fields = (
            'id', 'notification', 'notification_title', 'notification_message',
            'recipient', 'recipient_username', 'delivery_status', 'delivery_error',
            'was_opened', 'opened_at', 'sent_at', 'updated_at'
        )
        read_only_fields = ('sent_at', 'updated_at')


class ReferralSummarySerializer(serializers.ModelSerializer):
    """Serializer for referral summary stats"""
    user_username = serializers.CharField(source='user.username', read_only=True)
    
    class Meta:
        model = ReferralSummary
        fields = (
            'id', 'user', 'user_username', 'total_referrals', 'successful_referrals',
            'pending_referrals', 'total_rewards_paid', 'pending_rewards', 'updated_at'
        )
        read_only_fields = ('updated_at',)


class ReferralDetailSerializer(serializers.ModelSerializer):
    """Detailed serializer for individual referrals"""
    referrer_username = serializers.CharField(source='referrer.username', read_only=True)
    referred_username = serializers.CharField(source='referred.username', read_only=True)
    referrer_id = serializers.CharField(source='referrer.external_id', read_only=True)
    referred_id = serializers.CharField(source='referred.external_id', read_only=True)
    referrer_type = serializers.CharField(source='referrer.role', read_only=True)
    referred_type = serializers.CharField(source='referred.role', read_only=True)
    
    class Meta:
        model = Referral
        fields = (
            'id', 'referrer', 'referrer_username', 'referrer_id', 'referrer_type',
            'referred', 'referred_username', 'referred_id', 'referred_type',
            'amount', 'is_credited', 'created_at'
        )
        read_only_fields = ('created_at',)


class ReferralCreateSerializer(serializers.Serializer):
    """Serializer for creating referrals"""
    referrer_id = serializers.IntegerField()
    referred_id = serializers.IntegerField()
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, default=1000)
    
    def validate(self, data):
        try:
            referrer = User.objects.get(id=data['referrer_id'])
        except User.DoesNotExist:
            raise serializers.ValidationError("Referrer not found")
        
        try:
            referred = User.objects.get(id=data['referred_id'])
        except User.DoesNotExist:
            raise serializers.ValidationError("Referred user not found")
        
        if referrer.id == referred.id:
            raise serializers.ValidationError("Cannot create self-referral")
        
        return data
    
    def create(self, validated_data):
        referrer = User.objects.get(id=validated_data['referrer_id'])
        referred = User.objects.get(id=validated_data['referred_id'])
        
        return Referral.objects.create(
            referrer=referrer,
            referred=referred,
            amount=validated_data.get('amount', 1000)
        )
