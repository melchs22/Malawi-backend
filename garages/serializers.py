from rest_framework import serializers
from django.db import transaction
from django.contrib.auth import get_user_model
import re
from datetime import time
from decimal import Decimal

from .models import (
    Garage,
    GarageInvoice,
    GaragePayment,
    GarageQuote,
    GarageReview,
    GarageSettlement,
    GarageServiceRequest,
)

User = get_user_model()


def normalize_phone_number(value):
    compact = re.sub(r'[\s()-]', '', value)
    if compact.startswith('0'):
        compact = f'+265{compact[1:]}'
    elif compact.startswith('265'):
        compact = f'+{compact}'
    if not re.fullmatch(r'\+[1-9]\d{7,14}', compact):
        raise serializers.ValidationError(
            'Enter a valid international phone number in +country-code format, or a local Malawi number beginning with 0.'
        )
    return compact


def validate_working_schedule(operating_hours, working_days):
    valid_days = {
        'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
    }
    if not isinstance(operating_hours, dict) or not isinstance(working_days, list):
        raise serializers.ValidationError(
            'Operating hours must be a weekday map and working days must be a list.'
        )
    if any(day not in valid_days for day in operating_hours):
        raise serializers.ValidationError({'operating_hours': 'Use lowercase weekday names.'})
    if not working_days or any(day not in valid_days for day in working_days):
        raise serializers.ValidationError({'working_days': 'Select at least one valid weekday.'})
    if len(set(working_days)) != len(working_days):
        raise serializers.ValidationError({'working_days': 'Weekdays cannot be repeated.'})
    for day in working_days:
        hours = operating_hours.get(day)
        if not isinstance(hours, str) or hours.lower() == 'closed':
            raise serializers.ValidationError(
                {'operating_hours': f'Provide opening hours for {day}.'}
            )
        try:
            opening, closing = hours.split('-', maxsplit=1)
            opening_time = time.fromisoformat(opening.strip())
            closing_time = time.fromisoformat(closing.strip())
        except ValueError as error:
            raise serializers.ValidationError(
                {'operating_hours': f'Use HH:MM-HH:MM format for {day}.'}
            ) from error
        if opening_time >= closing_time:
            raise serializers.ValidationError(
                {'operating_hours': f'Closing time must be after opening time on {day}.'}
            )


