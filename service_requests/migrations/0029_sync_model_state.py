from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("service_requests", "0028_dispute_alter_chatmessage_options_and_more"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    sql=[
                        """
                        DO $migration$
                        BEGIN
                            IF to_regclass('public.service_requests_cancellationreason') IS NOT NULL
                               AND to_regclass('public.requests_cancellationreason') IS NULL THEN
                                ALTER TABLE service_requests_cancellationreason
                                    RENAME TO requests_cancellationreason;
                            END IF;
                            IF to_regclass('public.service_requests_chatmessage') IS NOT NULL
                               AND to_regclass('public.requests_chatmessage') IS NULL THEN
                                ALTER TABLE service_requests_chatmessage
                                    RENAME TO requests_chatmessage;
                            END IF;
                            IF to_regclass('public.service_requests_dispute') IS NOT NULL
                               AND to_regclass('public.requests_dispute') IS NULL THEN
                                ALTER TABLE service_requests_dispute
                                    RENAME TO requests_dispute;
                            END IF;
                            IF to_regclass('public.service_requests_rating') IS NOT NULL
                               AND to_regclass('public.requests_rating') IS NULL THEN
                                ALTER TABLE service_requests_rating
                                    RENAME TO requests_rating;
                            END IF;
                            IF to_regclass('public.service_requests_requestcancellation') IS NOT NULL
                               AND to_regclass('public.requests_requestcancellation') IS NULL THEN
                                ALTER TABLE service_requests_requestcancellation
                                    RENAME TO requests_requestcancellation;
                            END IF;
                            IF to_regclass('public.service_requests_servicerequest') IS NOT NULL
                               AND to_regclass('public.requests_servicerequest') IS NULL THEN
                                ALTER TABLE service_requests_servicerequest
                                    RENAME TO requests_servicerequest;
                            END IF;
                        END
                        $migration$
                        """,
                        """
                        ALTER TABLE requests_servicerequest
                            ADD COLUMN IF NOT EXISTS additional_notes text NULL,
                            ADD COLUMN IF NOT EXISTS service_fee_amount numeric(12, 2) NULL,
                            ADD COLUMN IF NOT EXISTS show_rider_username boolean NOT NULL DEFAULT true,
                            ADD COLUMN IF NOT EXISTS show_rodie_username boolean NOT NULL DEFAULT true
                        """,
                        """
                        DO $migration$
                        BEGIN
                            IF to_regclass('public.requests_ra_service_idx') IS NOT NULL
                               AND to_regclass('public.requests_ra_service_c01108_idx') IS NULL THEN
                                ALTER INDEX requests_ra_service_idx
                                    RENAME TO requests_ra_service_c01108_idx;
                            END IF;
                            IF to_regclass('public.requests_ra_rated_u_idx') IS NOT NULL
                               AND to_regclass('public.requests_ra_rated_u_58b232_idx') IS NULL THEN
                                ALTER INDEX requests_ra_rated_u_idx
                                    RENAME TO requests_ra_rated_u_58b232_idx;
                            END IF;
                        END
                        $migration$
                        """,
                    ],
                ),
            ],
            state_operations=[
                migrations.RenameIndex(
                    model_name="rating",
                    new_name="requests_ra_service_c01108_idx",
                    old_name="requests_ra_service_idx",
                ),
                migrations.RenameIndex(
                    model_name="rating",
                    new_name="requests_ra_rated_u_58b232_idx",
                    old_name="requests_ra_rated_u_idx",
                ),
                migrations.AddField(
                    model_name="servicerequest",
                    name="additional_notes",
                    field=models.TextField(blank=True, null=True),
                ),
                migrations.AddField(
                    model_name="servicerequest",
                    name="service_fee_amount",
                    field=models.DecimalField(
                        blank=True,
                        decimal_places=2,
                        help_text="Service fee deducted from Roadie wallet for this request",
                        max_digits=12,
                        null=True,
                    ),
                ),
                migrations.AddField(
                    model_name="servicerequest",
                    name="show_rider_username",
                    field=models.BooleanField(default=True),
                ),
                migrations.AddField(
                    model_name="servicerequest",
                    name="show_rodie_username",
                    field=models.BooleanField(default=True),
                ),
                migrations.AlterModelTable(
                    name="cancellationreason",
                    table="requests_cancellationreason",
                ),
                migrations.AlterModelTable(
                    name="chatmessage",
                    table="requests_chatmessage",
                ),
                migrations.AlterModelTable(
                    name="dispute",
                    table="requests_dispute",
                ),
                migrations.AlterModelTable(
                    name="rating",
                    table="requests_rating",
                ),
                migrations.AlterModelTable(
                    name="requestcancellation",
                    table="requests_requestcancellation",
                ),
                migrations.AlterModelTable(
                    name="servicerequest",
                    table="requests_servicerequest",
                ),
            ],
        ),
    ]
