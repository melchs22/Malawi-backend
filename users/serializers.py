from rest_framework import serializers
from django.contrib.auth import get_user_model
from decimal import Decimal

from .models import Wallet, WalletTransaction, Referral, PlatformConfig, Notification, Payment
from services.models import RodieService

User = get_user_model()


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    referred_by_code = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = User
        fields = (
            'id',
            'first_name',
            'last_name',
            'email',
            'phone',
            'username',
            'password',
            'role',
            'nin',
            'referred_by_code',
            'fcm_token',
        )

    def create(self, validated_data):
        referred_by_code = validated_data.pop('referred_by_code', None)
        referrer = None

        # Find referrer if code was provided and validated
        if referred_by_code and referred_by_code.strip():
            referrer = User.objects.filter(referral_code__iexact=referred_by_code.strip()).first()

        role = validated_data.get('role')
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password'],
            first_name=validated_data['first_name'],
            last_name=validated_data['last_name'],
            phone=validated_data.get('phone'),
            role=role,
            nin=validated_data.get('nin'),
            fcm_token=validated_data.get('fcm_token'),
        )

        if role == 'RIDER':
            user.is_approved = True
            user.is_active = True
            user.save(update_fields=['is_approved', 'is_active'])

        wallet, _ = Wallet.objects.get_or_create(user=user)

        # Create referral record if valid referrer was found
        # No immediate crediting; rewards are earned when the referred user completes their first Job/Assist
        if referrer and referrer != user:
            Referral.objects.create(referrer=referrer, referred=user, amount=Decimal('1000.00'), is_credited=False)

        # Note: Services are no longer automatically assigned to roadies
        # They must manually select services through the services selection screen

        return user

    def validate(self, data):
        role = data.get('role')
        nin = data.get('nin')
        referred_by_code = data.get('referred_by_code')
        username = data.get('username')
        email = data.get('email')
        phone = data.get('phone')

        if role == 'WORKSHOP':
            raise serializers.ValidationError({
                'role': 'Workshop accounts are created through service-centre registration and admin approval.'
            })

        # NIN is required only for RODIE and MECHANIC roles, not for RIDER
        if role in ('RODIE', 'MECHANIC'):
            if not nin:
                raise serializers.ValidationError({'nin': 'NIN is required for roadies and mechanics'})
            if len(nin) != 14:
                raise serializers.ValidationError({'nin': 'NIN must be exactly 14 characters'})
            if User.objects.filter(nin=nin).exists():
                raise serializers.ValidationError({'nin': 'This NIN is already in use'})
        elif role == 'RIDER' and nin:
            # If rider provides NIN, validate it but don't require it
            if len(nin) != 14:
                raise serializers.ValidationError({'nin': 'NIN must be exactly 14 characters'})
            if User.objects.filter(nin=nin).exists():
                raise serializers.ValidationError({'nin': 'This NIN is already in use'})

        # Email must be unique within the same role
        # (same email CAN be used as both RIDER and RODIE)
        if email and role:
            if User.objects.filter(email__iexact=email, role=role).exists():
                raise serializers.ValidationError({
                    'email': 'This email address is already registered for this role.'
                })

        # Phone must be unique within the same role
        if phone and role:
            if User.objects.filter(phone=phone, role=role).exists():
                raise serializers.ValidationError({
                    'phone': 'This phone number is already registered for this role.'
                })

        # Username must be unique within the same role
        # (same username CAN be used as both RIDER and RODIE)
        if username and role:
            if User.objects.filter(username__iexact=username, role=role).exists():
                raise serializers.ValidationError({
                    'username': 'This username is already taken for this role.'
                })

        # Validate referral code if provided
        if referred_by_code and referred_by_code.strip():
            referred_by_code = referred_by_code.strip()
            referrer = User.objects.filter(referral_code__iexact=referred_by_code).first()
            if not referrer:
                raise serializers.ValidationError({
                    'referred_by_code': 'Invalid referral code. Please enter a valid code or proceed without referral.'
                })

        return data


class WalletTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = WalletTransaction
        fields = ('id', 'amount', 'reason', 'created_at')


class WalletSerializer(serializers.ModelSerializer):
    transactions = serializers.SerializerMethodField()
    user_id = serializers.IntegerField(source='user.id', read_only=True)
    user_external_id = serializers.CharField(source='user.external_id', read_only=True)
    user_username = serializers.CharField(source='user.username', read_only=True)
    user_role = serializers.CharField(source='user.role', read_only=True)

    class Meta:
        model = Wallet
        fields = ('id', 'user_id', 'user_external_id', 'user_username', 'user_role', 'balance', 'transactions')

    def get_transactions(self, obj):
        wallet_transactions = list(WalletTransaction.objects.filter(wallet=obj))
        payments = list(Payment.objects.filter(user=obj.user))
        combined = sorted(
            [*wallet_transactions, *payments],
            key=lambda item: item.created_at,
            reverse=True,
        )
        return TransactionHistorySerializer(combined, many=True).data