class GarageRegistrationSerializer(serializers.ModelSerializer):
    """Serializer for garage registration/onboarding"""
    primary_phone = serializers.CharField(max_length=20)
    secondary_phone = serializers.CharField(
        max_length=20, required=False, allow_blank=True, allow_null=True
    )
    owner_phone = serializers.CharField(max_length=20)
    emergency_contact_phone = serializers.CharField(
        max_length=20, required=False, allow_blank=True, allow_null=True
    )
    manager_phone = serializers.CharField(
        max_length=20, required=False, allow_blank=True, allow_null=True
    )
    owner_id_front = serializers.ImageField(required=False)
    owner_id_back = serializers.ImageField(required=False)
    business_registration_cert = serializers.FileField(required=False)
    trading_license = serializers.FileField(required=False)
    local_authority_letter = serializers.FileField(required=False)
    exterior_photo = serializers.ImageField(required=True)
    interior_workshop_photo = serializers.ImageField(required=True)
    tools_equipment_photo = serializers.ImageField(required=False)

    class Meta:
        model = Garage
        fields = [
            # Garage Identity
            'name', 'garage_type', 'years_in_operation', 'physical_address',
            'latitude', 'longitude', 'operating_hours', 'primary_phone',
            'secondary_phone', 'business_email',

            # Ownership & Management
            'owner_name', 'owner_national_id', 'owner_id_front', 'owner_id_back',
            'owner_phone', 'owner_email', 'emergency_contact_name', 'emergency_contact_phone',
            'manager_name', 'manager_phone', 'manager_email',

            # Legal & Business Documents
            'business_registration_cert', 'tin_tax_id', 'trading_license', 'local_authority_letter',

            # Workshop Proof
            'exterior_photo', 'interior_workshop_photo', 'tools_equipment_photo',

            # Services Offered
            'vehicle_types', 'services_offered', 'services_not_offered',

            # Pricing Information
            'pricing_info', 'is_price_negotiable',

            # Staff & Skills
            'mechanics_count', 'lead_mechanic_name', 'experience_years',
            'certifications', 'specialized_skills',

            # Service Policies
            'warranty_offered', 'warranty_duration_days', 'avg_turnaround_hours',
            'emergency_service_available', 'working_days', 'cancellation_policy',

            # Banking & Payments
            'payment_method', 'account_holder_name', 'account_number',
            'provider_name', 'settlement_preference',

            # Compliance & Agreements
            'terms_accepted',
        ]
        read_only_fields = ['application_tracking_id', 'verification_status', 'submission_completeness', 'registration_date']

    def validate_owner_email(self, value):
        if User.objects.filter(email__iexact=value, role='WORKSHOP').exists():
            raise serializers.ValidationError(
                "A workshop account already exists for this email address."
            )
        return value

    def validate_primary_phone(self, value):
        return normalize_phone_number(value)

    def validate_secondary_phone(self, value):
        return normalize_phone_number(value) if value else value

    def validate_owner_phone(self, value):
        return normalize_phone_number(value)

    def validate_emergency_contact_phone(self, value):
        return normalize_phone_number(value) if value else value

    def validate_manager_phone(self, value):
        return normalize_phone_number(value) if value else value

    def create(self, validated_data):
        garage = self._create_with_owner(validated_data)
        return garage

    @transaction.atomic
    def _create_with_owner(self, validated_data):
        garage = Garage.objects.create(**validated_data)
        owner_names = garage.owner_name.strip().split(maxsplit=1)
        username = f"workshop_{garage.application_tracking_id}".lower()
        owner = User.objects.create_user(
            username=username,
            email=garage.owner_email,
            password=None,
            first_name=owner_names[0],
            last_name=owner_names[1] if len(owner_names) > 1 else '',
            phone=garage.owner_phone,
            role='WORKSHOP',
            is_active=False,
            is_approved=False,
        )
        owner.set_unusable_password()
        owner.save(update_fields=['password'])
        garage.owner_user = owner
        garage.save(update_fields=['owner_user'])
        return garage

    def validate_terms_accepted(self, value):
        if not value:
            raise serializers.ValidationError("You must accept the Vehix partner terms to register.")
        return value

    def validate_vehicle_types(self, value):
        if not isinstance(value, list) or len(value) == 0:
            raise serializers.ValidationError("At least one vehicle type must be selected.")
        valid_types = [choice[0] for choice in Garage.VEHICLE_TYPES]
        for v_type in value:
            if v_type not in valid_types:
                raise serializers.ValidationError(f"Invalid vehicle type: {v_type}")
        return value

    def validate_services_offered(self, value):
        if not isinstance(value, list) or len(value) == 0:
            raise serializers.ValidationError("At least one service must be offered.")
        valid_services = [choice[0] for choice in Garage.SERVICE_CATEGORIES]
        for service in value:
            if service not in valid_services:
                raise serializers.ValidationError(f"Invalid service category: {service}")
        return value

    def validate(self, attrs):
        validate_working_schedule(
            attrs.get('operating_hours'),
            attrs.get('working_days'),
        )
        return attrs


class GarageListSerializer(serializers.ModelSerializer):
    """Serializer for listing garages (public view for riders)"""
    average_rating = serializers.DecimalField(
        max_digits=4,
        decimal_places=2,
        read_only=True,
        allow_null=True,
    )
    rating_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Garage
        fields = [
            'id', 'name', 'garage_type', 'physical_address', 'latitude', 'longitude',
            'operating_hours', 'primary_phone', 'business_email', 'vehicle_types',
            'services_offered', 'pricing_info', 'is_price_negotiable', 'warranty_offered',
            'warranty_duration_days', 'avg_turnaround_hours', 'emergency_service_available',
            'working_days', 'average_rating', 'rating_count'
        ]


