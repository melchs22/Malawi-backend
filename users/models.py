from django.contrib.auth.models import AbstractUser, UserManager as AuthUserManager
from django.db import models
from django.db import transaction
from django.core.validators import RegexValidator
from django.utils import timezone
import re
import uuid


class UserManager(AuthUserManager):
    def create_user(self, username, email=None, password=None, **extra_fields):
        # We need to ensure external_id is generated even if it's not passed,
        # because it's our USERNAME_FIELD.
        if 'external_id' not in extra_fields or not extra_fields['external_id']:
            # We'll let the Model.save() handle it for now, 
            # but we must ensure we don't pass an empty string that conflicts.
            extra_fields['external_id'] = f"PENDING-{uuid.uuid4().hex[:8]}"
        
        user = self.model(username=username, email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, username, email=None, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('role', 'ADMIN')
        return self.create_user(username, email, password, **extra_fields)

class User(AbstractUser):
    objects = UserManager()
    # Username is unique per role - same username can be used as RIDER and RODIE
    username = models.CharField(
        max_length=150,
        help_text='Required. 150 characters or fewer. Letters, digits and @/./+/-/_ only.',
    )

    # Use external_id as the unique identifier for Django's auth system 
    # to allow duplicate usernames/emails/phones across roles.
    USERNAME_FIELD = 'external_id'
    REQUIRED_FIELDS = ['username', 'email']

    ROLE_CHOICES = (
        ('RIDER', 'Rider'),
        ('RODIE', 'Rodie'),
        ('MECHANIC', 'Mechanic'),
        ('WORKSHOP', 'Workshop'),
        ('ADMIN', 'Admin'),
    )

    # Email is unique per role — same email can be used as RIDER and RODIE
    email = models.EmailField()

    role = models.CharField(
        max_length=10,
        choices=ROLE_CHOICES
    )

    # Phone is unique per role — same phone can be used as RIDER and RODIE
    phone = models.CharField(
        max_length=20
    )

    referral_code = models.CharField(
        max_length=10,
        unique=True,
        blank=True,
        null=True
    )

    nin = models.CharField(
        max_length=14,
        unique=True,
        blank=True,
        null=True,
        validators=[RegexValidator(r'^[A-Za-z0-9]{14}$', message='NIN must be exactly 14 alphanumeric characters')],
        help_text="National Identification Number (14 characters)"
    )

    is_approved = models.BooleanField(default=False)

    created_at = models.DateTimeField(default=timezone.now, editable=False)
    updated_at = models.DateTimeField(auto_now=True)

    external_id = models.CharField(
        max_length=20,
        unique=True,
        blank=True,
        null=True,
        help_text="Public ID: Riders start with R001, Roadies with BS001",
    )

    is_active = models.BooleanField(default=True)
    is_online = models.BooleanField(default=False, editable=False)
    is_deleted = models.BooleanField(default=False)
    lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, editable=False)
    lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, editable=False)

    current_login_id = models.UUIDField(null=True, blank=True, help_text="Used to enforce single device login", default=uuid.uuid4)

    services_selected = models.BooleanField(
        default=False,
        help_text="Tracks if roadie has selected services on first login"
    )

    trial_end_date = models.DateTimeField(
        null=True, 
        blank=True,
        help_text="The date when the user's free trial expires."
    )

    fcm_token = models.TextField(
        null=True, 
        blank=True, 
        help_text="Firebase Cloud Messaging token for push notifications"
    )

    DELETION_STATUS_CHOICES = (
        ('PENDING', 'Pending Deletion'),
    )

    deletion_status = models.CharField(
        max_length=20, 
        choices=DELETION_STATUS_CHOICES, 
        null=True, 
        blank=True,
        help_text="Tracks account deletion requests"
    )
    deletion_requested_at = models.DateTimeField(null=True, blank=True)
    deletion_reason = models.TextField(null=True, blank=True)

    class Meta:
        constraints = [
            # Email + role must be unique (same email can exist for RIDER and RODIE)
            models.UniqueConstraint(fields=['email', 'role'], name='unique_email_per_role'),
            # Phone + role must be unique
            models.UniqueConstraint(fields=['phone', 'role'], name='unique_phone_per_role'),
            # Username + role must be unique
            models.UniqueConstraint(fields=['username', 'role'], name='unique_username_per_role'),
        ]

    @property
    def trial_days_left(self):
        """Returns the number of days left in the free trial, or 0 if expired/not applicable."""
        if not self.trial_end_date:
            return 0
        from django.utils import timezone
        diff = self.trial_end_date - timezone.now()
        total_seconds = diff.total_seconds()
        if total_seconds <= 0:
            return 0
        # diff.days returns floor, but we want to include today. 
        # For example, if 0.5 days left, it should show 1 day.
        return int(total_seconds // 86400) + 1

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        from django.utils import timezone

        # Reset trial end date on every approval (including re-approvals).
        # Detect the unapproved → approved transition by comparing with DB state.
        if self.is_approved:
            should_set_trial = False
            if is_new:
                should_set_trial = True
            else:
                try:
                    old = User.objects.filter(pk=self.pk).values('is_approved').first()
                    was_approved = old['is_approved'] if old else False
                    if not was_approved:
                        # Transitioning from unapproved → approved: reset trial
                        should_set_trial = True
                except Exception:
                    pass

            if should_set_trial:
                try:
                    from django.apps import apps
                    ConfigModel = apps.get_model('users', 'PlatformConfig')
                    config = ConfigModel.objects.first()
                    if config and config.trial_days > 0:
                        from datetime import timedelta
                        self.trial_end_date = timezone.now() + timedelta(days=config.trial_days)
                except Exception as e:
                    import logging
                    logging.error(f"Error setting trial date: {e}")

        if not self.external_id or self.external_id.startswith('PENDING-'):
            if self.role == 'RIDER':
                prefix = 'R'
            elif self.role == 'RODIE':
                prefix = 'SP'
            elif self.role == 'MECHANIC':
                prefix = 'IT'
            elif self.role == 'WORKSHOP':
                prefix = 'WS'
            elif self.role == 'ADMIN':
                prefix = 'AD'
            else:
                prefix = None

            if prefix:
                try:
                    with transaction.atomic():
                        # Use select_for_update to lock users table during sequence generation
                        existing = User.objects.select_for_update().filter(
                            external_id__startswith=prefix,
                            external_id__regex=r'^' + re.escape(prefix) + r'\d+$'
                        ).values_list('external_id', flat=True)
                        
                        max_n = 0
                        for val in existing:
                            if not val:
                                continue
                            try:
                                n = int(val[len(prefix):])
                                if n > max_n:
                                    max_n = n
                            except (ValueError, IndexError):
                                continue
                        
                        seq = max_n + 1
                        self.external_id = f"{prefix}{seq:03d}"
                except Exception:
                    # Generic fallback if sequence generation fails
                    self.external_id = f"{prefix}{uuid.uuid4().hex[:6].upper()}"
            else:
                # Default fallback for roles with no prefix: use username
                self.external_id = self.username

        if not self.referral_code:
            prefix = 'VX'
            try:
                with transaction.atomic():
                    existing = User.objects.filter(
                        referral_code__startswith=prefix,
                        referral_code__regex=r'^' + re.escape(prefix) + r'\d+$'
                    ).values_list('referral_code', flat=True)
                    
                    max_n = 0
                    for val in existing:
                        if not val:
                            continue
                        try:
                            n = int(val[len(prefix):])
                            if n > max_n:
                                max_n = n
                        except (ValueError, IndexError):
                            continue
                    
                    seq = max_n + 1
                    self.referral_code = f"{prefix}{seq:03d}"
            except Exception:
                self.referral_code = f"VX{uuid.uuid4().hex[:6].upper()}"

        if self.role == 'RIDER' and is_new:
            self.is_approved = True
            self.is_active = True

        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.username} ({self.role})"


