from rest_framework.permissions import BasePermission


class IsPlatformAdmin(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (
                user.is_staff
                or user.is_superuser
                or getattr(user, 'role', None) == 'ADMIN'
            )
        )


class IsRider(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and getattr(user, 'role', None) == 'RIDER'
        )


class IsWorkshopOwner(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and getattr(user, 'role', None) == 'WORKSHOP'
            and hasattr(user, 'owned_garage')
            and user.owned_garage.verification_status == 'VERIFIED'
        )

    def has_object_permission(self, request, view, obj):
        garage = getattr(obj, 'garage', None)
        if garage is None:
            garage = getattr(obj, 'service_request', None)
            garage = getattr(garage, 'garage', None)
        return bool(garage and garage.owner_user_id == request.user.id)