class GarageDetailSerializer(serializers.ModelSerializer):
    """Detailed serializer for garage profile view"""
    average_rating = serializers.DecimalField(
        max_digits=4,
        decimal_places=2,
        read_only=True,
        allow_null=True,
    )
    rating_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Garage
        fields = [
            'id', 'name', 'garage_type', 'years_in_operation', 'physical_address',
            'latitude', 'longitude', 'operating_hours', 'primary_phone', 'secondary_phone',
            'business_email', 'vehicle_types', 'services_offered', 'services_not_offered',
            'pricing_info', 'is_price_negotiable', 'mechanics_count', 'lead_mechanic_name',
            'experience_years', 'certifications', 'specialized_skills', 'warranty_offered',
            'warranty_duration_days', 'avg_turnaround_hours', 'emergency_service_available',
            'working_days', 'cancellation_policy', 'verification_status',
            'average_rating', 'rating_count'
        ]


class GarageServiceRequestSerializer(serializers.ModelSerializer):
    """Serializer for garage service requests from riders"""
    rider = serializers.PrimaryKeyRelatedField(read_only=True)
    garage_name = serializers.CharField(source='garage.name', read_only=True)
    rider_name = serializers.CharField(source='rider.username', read_only=True)
    quotes = serializers.SerializerMethodField()
    invoice = serializers.SerializerMethodField()
    review = serializers.SerializerMethodField()

    class Meta:
        model = GarageServiceRequest
        fields = [
            'id', 'rider', 'rider_name', 'garage', 'garage_name', 'vehicle_type',
            'service_category', 'description', 'preferred_date', 'preferred_time',
            'location_lat', 'location_lng', 'status', 'estimated_cost', 'actual_cost',
            'created_at', 'updated_at', 'response_note', 'quotes', 'invoice', 'review'
        ]
        read_only_fields = [
            'id', 'rider', 'status', 'estimated_cost', 'actual_cost',
            'response_note', 'created_at', 'updated_at'
        ]

    def get_quotes(self, obj):
        return GarageQuoteSerializer(obj.quotes.all(), many=True).data

    def get_invoice(self, obj):
        quote = obj.quotes.filter(status='ACCEPTED').first()
        invoice = getattr(quote, 'invoice', None) if quote else None
        return GarageInvoiceSerializer(invoice).data if invoice else None

    def get_review(self, obj):
        review = getattr(obj, 'review', None)
        return GarageReviewSerializer(review).data if review else None

    def validate_preferred_date(self, value):
        from django.utils import timezone
        if value < timezone.now().date():
            raise serializers.ValidationError("Preferred date cannot be in the past.")
        return value

    def validate(self, attrs):
        request = self.context.get('request')
        garage = attrs.get('garage')
        if request and request.user.is_authenticated:
            if request.user.role != 'RIDER':
                raise serializers.ValidationError("Only member accounts may request garage services.")
        if garage and garage.verification_status != 'VERIFIED':
            raise serializers.ValidationError({'garage': 'This service centre is not accepting bookings.'})
        if garage:
            vehicle_type = attrs.get('vehicle_type')
            service_category = attrs.get('service_category')
            if vehicle_type not in garage.vehicle_types:
                raise serializers.ValidationError({'vehicle_type': 'This service centre does not support this vehicle type.'})
            if service_category not in garage.services_offered:
                raise serializers.ValidationError({'service_category': 'This service centre does not offer this service.'})
        latitude = attrs.get('location_lat')
        longitude = attrs.get('location_lng')
        if (latitude is None) != (longitude is None):
            raise serializers.ValidationError('Provide both location coordinates or neither.')
        if latitude is not None and not Decimal('-90') <= latitude <= Decimal('90'):
            raise serializers.ValidationError({'location_lat': 'Latitude must be between -90 and 90.'})
        if longitude is not None and not Decimal('-180') <= longitude <= Decimal('180'):
            raise serializers.ValidationError({'location_lng': 'Longitude must be between -180 and 180.'})
        return attrs


class QuoteLineItemSerializer(serializers.Serializer):
    description = serializers.CharField(max_length=255, trim_whitespace=True)
    quantity = serializers.IntegerField(min_value=1, max_value=100)
    unit_amount = serializers.DecimalField(max_digits=12, decimal_places=0, min_value=0)


