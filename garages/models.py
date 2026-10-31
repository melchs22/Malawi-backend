from django.db import models
from django.contrib.auth import get_user_model
from django.core.validators import RegexValidator
from django.utils import timezone
import uuid
import secrets

User = get_user_model()


class Garage(models.Model):
    GARAGE_TYPE_CHOICES = (
        ('INDIVIDUAL', 'Individual / Informal'),
        ('REGISTERED', 'Registered Business'),
    )

    VERIFICATION_STATUS_CHOICES = (
        ('SUBMITTED', 'Submitted'),
        ('UNDER_REVIEW', 'Under Review'),
        ('VERIFIED', 'Verified'),
        ('REJECTED', 'Rejected'),
        ('SUSPENDED', 'Suspended'),
    )

    # Garage Identity
    name = models.CharField(max_length=255, help_text="Garage name as publicly displayed")
    garage_type = models.CharField(max_length=20, choices=GARAGE_TYPE_CHOICES)
    years_in_operation = models.PositiveIntegerField()
    physical_address = models.TextField()
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    operating_hours = models.JSONField(
        help_text="Weekday-to-hours map, e.g. {'monday': '08:00-17:00'}; use 'Closed' for closed days."
    )
    primary_phone = models.CharField(max_length=20, validators=[RegexValidator(r'^\+[1-9]\d{7,14}$')])
    secondary_phone = models.CharField(max_length=20, blank=True, null=True, validators=[RegexValidator(r'^\+[1-9]\d{7,14}$')])
    business_email = models.EmailField()

    # Ownership & Management
    owner_name = models.CharField(max_length=255)
    owner_national_id = models.CharField(max_length=20, unique=True)
    owner_user = models.OneToOneField(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='owned_garage'
    )
    owner_id_front = models.ImageField(upload_to='garage_docs/', blank=True, null=True)
    owner_id_back = models.ImageField(upload_to='garage_docs/', blank=True, null=True)
    owner_phone = models.CharField(max_length=20, validators=[RegexValidator(r'^\+[1-9]\d{7,14}$')])
    owner_email = models.EmailField()
    emergency_contact_name = models.CharField(max_length=255, blank=True, null=True)
    emergency_contact_phone = models.CharField(max_length=20, blank=True, null=True, validators=[RegexValidator(r'^\+[1-9]\d{7,14}$')])

    # Manager details (optional)
    manager_name = models.CharField(max_length=255, blank=True, null=True)
    manager_phone = models.CharField(max_length=20, blank=True, null=True, validators=[RegexValidator(r'^\+[1-9]\d{7,14}$')])
    manager_email = models.EmailField(blank=True, null=True)

    # Legal & Business Documents
    business_registration_cert = models.FileField(upload_to='garage_docs/', blank=True, null=True)
    tin_tax_id = models.CharField(max_length=50, blank=True, null=True)
    trading_license = models.FileField(upload_to='garage_docs/', blank=True, null=True)
    local_authority_letter = models.FileField(upload_to='garage_docs/', blank=True, null=True)

    # Workshop Proof
    exterior_photo = models.ImageField(upload_to='garage_photos/')
    interior_workshop_photo = models.ImageField(upload_to='garage_photos/')
    tools_equipment_photo = models.ImageField(upload_to='garage_photos/', blank=True, null=True)

    # Services Offered
    VEHICLE_TYPES = (
        ('MOTORCYCLE', 'Motorcycles'),
        ('CAR', 'Cars'),
        ('VAN', 'Vans'),
        ('TRUCK', 'Trucks'),
    )
    vehicle_types = models.JSONField(help_text="List of supported vehicle types")

    SERVICE_CATEGORIES = (
        ('ENGINE_REPAIR', 'Engine Repair'),
        ('BRAKE_SERVICE', 'Brake Service'),
        ('ELECTRICAL_DIAGNOSTICS', 'Electrical & Diagnostics'),
        ('TIRE_WHEEL', 'Tire & Wheel Services'),
        ('BODY_WORK', 'Body Work & Painting'),
        ('ROUTINE_SERVICING', 'Routine Servicing'),
        ('ACCIDENT_REPAIR', 'Accident Repair'),
    )
    services_offered = models.JSONField(help_text="List of services offered")
    services_not_offered = models.JSONField(blank=True, null=True, help_text="List of services not offered")

    # Pricing Information
    pricing_info = models.JSONField(help_text="Pricing details for each service")
    is_price_negotiable = models.BooleanField(default=False)

    # Staff & Skills
    mechanics_count = models.PositiveIntegerField(default=1)
    lead_mechanic_name = models.CharField(max_length=255, blank=True, null=True)
    experience_years = models.PositiveIntegerField(blank=True, null=True)
    certifications = models.JSONField(blank=True, null=True, help_text="List of certifications")
    specialized_skills = models.TextField(blank=True, null=True)

    # Service Policies
    warranty_offered = models.BooleanField(default=False)
    warranty_duration_days = models.PositiveIntegerField(blank=True, null=True)
    avg_turnaround_hours = models.PositiveIntegerField(help_text="Average service turnaround time in hours")
    emergency_service_available = models.BooleanField(default=False)
    working_days = models.JSONField(help_text="Working days, e.g. ['monday', 'tuesday', ...]")
    cancellation_policy = models.TextField()

    # Banking & Payments
    PAYMENT_METHODS = (
        ('MOBILE_MONEY', 'Mobile Money'),
        ('BANK_TRANSFER', 'Bank Transfer'),
    )
    payment_method = models.CharField(max_length=20, choices=PAYMENT_METHODS)
    account_holder_name = models.CharField(max_length=255)
    account_number = models.CharField(max_length=50)
    provider_name = models.CharField(max_length=255, help_text="Mobile money provider or bank name")
    settlement_preference = models.CharField(max_length=20, choices=(('DAILY', 'Daily'), ('WEEKLY', 'Weekly')), default='WEEKLY')

    # Compliance & Agreements
    terms_accepted = models.BooleanField(default=False)
    terms_accepted_at = models.DateTimeField(blank=True, null=True)
    terms_accepted_ip = models.GenericIPAddressField(blank=True, null=True)

    # System Metadata
    application_tracking_id = models.CharField(max_length=10, unique=True, blank=True, null=True, help_text="Unique tracking ID for application status checking")
    verification_status = models.CharField(max_length=20, choices=VERIFICATION_STATUS_CHOICES, default='SUBMITTED')
    submission_completeness = models.DecimalField(max_digits=5, decimal_places=2, default=0.00, help_text="Percentage of completion")
    registration_date = models.DateTimeField(default=timezone.now)
    registration_ip = models.GenericIPAddressField(blank=True, null=True)
    device_type = models.CharField(max_length=50, blank=True, null=True)

    # Admin fields
    verified_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='verified_garages')
    verified_at = models.DateTimeField(blank=True, null=True)
    rejection_reason = models.TextField(blank=True, null=True)
    suspension_reason = models.TextField(blank=True, null=True)

    def __str__(self):
        return f"{self.name} ({self.verification_status})"

    def save(self, *args, **kwargs):
        if not self.application_tracking_id:
            self.application_tracking_id = secrets.token_hex(5).upper()

        # Calculate submission completeness
        total_fields = 0
        filled_fields = 0

        # Count mandatory fields
        mandatory_fields = [
            'name', 'garage_type', 'years_in_operation', 'physical_address',
            'operating_hours', 'primary_phone', 'business_email',
            'owner_name', 'owner_national_id', 'owner_phone', 'owner_email',
            'exterior_photo', 'interior_workshop_photo',
            'vehicle_types', 'services_offered', 'pricing_info',
            'avg_turnaround_hours', 'working_days', 'cancellation_policy',
            'payment_method', 'account_holder_name', 'account_number', 'provider_name',
            'terms_accepted'
        ]

        for field in mandatory_fields:
            total_fields += 1
            if getattr(self, field):
                filled_fields += 1

        # Additional checks for conditional fields
        if self.garage_type == 'REGISTERED':
            total_fields += 1
            if self.business_registration_cert:
                filled_fields += 1

        if self.warranty_offered:
            total_fields += 1
            if self.warranty_duration_days:
                filled_fields += 1

        self.submission_completeness = (filled_fields / total_fields) * 100 if total_fields > 0 else 0
        super().save(*args, **kwargs)


