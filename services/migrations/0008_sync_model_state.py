import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("services", "0007_servicetype_category_alter_rodieservice_rodie"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[],
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