class GarageQuoteCreateSerializer(serializers.Serializer):
    line_items = QuoteLineItemSerializer(many=True, allow_empty=False)
    scheduled_date = serializers.DateField()
    scheduled_time = serializers.TimeField(required=False, allow_null=True)

    def validate_line_items(self, value):
        amount = sum(
            item['unit_amount'] * item['quantity']
            for item in value
        )
        if amount <= 0:
            raise serializers.ValidationError('A quote total must be greater than zero.')
        if amount > 2_147_483_647:
            raise serializers.ValidationError("A quote total exceeds PayChangu's maximum amount.")
        return value

    def validate(self, attrs):
        booking = self.context['booking']
        validate_working_schedule(
            booking.garage.operating_hours,
            booking.garage.working_days,
        )
        scheduled_date = attrs['scheduled_date']
        if scheduled_date < booking.preferred_date:
            raise serializers.ValidationError({
                'scheduled_date': 'The confirmed appointment cannot be earlier than the requested date.'
            })
        weekday = scheduled_date.strftime('%A').lower()
        garage = booking.garage
        if weekday not in garage.working_days:
            raise serializers.ValidationError({
                'scheduled_date': 'The service centre is closed on the selected day.'
            })
        hours = garage.operating_hours.get(weekday, '')
        if attrs.get('scheduled_time'):
            opening, closing = hours.split('-', maxsplit=1)
            if not time.fromisoformat(opening.strip()) <= attrs['scheduled_time'] < time.fromisoformat(closing.strip()):
                raise serializers.ValidationError({
                    'scheduled_time': 'The confirmed time must be within the service centre operating hours.'
                })
        return attrs


class GarageQuoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = GarageQuote
        fields = [
            'id', 'revision', 'line_items', 'amount', 'currency', 'scheduled_date',
            'scheduled_time', 'status', 'response_reason', 'created_at', 'responded_at'
        ]
        read_only_fields = fields


class GaragePaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = GaragePayment
        fields = [
            'id', 'transaction_reference', 'provider_reference', 'checkout_url',
            'amount', 'currency', 'status', 'is_excess_payment',
            'created_at', 'verified_at'
        ]
        read_only_fields = fields


class GarageInvoiceSerializer(serializers.ModelSerializer):
    payments = GaragePaymentSerializer(many=True, read_only=True)
    garage_name = serializers.CharField(source='quote.service_request.garage.name', read_only=True)

    class Meta:
        model = GarageInvoice
        fields = [
            'id', 'invoice_number', 'garage_name', 'amount', 'currency', 'status',
            'issued_at', 'paid_at', 'payments'
        ]
        read_only_fields = fields


class GarageSettlementSerializer(serializers.ModelSerializer):
    settled_by_name = serializers.CharField(source='settled_by.username', read_only=True)

    class Meta:
        model = GarageSettlement
        fields = [
            'id', 'amount', 'transfer_reference', 'settled_by',
            'settled_by_name', 'notes', 'is_final', 'settled_at'
        ]
        read_only_fields = fields


class GarageAdminInvoiceSerializer(GarageInvoiceSerializer):
    settlements = GarageSettlementSerializer(many=True, read_only=True)

    class Meta(GarageInvoiceSerializer.Meta):
        fields = GarageInvoiceSerializer.Meta.fields + ['settlements']


class GarageProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = Garage
        fields = [
            'id', 'name', 'physical_address', 'latitude', 'longitude',
            'operating_hours', 'primary_phone', 'secondary_phone', 'business_email',
            'vehicle_types', 'services_offered', 'services_not_offered',
            'pricing_info', 'is_price_negotiable', 'mechanics_count',
            'lead_mechanic_name', 'experience_years', 'certifications',
            'specialized_skills', 'warranty_offered', 'warranty_duration_days',
            'avg_turnaround_hours', 'emergency_service_available', 'working_days',
            'cancellation_policy', 'verification_status'
        ]
        read_only_fields = ['id', 'verification_status']

    def validate(self, attrs):
        garage = self.instance
        vehicle_types = attrs.get('vehicle_types', garage.vehicle_types)
        services_offered = attrs.get('services_offered', garage.services_offered)
        validate_working_schedule(
            attrs.get('operating_hours', garage.operating_hours),
            attrs.get('working_days', garage.working_days),
        )
        if not vehicle_types:
            raise serializers.ValidationError({'vehicle_types': 'At least one vehicle type is required.'})
        valid_vehicle_types = {choice[0] for choice in Garage.VEHICLE_TYPES}
        if any(value not in valid_vehicle_types for value in vehicle_types):
            raise serializers.ValidationError({'vehicle_types': 'One or more vehicle types are invalid.'})
        if not services_offered:
            raise serializers.ValidationError({'services_offered': 'At least one service is required.'})
        valid_services = {choice[0] for choice in Garage.SERVICE_CATEGORIES}
        if any(value not in valid_services for value in services_offered):
            raise serializers.ValidationError({'services_offered': 'One or more services are invalid.'})
        if attrs.get('mechanics_count', garage.mechanics_count) < 1:
            raise serializers.ValidationError({'mechanics_count': 'At least one mechanic must be available.'})
        return attrs

    def validate_primary_phone(self, value):
        return normalize_malawi_phone(value)

    def validate_secondary_phone(self, value):
        return normalize_malawi_phone(value) if value else value


class QuoteResponseSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['accept', 'decline'])
    reason = serializers.CharField(required=False, allow_blank=True, max_length=1000)


class GarageDeclineSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=1000, trim_whitespace=True)


class GarageReviewSerializer(serializers.ModelSerializer):
    rider_name = serializers.CharField(source='rider.username', read_only=True)
    garage_name = serializers.CharField(source='service_request.garage.name', read_only=True)
    booking_id = serializers.IntegerField(source='service_request.id', read_only=True)

    class Meta:
        model = GarageReview
        fields = [
            'id', 'booking_id', 'garage_name', 'rider_name',
            'rating', 'comment', 'created_at'
        ]
        read_only_fields = ['id', 'booking_id', 'garage_name', 'rider_name', 'created_at']

    def validate_rating(self, value):
        if not 1 <= value <= 5:
            raise serializers.ValidationError('Rating must be between 1 and 5.')
        return value


class GarageSettlementCreateSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=14, decimal_places=0, min_value=1)
    transfer_reference = serializers.CharField(max_length=100)
    notes = serializers.CharField(required=False, allow_blank=True)
    is_final = serializers.BooleanField(default=False)

    def validate_transfer_reference(self, value):
        from .models import GarageSettlement

        if GarageSettlement.objects.filter(transfer_reference=value).exists():
            raise serializers.ValidationError('This transfer reference has already been recorded.')
        return value


class GarageApplicationStatusSerializer(serializers.Serializer):
    """Serializer for checking garage application status by tracking ID"""
    application_tracking_id = serializers.CharField(max_length=10, required=True)

    def validate_application_tracking_id(self, value):
        try:
            garage = Garage.objects.get(application_tracking_id=value.upper())
            return value.upper()
        except Garage.DoesNotExist:
            raise serializers.ValidationError("Invalid application tracking ID.")


class GarageRegistrationResponseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Garage
        fields = [
            'application_tracking_id', 'verification_status',
            'submission_completeness', 'registration_date',
        ]
        read_only_fields = fields


class GarageStatusResponseSerializer(serializers.ModelSerializer):
    """Serializer for garage application status response"""
    verified_by_name = serializers.CharField(source='verified_by.username', read_only=True)

    class Meta:
        model = Garage
        fields = [
            'application_tracking_id', 'name', 'verification_status', 'submission_completeness',
            'registration_date', 'verified_at', 'rejection_reason', 'suspension_reason',
            'verified_by_name'
        ]


class GarageAdminSerializer(serializers.ModelSerializer):
    """Admin serializer for managing garages"""
    verified_by_name = serializers.CharField(source='verified_by.username', read_only=True)

    class Meta:
        model = Garage
        fields = '__all__'
        read_only_fields = [
            'owner_user', 'application_tracking_id', 'verification_status',
            'submission_completeness', 'registration_date', 'registration_ip',
            'device_type', 'verified_by', 'verified_at', 'rejection_reason',
            'suspension_reason', 'terms_accepted_at', 'terms_accepted_ip',
        ]
