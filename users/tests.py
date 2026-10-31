from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APITestCase
from rest_framework import status
from .models import AdminAuditLog, User


class AdminAuditLogApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username="audit-admin",
            email="audit-admin@example.com",
            password="test-password",
            role="ADMIN",
            phone="+265991234567",
            external_id="ADMIN-AUDIT-TEST",
        )
        self.client.force_authenticate(user=self.admin)
        self.url = reverse("audit-log-list")

    def test_admin_can_create_and_read_audit_log_with_old_and_new_values(self):
        response = self.client.post(
            self.url,
            {
                "action_type": "Disable User",
                "action_description": "Updated rider approval status",
                "target_entity_type": "User",
                "target_entity_id": "42",
                "changes": {
                    "old": {"is_approved": False},
                    "new": {"is_approved": True},
                },
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["admin_username"], self.admin.username)
        self.assertEqual(
            response.data["changes"],
            {"old": {"is_approved": False}, "new": {"is_approved": True}},
        )
        self.assertEqual(AdminAuditLog.objects.count(), 1)

        list_response = self.client.get(self.url)
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        self.assertEqual(list_response.data["results"][0]["action_description"], "Updated rider approval status")

    def test_audit_log_changes_must_be_an_object(self):
        response = self.client.post(
            self.url,
            {
                "action_type": "Disable User",
                "action_description": "Updated rider",
                "changes": ["not", "an", "object"],
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(AdminAuditLog.objects.count(), 0)