DEVICE_TYPE_CHOICES = (
    ('IOS', 'iOS'),
    ('ANDROID', 'Android'),
)


class RiderAvailabilityLog(models.Model):
    user = models.ForeignKey('users.User', on_delete=models.CASCADE, related_name='availability_logs')
    went_online_at = models.DateTimeField()
    went_offline_at = models.DateTimeField(null=True, blank=True)

    def duration_seconds(self):
        if self.went_offline_at:
            return (self.went_offline_at - self.went_online_at).total_seconds()
        from django.utils import timezone
        return (timezone.now() - self.went_online_at).total_seconds()

    def __str__(self):
        return f"{self.user.username} online {self.went_online_at} - {self.went_offline_at or 'now'}"

    device_type = models.CharField(max_length=10, choices=DEVICE_TYPE_CHOICES, null=True, blank=True)


class RodieAvailabilityLog(models.Model):
    user = models.ForeignKey('users.User', on_delete=models.CASCADE, related_name='rodie_availability_logs')
    went_online_at = models.DateTimeField()
    went_offline_at = models.DateTimeField(null=True, blank=True)

    def duration_seconds(self):
        if self.went_offline_at:
            return (self.went_offline_at - self.went_online_at).total_seconds()
        from django.utils import timezone
        return (timezone.now() - self.went_online_at).total_seconds()

    def __str__(self):
        return f"{self.user.username} online {self.went_online_at} - {self.went_offline_at or 'now'}"

    device_type = models.CharField(max_length=10, choices=DEVICE_TYPE_CHOICES, null=True, blank=True)