class GarageServiceRequest(models.Model):
    """Model for when riders request garage services"""
    STATUS_CHOICES = (
        ('PENDING', 'Pending'),
        ('QUOTED', 'Quote Submitted'),
        ('ACCEPTED', 'Accepted'),
        ('DECLINED', 'Declined'),
        ('IN_PROGRESS', 'In Progress'),
        ('COMPLETED', 'Completed'),
        ('CANCELLED', 'Cancelled'),
    )

    rider = models.ForeignKey(User, on_delete=models.CASCADE, related_name='garage_requests')
    garage = models.ForeignKey(Garage, on_delete=models.CASCADE, related_name='service_requests')
    vehicle_type = models.CharField(max_length=20, choices=Garage.VEHICLE_TYPES)
    service_category = models.CharField(max_length=30, choices=Garage.SERVICE_CATEGORIES)
    description = models.TextField(help_text="Description of the mechanical issue")
    preferred_date = models.DateField()
    preferred_time = models.TimeField(blank=True, null=True)
    location_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    location_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING')
    estimated_cost = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    actual_cost = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    response_note = models.TextField(blank=True)
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Garage Request: {self.rider.username} -> {self.garage.name} ({self.status})"


class GarageQuote(models.Model):
    STATUS_CHOICES = (
        ('PENDING', 'Pending member response'),
        ('ACCEPTED', 'Accepted'),
        ('DECLINED', 'Declined'),
        ('REPLACED', 'Replaced'),
    )

    service_request = models.ForeignKey(
        GarageServiceRequest,
        on_delete=models.CASCADE,
        related_name='quotes'
    )
    created_by = models.ForeignKey(
        User,
        on_delete=models.PROTECT,
        related_name='garage_quotes_created'
    )
    revision = models.PositiveIntegerField()
    line_items = models.JSONField()
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    currency = models.CharField(max_length=3, default='MWK')
    scheduled_date = models.DateField()
    scheduled_time = models.TimeField(null=True, blank=True)
    status = models.CharField(max_length=12, choices=STATUS_CHOICES, default='PENDING')
    response_reason = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-revision']
        constraints = [
            models.UniqueConstraint(
                fields=['service_request', 'revision'],
                name='unique_garage_quote_revision'
            )
        ]

    def __str__(self):
        return f"Quote #{self.service_request_id}.{self.revision} ({self.status})"