class UserSerializer(serializers.ModelSerializer):
    wallet = serializers.SerializerMethodField()
    services = serializers.SerializerMethodField()
    profile_photo = serializers.SerializerMethodField()
    id_card_front = serializers.SerializerMethodField()
    id_card_back = serializers.SerializerMethodField()
    license_photo = serializers.SerializerMethodField()
    vehicle_photo = serializers.SerializerMethodField()
    is_verified = serializers.BooleanField(source='is_approved', read_only=True)
    rating = serializers.SerializerMethodField()
    total_assists = serializers.SerializerMethodField()
    total_rides = serializers.SerializerMethodField()
    total_jobs = serializers.SerializerMethodField()
    trial_days_left = serializers.ReadOnlyField()
    trial_end_date = serializers.ReadOnlyField()
    max_negative_balance = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'external_id', 'first_name', 'last_name', 'email',
            'phone', 'username', 'role', 'referral_code', 'nin',
            'is_approved', 'is_verified', 'is_online', 'services_selected',
            'created_at', 'updated_at', 'wallet', 'services', 'profile_photo',
            'id_card_front', 'id_card_back', 'license_photo', 'vehicle_photo',
            'rating', 'total_assists', 'total_rides', 'total_jobs',
            'trial_days_left', 'trial_end_date', 'max_negative_balance',
            'deletion_status', 'deletion_requested_at', 'deletion_reason',
        ]
        read_only_fields = (
            'id', 'external_id', 'username', 'first_name', 'last_name', 
            'role', 'referral_code', 'nin', 'is_approved', 'is_verified', 
            'is_online', 'services_selected', 'created_at', 'updated_at', 
            'trial_days_left', 'trial_end_date', 'max_negative_balance'
        )

    def get_max_negative_balance(self, obj):
        from .models import PlatformConfig
        config = PlatformConfig.objects.first()
        return float(config.max_negative_balance) if config else 0.0

    def get_services(self, obj):
        if getattr(obj, 'role', None) not in ('RODIE', 'MECHANIC'):
            return []
        qs = RodieService.objects.filter(rodie=obj).select_related('service')
        return [
            {
                'service_id': r.service.id,
                'service_name': r.service.name,
                'fixed_price': r.service.fixed_price,
                'image': self.context['request'].build_absolute_uri(r.service.image.url) if r.service.image and 'request' in self.context else (r.service.image.url if r.service.image else None)
            } for r in qs
        ]

    def _get_user_image(self, obj, image_type):
        from images.models import UserImage
        image = UserImage.objects.filter(user=obj, image_type=image_type).order_by('-created_at').first()
        if image and image.original_image:
            if 'request' in self.context:
                return self.context['request'].build_absolute_uri(image.original_image.url)
            return image.original_image.url
        return None

    def get_profile_photo(self, obj):
        return self._get_user_image(obj, 'PROFILE')

    def get_id_card_front(self, obj):
        # Handle both naming conventions (ID_CARD_FRONT from some views, NIN_FRONT from others)
        return self._get_user_image(obj, 'NIN_FRONT') or self._get_user_image(obj, 'ID_CARD_FRONT')

    def get_id_card_back(self, obj):
        return self._get_user_image(obj, 'NIN_BACK') or self._get_user_image(obj, 'ID_CARD_BACK')

    def get_license_photo(self, obj):
        return self._get_user_image(obj, 'LICENSE')

    def get_vehicle_photo(self, obj):
        return self._get_user_image(obj, 'VEHICLE')

    def get_wallet(self, obj):
        try:
            wallet = obj.wallet
            return {
                'id': wallet.id,
                'balance': str(wallet.balance),
            }
        except (Wallet.DoesNotExist, AttributeError):
            return None

    def get_rating(self, obj):
        from django.apps import apps
        Rating = apps.get_model('service_requests', 'Rating')
        from django.db.models import Avg
        avg = Rating.objects.filter(rated_user=obj).aggregate(Avg('rating'))['rating__avg']
        # Default to 5.0 for new users instead of 0.0
        return float(avg) if avg is not None else 5.0

    def get_total_assists(self, obj):
        from django.apps import apps
        ServiceRequest = apps.get_model('service_requests', 'ServiceRequest')
        if obj.role == 'RIDER':
            return ServiceRequest.objects.filter(rider=obj, status='COMPLETED').count()
        return ServiceRequest.objects.filter(rodie=obj, status='COMPLETED').count()

    def get_total_rides(self, obj):
        return self.get_total_assists(obj)

    def get_total_jobs(self, obj):
        return self.get_total_assists(obj)


class ReferralSerializer(serializers.ModelSerializer):
    referrer = UserSerializer(read_only=True)
    referred_user = UserSerializer(source='referred', read_only=True)

    class Meta:
        model = Referral
        fields = ('id', 'referrer', 'referred_user', 'amount', 'is_credited', 'created_at')


class PlatformConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = PlatformConfig
        fields = ('id', 'max_negative_balance', 'trial_days', 'mechanic_transition_documents', 'updated_at')


class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = ('id', 'amount', 'transaction_type', 'status', 'reference', 'created_at')
        read_only_fields = ('id', 'status', 'reference', 'created_at')