class Wallet(models.Model):
    """Simple wallet model to track V coins for users."""
    user = models.OneToOneField('users.User', on_delete=models.CASCADE, related_name='wallet')
    balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    def __str__(self):
        return f"Wallet({self.user.username}): {self.balance}"




class WalletTransaction(models.Model):
    wallet = models.ForeignKey(Wallet, on_delete=models.CASCADE, related_name='transactions')
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reason = models.CharField(max_length=255, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.wallet.user.username}: {self.amount} ({self.reason})"


class Referral(models.Model):
    referrer = models.ForeignKey('users.User', related_name='referrals_made', on_delete=models.CASCADE)
    referred = models.ForeignKey('users.User', related_name='referred_by_user', on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=1000.00)
    is_credited = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Referral {self.referrer.username} -> {self.referred.username}: {self.amount} (Paid: {self.is_credited})"


class PlatformConfig(models.Model):
    """Singleton-like config to allow admin configuration via API.
    Admins can set `max_negative_balance`.
    """
    max_negative_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    trial_days = models.IntegerField(default=0, help_text="Free trial period in days from user registration")
    mechanic_transition_documents = models.JSONField(default=list, help_text="List of required documents for mechanic transition, e.g. ['ID', 'License', 'Certificate']")
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"PlatformConfig(max_neg={self.max_negative_balance})"


class Payment(models.Model):
    TRANSACTION_TYPE_CHOICES = (
        ('DEPOSIT', 'Deposit'),
        ('WITHDRAWAL', 'Withdrawal'),
    )
    STATUS_CHOICES = (
        ('PENDING', 'Pending'),
        ('COMPLETED', 'Completed'),
        ('FAILED', 'Failed'),
        ('CANCELLED', 'Cancelled'),
    )

    user = models.ForeignKey('users.User', on_delete=models.CASCADE, related_name='payments')
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    transaction_type = models.CharField(max_length=20, choices=TRANSACTION_TYPE_CHOICES)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING')
    reference = models.CharField(max_length=100, unique=True, help_text="Internal unique reference")
    processor_id = models.CharField(max_length=100, blank=True, null=True, help_text="Pesapal Order Tracking ID")
    description = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._original_status = self.status

    def save(self, *args, **kwargs):
        from django.db import transaction
        
        # If it's an existing withdrawal payment transitioning to FAILED
        if self.pk and self.transaction_type == 'WITHDRAWAL' and self.status == 'FAILED' and self._original_status != 'FAILED':
            with transaction.atomic():
                try:
                    wallet = self.user.wallet
                    # Refund the wallet
                    wallet.balance += self.amount
                    wallet.save()
                    
                    # Log the refund transaction
                    from .models import WalletTransaction
                    WalletTransaction.objects.create(
                        wallet=wallet,
                        amount=self.amount,
                        reason=f"Refund: Withdrawal Failed ({self.reference})"
                    )
                except Exception as e:
                    import logging
                    logging.getLogger(__name__).error(f"Failed to refund wallet for payment {self.id}: {str(e)}")
                    
        super().save(*args, **kwargs)
        self._original_status = self.status

    def __str__(self):
        return f"{self.transaction_type} - {self.reference} ({self.status})"