class GarageInvoice(models.Model):
    STATUS_CHOICES = (
        ('ISSUED', 'Issued'),
        ('PAID', 'Paid'),
        ('SETTLED', 'Settled'),
    )

    quote = models.OneToOneField(
        GarageQuote,
        on_delete=models.PROTECT,
        related_name='invoice'
    )
    invoice_number = models.CharField(max_length=32, unique=True)
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    currency = models.CharField(max_length=3, default='MWK')
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='ISSUED')
    issued_at = models.DateTimeField(default=timezone.now)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-issued_at']

    def __str__(self):
        return self.invoice_number


class GaragePayment(models.Model):
    STATUS_CHOICES = (
        ('PENDING', 'Pending'),
        ('PAID', 'Paid'),
        ('FAILED', 'Failed'),
    )

    invoice = models.ForeignKey(
        GarageInvoice,
        on_delete=models.PROTECT,
        related_name='payments'
    )
    transaction_reference = models.CharField(max_length=64, unique=True)
    provider_reference = models.CharField(max_length=100, blank=True, null=True, unique=True)
    checkout_url = models.URLField(max_length=500, blank=True)
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    currency = models.CharField(max_length=3, default='MWK')
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='PENDING')
    is_excess_payment = models.BooleanField(default=False)
    failure_reason = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    verified_at = models.DateTimeField(null=True, blank=True)
    last_checked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.transaction_reference} ({self.status})"


class GarageSettlement(models.Model):
    invoice = models.ForeignKey(
        GarageInvoice,
        on_delete=models.PROTECT,
        related_name='settlements'
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    settled_by = models.ForeignKey(
        User,
        on_delete=models.PROTECT,
        related_name='garage_settlements_recorded'
    )
    notes = models.TextField(blank=True)
    transfer_reference = models.CharField(max_length=100, unique=True)
    is_final = models.BooleanField(default=False)
    settled_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['-settled_at']

    def __str__(self):
        return f"Settlement for {self.invoice.invoice_number}"


class GarageReview(models.Model):
    service_request = models.OneToOneField(
        GarageServiceRequest,
        on_delete=models.CASCADE,
        related_name='review'
    )
    rider = models.ForeignKey(
        User,
        on_delete=models.PROTECT,
        related_name='garage_reviews'
    )
    rating = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            models.CheckConstraint(
                condition=models.Q(rating__gte=1, rating__lte=5),
                name='garage_review_rating_1_to_5',
            )
        ]

    def __str__(self):
        return f"Review for booking #{self.service_request_id}: {self.rating}/5"


class GarageAuditEvent(models.Model):
    garage = models.ForeignKey(Garage, on_delete=models.CASCADE, related_name='audit_events')
    actor = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='garage_audit_events'
    )
    event_type = models.CharField(max_length=50)
    from_status = models.CharField(max_length=20, blank=True)
    to_status = models.CharField(max_length=20, blank=True)
    reason = models.TextField(blank=True)
    details = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.garage.name}: {self.event_type}"
