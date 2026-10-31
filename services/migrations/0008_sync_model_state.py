import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("services", "0007_servicetype_category_alter_rodieservice_rodie"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    sql=[
                        """
                        ALTER TABLE services_servicetype
                            ADD COLUMN IF NOT EXISTS has_subcategories boolean NOT NULL DEFAULT false,
                            ADD COLUMN IF NOT EXISTS service_fee numeric(12, 2) NOT NULL DEFAULT 0
                        """,
                        """
                        CREATE TABLE IF NOT EXISTS services_servicesubcategory (
                            id bigserial PRIMARY KEY,
                            name varchar(100) NOT NULL,
                            description text NOT NULL,
                            is_active boolean NOT NULL,
                            "order" integer NOT NULL,
                            created_at timestamp with time zone NOT NULL,
                            updated_at timestamp with time zone NOT NULL,
                            service_id bigint NOT NULL
                                REFERENCES services_servicetype (id) ON DELETE CASCADE,
                            CONSTRAINT services_servicesubcategory_service_id_name_key
                                UNIQUE (service_id, name)
                        )
                        """,
                        """
                        CREATE INDEX IF NOT EXISTS services_servicesubcategory_service_id_55eccf2aa_idx
                            ON services_servicesubcategory (service_id)
                        """,
                        """
                        CREATE UNIQUE INDEX IF NOT EXISTS services_servicesubcategory_service_id_name_key
                            ON services_servicesubcategory (service_id, name)
                        """,
                    ],
                ),
            ],
            state_operations=[
                migrations.AddField(
                    model_name="servicetype",
                    name="has_subcategories",
                    field=models.BooleanField(
                        default=False,
                        help_text="Whether this service has sub-category services",
                    ),
                ),
                migrations.AddField(
                    model_name="servicetype",
                    name="service_fee",
                    field=models.DecimalField(
                        decimal_places=2,
                        default=0,
                        help_text="Service fee charged to Roadies for this service type",
                        max_digits=12,
                    ),
                ),
                migrations.CreateModel(
                    name="ServiceSubCategory",
                    fields=[
                        (
                            "id",
                            models.BigAutoField(
                                auto_created=True,
                                primary_key=True,
                                serialize=False,
                                verbose_name="ID",
                            ),
                        ),
                        ("name", models.CharField(max_length=100)),
                        ("description", models.TextField(blank=True, default="")),
                        ("is_active", models.BooleanField(default=True)),
                        ("order", models.PositiveIntegerField(default=0)),
                        (
                            "created_at",
                            models.DateTimeField(
                                default=django.utils.timezone.now,
                                editable=False,
                            ),
                        ),
                        ("updated_at", models.DateTimeField(auto_now=True)),
                        (
                            "service",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="subcategories",
                                to="services.servicetype",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["order", "name"],
                        "unique_together": {("service", "name")},
                    },
                ),
            ],
        ),
    ]