class Notification(models.Model):
    NOTIFICATION_TYPES = (
        ('BULLETIN', 'Bulletin'),
        ('UPDATE', 'Update'),
        ('PROMOTION', 'Promotion'),
        ('URGENT', 'Urgent Notice'),
        ('SERVICE', 'Service Announcement'),
    )
    
    TARGET_CHOICES = (
        ('RIDER', 'All Riders'),
        ('RODIE', 'All Roadies'),
        ('ALL', 'Everyone'),
        ('SPECIFIC', 'Specific User'),
    )

    recipient = models.ForeignKey(
        'users.User', 
        on_delete=models.CASCADE, 
        related_name='notifications',
        null=True, 
        blank=True,
        help_text="The specific user receiving this notification (null for bulk)"
    )
    target_role = models.CharField(
        max_length=10, 
        choices=TARGET_CHOICES, 
        default='SPECIFIC'
    )
    title = models.CharField(max_length=200)
    message = models.TextField(blank=True, default='')
    url = models.URLField(
        null=True,
        blank=True,
        help_text='Optional deep link or external URL for the notification'
    )
    notification_type = models.CharField(
        max_length=20, 
        choices=NOTIFICATION_TYPES, 
        default='UPDATE'
    )
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.recipient.username if self.recipient else 'Bulk'} - {self.title} ({self.notification_type})"


class PasswordResetToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    token = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    is_used = models.BooleanField(default=False)

    def is_valid(self):
        # Valid for 15 minutes
        from django.utils import timezone
        from datetime import timedelta
        return not self.is_used and (timezone.now() - self.created_at) < timedelta(minutes=15)

    def __str__(self):
        return f"ResetToken for {self.user.username} - {self.token}"


class SupportTicket(models.Model):
    """Support/Inquiry tickets submitted by users via feedback form"""
    
    STATUS_CHOICES = (
        ('PENDING', 'Pending'),
        ('ONGOING', 'Ongoing'),
        ('RESOLVED', 'Resolved'),
    )
    
    USER_TYPE_CHOICES = (
        ('RIDER', 'Rider'),
        ('RODIE', 'Roadie'),
    )
    
    # Unique support ID
    support_id = models.CharField(max_length=20, unique=True)
    
    # User who submitted the ticket
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='support_tickets'
    )
    user_type = models.CharField(
        max_length=10,
        choices=USER_TYPE_CHOICES,
        help_text="Whether the ticket is from a Rider or Roadie"
    )
    
    # Ticket content
    subject = models.CharField(max_length=200, blank=True)
    message = models.TextField()
    
    # Status tracking
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='PENDING'
    )
    
    # Internal notes for support team
    internal_comments = models.TextField(blank=True, null=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    
    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['status', '-created_at']),
            models.Index(fields=['user_type', '-created_at']),
        ]
    
    def __str__(self):
        return f"Ticket {self.support_id} - {self.user.username} ({self.status})"
    
    def save(self, *args, **kwargs):
        # Generate unique support ID if not set
        if not self.support_id:
            import uuid
            from django.utils import timezone
            timestamp = timezone.now().strftime('%Y%m%d')
            random_id = uuid.uuid4().hex[:6].upper()
            self.support_id = f"SUP-{timestamp}-{random_id}"
        super().save(*args, **kwargs)


