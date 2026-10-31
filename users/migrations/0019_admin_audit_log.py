import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0018_passwordresettoken_alter_notification_options_and_more"),
    ]

    operations = [
        migrations.CreateModel(
            name="AdminAuditLog",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "action_type",
                    models.CharField(
                        choices=[
                            ("USER_CREATE", "User Created"),
                            ("USER_UPDATE", "User Updated"),
                            ("USER_DELETE", "User Deleted"),
                            ("USER_APPROVE", "User Approved"),
                            ("USER_DEACTIVATE", "User Deactivated"),
                            ("ADMIN_CREATE", "Admin Created"),
                            ("ADMIN_DELETE", "Admin Deleted"),
                            ("SERVICE_CREATE", "Service Created"),
                            ("SERVICE_UPDATE", "Service Updated"),
                            ("SERVICE_DELETE", "Service Deleted"),
                            ("REQUEST_CANCEL", "Request Cancelled"),
                            ("WALLET_ADJUST", "Wallet Adjusted"),
                            ("PAYMENT_PROCESS", "Payment Processed"),
                            ("SUPPORT_UPDATE", "Support Ticket Updated"),
                            ("DISPUTE_RESOLVE", "Dispute Resolved"),
                            ("CONFIG_UPDATE", "Config Updated"),
                            ("NOTIFICATION_SEND", "Notification Sent"),
                            ("OTHER", "Other"),
                        ],
                        max_length=50,
                    ),
                ),
                ("action_description", models.TextField()),
                (
                    "target_entity_type",
                    models.CharField(
                        blank=True,
                        help_text="Type of entity affected (User, Service, Request, etc.)",
                        max_length=50,
                    ),
                ),
                (
                    "target_entity_id",
                    models.CharField(
                        blank=True,
                        help_text="ID of the entity affected",
                        max_length=100,
                    ),
                ),
                ("changes", models.JSONField(blank=True, default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("ip_address", models.GenericIPAddressField(blank=True, null=True)),
                (
                    "admin_user",
                    models.ForeignKey(
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="audit_logs_created",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "target_user",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="audit_logs_targeting",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
                "indexes": [
                    models.Index(
                        fields=["admin_user", "-created_at"],
                        name="users_admin_admin_u_d02db6_idx",
                    ),
                    models.Index(
                        fields=["action_type", "-created_at"],
                        name="users_admin_action__9808fb_idx",
                    ),
                ],
            },
        ),
    ]