class DepositSerializer(serializers.Serializer):
    """No amount required — Pesapal page lets user enter amount themselves."""
    pass


class WithdrawSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=Decimal('5000.00'))
    phone_number = serializers.CharField(max_length=20, required=False)

    def validate_amount(self, value):
        from decimal import Decimal
        if value < Decimal('5000.00'):
            raise serializers.ValidationError(
                'Minimum withdrawal amount is UGX 5,000 per transaction.'
            )
        return value


class TransactionHistorySerializer(serializers.Serializer):
    """Unified transaction history combining Payments and WalletTransactions"""
    id = serializers.SerializerMethodField()
    type = serializers.SerializerMethodField()
    amount = serializers.DecimalField(max_digits=12, decimal_places=2)
    reason = serializers.SerializerMethodField()
    status = serializers.SerializerMethodField()
    reference = serializers.SerializerMethodField()
    created_at = serializers.DateTimeField()

    def get_id(self, obj):
        if isinstance(obj, Payment):
            return f"payment_{obj.id}"
        return f"transaction_{obj.id}"

    def get_type(self, obj):
        if isinstance(obj, Payment):
            return obj.transaction_type  # DEPOSIT or WITHDRAWAL
        return "TRANSACTION"

    def get_reason(self, obj):
        if isinstance(obj, Payment):
            return obj.description
        return obj.reason or "Wallet Transaction"

    def get_status(self, obj):
        if isinstance(obj, Payment):
            return obj.status
        return "COMPLETED"

    def get_reference(self, obj):
        if isinstance(obj, Payment):
            return obj.reference
        return f"TXN-{obj.id}"


class RoadiePaymentSummarySerializer(serializers.Serializer):
    """Summary of roadie payments including balance and recent activity"""
    current_balance = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_earned = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_withdrawn = serializers.DecimalField(max_digits=12, decimal_places=2)
    pending_deposits = serializers.DecimalField(max_digits=12, decimal_places=2)
    transaction_count = serializers.IntegerField()


class UserProfileUpdateSerializer(serializers.ModelSerializer):
    """Serializer for users to update their profile information"""
    class Meta:
        model = User
        fields = (
            'id',
            'first_name',
            'last_name',
            'email',
            'phone',
            'username',
            'fcm_token',
        )
        read_only_fields = ('id',)

    def validate_email(self, value):
        user = self.instance
        if User.objects.exclude(id=user.id).filter(email=value, role=user.role).exists():
            raise serializers.ValidationError("This email is already in use for this role.")
        return value

    def validate_phone(self, value):
        user = self.instance
        if User.objects.exclude(id=user.id).filter(phone=value, role=user.role).exists():
            raise serializers.ValidationError("This phone number is already in use for this role.")
        return value

    def validate_username(self, value):
        user = self.instance
        if User.objects.exclude(id=user.id).filter(username=value, role=user.role).exists():
            raise serializers.ValidationError("This username is already taken for this role.")
        return value

    def update(self, instance, validated_data):
        instance.first_name = validated_data.get('first_name', instance.first_name)
        instance.last_name = validated_data.get('last_name', instance.last_name)
        instance.email = validated_data.get('email', instance.email)
        instance.phone = validated_data.get('phone', instance.phone)
        instance.username = validated_data.get('username', instance.username)
        instance.fcm_token = validated_data.get('fcm_token', instance.fcm_token)
        instance.save()
        return instance


class UserProfilePhotoSerializer(serializers.Serializer):
    """Serializer for uploading profile photo"""
    profile_photo = serializers.ImageField()

    def validate_profile_photo(self, value):
        # Simple validation
        if value.size > 5 * 1024 * 1024:  # 5MB limit
            raise serializers.ValidationError("Profile photo size must be less than 5MB.")
        return value

class NotificationSerializer(serializers.ModelSerializer):
    body = serializers.CharField(source='message', required=False, allow_blank=True)
    user = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.all(),
        source='recipient',
        write_only=True,
        required=False,
        allow_null=True
    )
    recipient_id = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.all(),
        source='recipient',
        write_only=True,
        required=False,
        allow_null=True
    )
    recipient_external_id = serializers.CharField(
        source='recipient.external_id',
        read_only=True
    )
    target_role = serializers.CharField(required=False)
    broadcast = serializers.BooleanField(write_only=True, required=False)
    data = serializers.JSONField(write_only=True, required=False)

    class Meta:
        model = Notification
        fields = [
            'id',
            'recipient_id',
            'recipient_external_id',
            'target_role',
            'title',
            'body',
            'message',
            'url',
            'notification_type',
            'is_read',
            'created_at',
            'user',
            'broadcast',
            'data',
        ]
        read_only_fields = ['id', 'created_at']

    def validate(self, attrs):
        broadcast = attrs.pop('broadcast', False)
        data = attrs.pop('data', None) or {}
        if data.get('url') and not attrs.get('url'):
            attrs['url'] = data.get('url')
        if broadcast:
            attrs['target_role'] = 'ALL'
            attrs['recipient'] = None
        elif attrs.get('recipient'):
            attrs.setdefault('target_role', 'SPECIFIC')
        return attrs