class AdminAuditLog(models.Model):
    """Immutable audit log of all admin actions for accountability and traceability"""
    
    ACTION_TYPES = (
        ('USER_CREATE', 'User Created'),
        ('USER_UPDATE', 'User Updated'),
        ('USER_DELETE', 'User Deleted'),
        ('USER_APPROVE', 'User Approved'),
        ('USER_DEACTIVATE', 'User Deactivated'),
        ('ADMIN_CREATE', 'Admin Created'),
        ('ADMIN_DELETE', 'Admin Deleted'),
        ('SERVICE_CREATE', 'Service Created'),
        ('SERVICE_UPDATE', 'Service Updated'),
        ('SERVICE_DELETE', 'Service Deleted'),
        ('REQUEST_CANCEL', 'Request Cancelled'),
        ('WALLET_ADJUST', 'Wallet Adjusted'),
        ('PAYMENT_PROCESS', 'Payment Processed'),
        ('SUPPORT_UPDATE', 'Support Ticket Updated'),
        ('DISPUTE_RESOLVE', 'Dispute Resolved'),
        ('CONFIG_UPDATE', 'Config Updated'),
        ('NOTIFICATION_SEND', 'Notification Sent'),
        ('OTHER', 'Other'),
    )
    
    # Admin performing the action
    admin_user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        related_name='audit_logs_created'
    )
    
    # What action was performed
    action_type = models.CharField(max_length=50, choices=ACTION_TYPES)
    action_description = models.TextField()
    
    # Target entity
    target_user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='audit_logs_targeting'
    )
    target_entity_type = models.CharField(
        max_length=50,
        blank=True,
        help_text="Type of entity affected (User, Service, Request, etc.)"
    )
    target_entity_id = models.CharField(
        max_length=100,
        blank=True,
        help_text="ID of the entity affected"
    )
    
    # Change details (JSON for flexibility)
    changes = models.JSONField(default=dict, blank=True)
    
    # Timestamp
    created_at = models.DateTimeField(auto_now_add=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    
    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['admin_user', '-created_at']),
            models.Index(fields=['action_type', '-created_at']),
        ]
    
    def __str__(self):
        admin_name = self.admin_user.username if self.admin_user else "System"
        return f"{admin_name} - {self.action_type} - {self.created_at}"


class NotificationHistory(models.Model):
    """History tracking of all notifications sent to users"""
    
    DELIVERY_STATUS = (
        ('PENDING', 'Pending'),
        ('SENT', 'Sent'),
        ('FAILED', 'Failed'),
        ('DELIVERED', 'Delivered'),
    )
    
    # Original notification
    notification = models.ForeignKey(
        Notification,
        on_delete=models.CASCADE,
        related_name='history'
    )
    
    # Recipient details at time of send
    recipient = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='notification_history'
    )
    
    # Delivery tracking
    delivery_status = models.CharField(
        max_length=20,
        choices=DELIVERY_STATUS,
        default='PENDING'
    )
    delivery_error = models.TextField(blank=True, null=True)
    
    # Interaction tracking
    was_opened = models.BooleanField(default=False)
    opened_at = models.DateTimeField(null=True, blank=True)
    
    # Timestamps
    sent_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['-sent_at']
        indexes = [
            models.Index(fields=['recipient', '-sent_at']),
            models.Index(fields=['delivery_status', '-sent_at']),
        ]
    
    def __str__(self):
        return f"Notification to {self.recipient.username if self.recipient else 'Unknown'} - {self.delivery_status}"


class ReferralSummary(models.Model):
    """Summary stats for referrals (for report generation)"""
    
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='referral_summary'
    )
    
    total_referrals = models.IntegerField(default=0)
    successful_referrals = models.IntegerField(default=0)
    pending_referrals = models.IntegerField(default=0)
    total_rewards_paid = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    pending_rewards = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"Referral Summary for {self.user.username}"
