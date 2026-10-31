from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("service_requests", "0028_dispute_alter_chatmessage_options_and_more"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    sql="ALTER INDEX requests_ra_service_idx RENAME TO requests_ra_service_c01108_idx",
                    reverse_sql="ALTER INDEX requests_ra_service_c01108_idx RENAME TO requests_ra_service_idx",
                ),
                migrations.RunSQL(
                    sql="ALTER INDEX requests_ra_rated_u_idx RENAME TO requests_ra_rated_u_58b232_idx",
                    reverse_sql="ALTER INDEX requests_ra_rated_u_58b232_idx RENAME TO requests_ra_rated_u_idx",
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
