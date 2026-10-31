import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0019_admin_audit_log"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    sql=[
                        """
                        ALTER TABLE users_notification
                            ADD COLUMN IF NOT EXISTS url varchar(200) NULL
                        """,
                        """
                        CREATE TABLE IF NOT EXISTS users_referralsummary (
                            id bigserial PRIMARY KEY,
                            total_referrals integer NOT NULL DEFAULT 0,
                            successful_referrals integer NOT NULL DEFAULT 0,
                            pending_referrals integer NOT NULL DEFAULT 0,
                            total_rewards_paid numeric(12, 2) NOT NULL DEFAULT 0,
                            pending_rewards numeric(12, 2) NOT NULL DEFAULT 0,
                            updated_at timestamp with time zone NOT NULL,
                            user_id bigint NOT NULL UNIQUE
                                REFERENCES users_user (id) ON DELETE CASCADE
                        )
                        """,
                        """
                        CREATE TABLE IF NOT EXISTS users_rodieavailabilitylog (
                            id bigserial PRIMARY KEY,
                            went_online_at timestamp with time zone NOT NULL,
                            went_offline_at timestamp with time zone NULL,
                            device_type varchar(10) NULL,
                            user_id bigint NOT NULL
                                REFERENCES users_user (id) ON DELETE CASCADE
                        )
                        """,
                        """
                        CREATE TABLE IF NOT EXISTS users_notificationhistory (
                            id bigserial PRIMARY KEY,
                            delivery_status varchar(20) NOT NULL DEFAULT 'PENDING',
                            delivery_error text NULL,
                            was_opened boolean NOT NULL DEFAULT false,
                            opened_at timestamp with time zone NULL,
                            sent_at timestamp with time zone NOT NULL,
                            updated_at timestamp with time zone NOT NULL,
                            notification_id bigint NOT NULL
                                REFERENCES users_notification (id) ON DELETE CASCADE,
                            recipient_id bigint NULL
                                REFERENCES users_user (id) ON DELETE SET NULL
                        )
                        """,
                        """
                        CREATE TABLE IF NOT EXISTS users_supportticket (
                            id bigserial PRIMARY KEY,
                            support_id varchar(20) NOT NULL UNIQUE,
                            user_type varchar(10) NOT NULL,
                            subject varchar(200) NOT NULL,
                            message text NOT NULL,
                            status varchar(20) NOT NULL DEFAULT 'PENDING',
                            internal_comments text NULL,
                            created_at timestamp with time zone NOT NULL,
                            updated_at timestamp with time zone NOT NULL,
                            resolved_at timestamp with time zone NULL,
                            user_id bigint NOT NULL
                                REFERENCES users_user (id) ON DELETE CASCADE
                        )
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_rodieavailabilitylog_user_id_idx
                            ON users_rodieavailabilitylog (user_id)
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_notificationhistory_notification_id_idx
                            ON users_notificationhistory (notification_id)
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_notificationhistory_recipient_id_idx
                            ON users_notificationhistory (recipient_id)
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_notif_recipie_ebd058_idx
                            ON users_notificationhistory (recipient_id, sent_at DESC)
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_notif_deliver_a61467_idx
                            ON users_notificationhistory (delivery_status, sent_at DESC)
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_supportticket_user_id_idx
                            ON users_supportticket (user_id)
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_suppo_status_a385e1_idx
                            ON users_supportticket (status, created_at DESC)
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS users_suppo_user_ty_e7c7ba_idx
                            ON users_supportticket (user_type, created_at DESC)
                        """,
                    ],
                ),
            ],
            state_operations=[
                migrations.RemoveField(
                    model_name="platformconfig",
                    name="service_fee",
                ),
                migrations.AddField(
                    model_name="notification",
                    name="url",
                    field=models.URLField(
                        blank=True,
                        help_text="Optional deep link or external URL for the notification",
                        null=True,
                    ),
                ),
                migrations.AlterField(
                    model_name="user",
                    name="current_login_id",
                    field=models.UUIDField(
                        blank=True,
                        default=uuid.uuid4,
                        help_text="Used to enforce single device login",
                        null=True,
                    ),
                ),
                migrations.AlterField(
                    model_name="user",
                    name="role",
                    field=models.CharField(
                        choices=[
                            ("RIDER", "Rider"),
                            ("RODIE", "Rodie"),
                            ("MECHANIC", "Mechanic"),
                            ("WORKSHOP", "Workshop"),
                            ("ADMIN", "Admin"),
                        ],
                        max_length=10,
                    ),
                ),
                migrations.CreateModel(
                    name="ReferralSummary",
                    fields=[
                        ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                        ("total_referrals", models.IntegerField(default=0)),
                        ("successful_referrals", models.IntegerField(default=0)),
                        ("pending_referrals", models.IntegerField(default=0)),
                        ("total_rewards_paid", models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                        ("pending_rewards", models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                        ("updated_at", models.DateTimeField(auto_now=True)),
                        (
                            "user",
                            models.OneToOneField(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="referral_summary",
                                to=settings.AUTH_USER_MODEL,
                            ),
                        ),
                    ],
                ),
                migrations.CreateModel(
                    name="RodieAvailabilityLog",
                    fields=[
                        ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                        ("went_online_at", models.DateTimeField()),
                        ("went_offline_at", models.DateTimeField(blank=True, null=True)),
                        (
                            "device_type",
                            models.CharField(
                                blank=True,
                                choices=[("IOS", "iOS"), ("ANDROID", "Android")],
                                max_length=10,
                                null=True,
                            ),
                        ),
                        (
                            "user",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="rodie_availability_logs",
                                to=settings.AUTH_USER_MODEL,
                            ),
                        ),
                    ],
                ),
                migrations.CreateModel(
                    name="NotificationHistory",
                    fields=[
                        ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                        (
                            "delivery_status",
                            models.CharField(
                                choices=[
                                    ("PENDING", "Pending"),
                                    ("SENT", "Sent"),
                                    ("FAILED", "Failed"),
                                    ("DELIVERED", "Delivered"),
                                ],
                                default="PENDING",
                                max_length=20,
                            ),
                        ),
                        ("delivery_error", models.TextField(blank=True, null=True)),
                        ("was_opened", models.BooleanField(default=False)),
                        ("opened_at", models.DateTimeField(blank=True, null=True)),
                        ("sent_at", models.DateTimeField(auto_now_add=True)),
                        ("updated_at", models.DateTimeField(auto_now=True)),
                        (
                            "notification",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="history",
                                to="users.notification",
                            ),
                        ),
                        (
                            "recipient",
                            models.ForeignKey(
                                blank=True,
                                null=True,
                                on_delete=django.db.models.deletion.SET_NULL,
                                related_name="notification_history",
                                to=settings.AUTH_USER_MODEL,
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["-sent_at"],
                        "indexes": [
                            models.Index(
                                fields=["recipient", "-sent_at"],
                                name="users_notif_recipie_ebd058_idx",
                            ),
                            models.Index(
                                fields=["delivery_status", "-sent_at"],
                                name="users_notif_deliver_a61467_idx",
                            ),
                        ],
                    },
                ),
                migrations.CreateModel(
                    name="SupportTicket",
                    fields=[
                        ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                        ("support_id", models.CharField(max_length=20, unique=True)),
                        (
                            "user_type",
                            models.CharField(
                                choices=[("RIDER", "Rider"), ("RODIE", "Roadie")],
                                help_text="Whether the ticket is from a Rider or Roadie",
                                max_length=10,
                            ),
                        ),
                        ("subject", models.CharField(blank=True, max_length=200)),
                        ("message", models.TextField()),
                        (
                            "status",
                            models.CharField(
                                choices=[
                                    ("PENDING", "Pending"),
                                    ("ONGOING", "Ongoing"),
                                    ("RESOLVED", "Resolved"),
                                ],
                                default="PENDING",
                                max_length=20,
                            ),
                        ),
                        ("internal_comments", models.TextField(blank=True, null=True)),
                        ("created_at", models.DateTimeField(auto_now_add=True)),
                        ("updated_at", models.DateTimeField(auto_now=True)),
                        ("resolved_at", models.DateTimeField(blank=True, null=True)),
                        (
                            "user",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="support_tickets",
                                to=settings.AUTH_USER_MODEL,
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["-created_at"],
                        "indexes": [
                            models.Index(
                                fields=["status", "-created_at"],
                                name="users_suppo_status_a385e1_idx",
                            ),
                            models.Index(
                                fields=["user_type", "-created_at"],
                                name="users_suppo_user_ty_e7c7ba_idx",
                            ),
                        ],
                    },
                ),
            ],
        ),
    ]
