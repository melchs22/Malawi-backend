from django.urls import path, include
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)
from .views import RegisterView, MeView, MyWalletView, MyReferralsView, RoadieStatusUpdateView, PlatformConfigView, NotificationListCreateView, NotificationRUDView, DepositView, WithdrawView, PesapalIPNView, RoadiePaymentsView, PaymentStatusView, UserProfileUpdateView, RegisterFcmTokenView, UserProfilePhotoUploadView, UserProfilePasswordChangeView, submit_feedback, PasswordResetRequestView, PasswordResetConfirmView, AccountDeletionEligibilityView, RequestAccountDeletionView
from .tokens import CustomTokenObtainPairView, RiderLoginView, RoadieLoginView, WorkshopLoginView
from .admin_views import (
    RiderListCreateView,
    RiderRetrieveUpdateDestroyView,
    RoadieListCreateView,
    RoadieRetrieveUpdateDestroyView,
    RealtimeRidersView,
    AdminListCreateView,
    AdminRetrieveUpdateDestroyView,
    AdminDeletedUsersView,
    AdminDeletedRidersView,
    AdminDeletedRoadiesView,
    AdminRestoreUserView,
    AdminPendingDeletionListView,
    AdminPermanentDeleteUserView,
    AdminNotificationListCreateView,
    AdminNotificationRUDView,
    AdminRegisterView,
    AdminWalletListCreateView,
    AdminWalletRUDView,
    AdminReferralListCreateView,
    AdminReferralRUDView,
    AdminPlatformConfigView,
    AdminUserPasswordView,
    RoadieOnlineTimeFleetView,
    RoadieOnlineTimeDetailView,
    AdminWithdrawalListView,
    AdminWithdrawalDetailView,
)
from .support_views import (
    SupportTicketViewSet,
    AdminAuditLogViewSet,
    NotificationHistoryViewSet,
    ReferralViewSet,
    ReferralSummaryViewSet,
)
from services.admin_views import (
    ServiceTypeListCreateView,
    ServiceTypeRetrieveUpdateDestroyView,
    RodieServiceListCreateView,
    RodieServiceRetrieveUpdateDestroyView,
)
from services.views import RodieMyServicesView, RodieInitialServiceSelectionView
from service_requests.admin_views import (
    ServiceRequestListCreateView,
    ServiceRequestRetrieveUpdateDestroyView,
    RealtimeRiderLocationsView,
    RealtimeRiderMapView,
    ServiceRequestRouteView,
    AdminAssignRodieView,
    JobsPerformanceReportView,
)
from locations.admin_views import (
    RealtimeLocationsView,
    RealtimeLocationsMapView,
)
from .admin_auth import AdminTokenObtainPairView
from rest_framework.routers import DefaultRouter

# Create router for viewsets
router = DefaultRouter()
router.register(r'auth/admin/support-tickets', SupportTicketViewSet, basename='support-ticket')
router.register(r'auth/admin/audit-logs', AdminAuditLogViewSet, basename='audit-log')
router.register(r'auth/admin/notification-history', NotificationHistoryViewSet, basename='notification-history')
router.register(r'auth/admin/referrals', ReferralViewSet, basename='referral')
router.register(r'auth/admin/referral-summaries', ReferralSummaryViewSet, basename='referral-summary')

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', CustomTokenObtainPairView.as_view(), name='login'),
    path('login/rider/', RiderLoginView.as_view(), name='rider_login'),
    path('login/roadie/', RoadieLoginView.as_view(), name='roadie_login'),
    path('login/workshop/', WorkshopLoginView.as_view(), name='workshop_login'),
    path('refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    # Images alias (for KYC and profile)
    path('images/', include('images.urls')),
    path('auth/password-reset/', PasswordResetRequestView.as_view(), name='password_reset_request'),
    path('auth/password-reset/confirm/', PasswordResetConfirmView.as_view(), name='password_reset_confirm'),
    path('me/', MeView.as_view(), name='me'),
    path('profile/', UserProfileUpdateView.as_view(), name='user_profile_update'),
    path('profile/fcm-token/', RegisterFcmTokenView.as_view(), name='user_profile_fcm_token'),
    path('profile/photo/', UserProfilePhotoUploadView.as_view(), name='user_profile_photo_upload'),
    path('profile/change-password/', UserProfilePasswordChangeView.as_view(), name='user_profile_password_change'),
    path('profile/deletion-eligibility/', AccountDeletionEligibilityView.as_view(), name='deletion_eligibility'),
    path('profile/request-deletion/', RequestAccountDeletionView.as_view(), name='request_deletion'),
    path('wallet/', MyWalletView.as_view(), name='my_wallet'),
    path('wallet/deposit/', DepositView.as_view(), name='wallet_deposit'),
    path('wallet/withdraw/', WithdrawView.as_view(), name='wallet_withdraw'),
    path('roadie/payments/', RoadiePaymentsView.as_view(), name='roadie_payments'),
    path('payments/status/<str:reference>/', PaymentStatusView.as_view(), name='payment_status'),
    path('pesapal/ipn/', PesapalIPNView.as_view(), name='pesapal_ipn'),
    path('referrals/', MyReferralsView.as_view(), name='my_referrals'),
    path('users/referrals/', MyReferralsView.as_view(), name='my_referrals_alias'),
    path('roadie/status/', RoadieStatusUpdateView.as_view(), name='roadie_status_update'),
    path('auth/platform/config/', PlatformConfigView.as_view(), name='platform_config'),
    path('notifications/', NotificationListCreateView.as_view(), name='my_notifications'),
    path('notifications/<int:pk>/', NotificationRUDView.as_view(), name='my_notifications_rud'),
    path('feedback/', submit_feedback, name='submit_feedback'),
    path('auth/admin/login/', AdminTokenObtainPairView.as_view(), name='admin_login'),
    path('auth/admin/register/', AdminRegisterView.as_view(), name='admin_register'),
    path('auth/admin/riders/', RiderListCreateView.as_view(), name='admin_riders_list_create'),
    path('auth/admin/riders/<int:pk>/', RiderRetrieveUpdateDestroyView.as_view(), name='admin_riders_rud'),
    path('auth/admin/roadies/', RoadieListCreateView.as_view(), name='admin_roadies_list_create'),
    path('auth/admin/roadies/<int:pk>/', RoadieRetrieveUpdateDestroyView.as_view(), name='admin_roadies_rud'),
    path('auth/admin/roadies/online-time/summary/', RoadieOnlineTimeFleetView.as_view(), name='admin_roadies_online_time_summary'),
    path('auth/admin/roadies/<int:pk>/online-time/', RoadieOnlineTimeDetailView.as_view(), name='admin_roadies_online_time_detail'),
    path('auth/admin/riders/realtime/', RealtimeRidersView.as_view(), name='admin_riders_realtime'),
    path('auth/admin/users/', AdminListCreateView.as_view(), name='admin_users_list_create'),
    path('auth/admin/users/<int:pk>/', AdminRetrieveUpdateDestroyView.as_view(), name='admin_users_rud'),
    path('auth/admin/users/deleted/', AdminDeletedUsersView.as_view(), name='admin_users_deleted'),
    path('auth/admin/riders/deleted/', AdminDeletedRidersView.as_view(), name='admin_riders_deleted'),
    path('auth/admin/roadies/deleted/', AdminDeletedRoadiesView.as_view(), name='admin_roadies_deleted'),
    path('auth/admin/users/pending-deletions/', AdminPendingDeletionListView.as_view(), name='admin_users_pending_deletion'),
    path('auth/admin/users/<int:pk>/restore/', AdminRestoreUserView.as_view(), name='admin_user_restore'),
    path('auth/admin/users/<int:pk>/permanent-delete/<str:role>/', AdminPermanentDeleteUserView.as_view(), name='admin_user_permanent_delete'),
    path('auth/admin/services/', ServiceTypeListCreateView.as_view(), name='admin_services_list_create'),
    path('auth/admin/services/<int:pk>/', ServiceTypeRetrieveUpdateDestroyView.as_view(), name='admin_services_rud'),
    path('auth/admin/rodie-services/', RodieServiceListCreateView.as_view(), name='admin_rodie_services_list_create'),
    path('auth/admin/rodie-services/<int:pk>/', RodieServiceRetrieveUpdateDestroyView.as_view(), name='admin_rodie_services_rud'),
    path('auth/rodie/services/', RodieMyServicesView.as_view(), name='rodie_my_services'),
    path('auth/rodie/services/initial/', RodieInitialServiceSelectionView.as_view(), name='rodie_initial_service_selection'),
    path('auth/admin/requests/', ServiceRequestListCreateView.as_view(), name='admin_requests_list_create'),
    path('auth/admin/requests/<int:pk>/', ServiceRequestRetrieveUpdateDestroyView.as_view(), name='admin_requests_rud'),
    path('auth/admin/requests/realtime/', RealtimeRiderLocationsView.as_view(), name='admin_requests_realtime'),
    path('auth/admin/requests/realtime/map/', RealtimeRiderMapView.as_view(), name='admin_requests_realtime_map'),
    path('auth/admin/requests/<int:pk>/route/', ServiceRequestRouteView.as_view(), name='admin_request_route'),
    path('auth/admin/locations/realtime/', RealtimeLocationsView.as_view(), name='admin_locations_realtime'),
    path('auth/admin/locations/realtime/map/', RealtimeLocationsMapView.as_view(), name='admin_locations_realtime_map'),
    path('auth/admin/wallets/', AdminWalletListCreateView.as_view(), name='admin_wallets_list_create'),
    path('auth/admin/wallets/<int:pk>/', AdminWalletRUDView.as_view(), name='admin_wallets_rud'),
    path('auth/admin/referrals/', AdminReferralListCreateView.as_view(), name='admin_referrals_list_create'),
    path('auth/admin/referrals/<int:pk>/', AdminReferralRUDView.as_view(), name='admin_referrals_rud'),
    path('auth/admin/platform/config/', AdminPlatformConfigView.as_view(), name='admin_platform_config'),
    path('auth/admin/notifications/', AdminNotificationListCreateView.as_view(), name='admin_notifications_list_create'),
    path('auth/admin/notifications/<int:pk>/', AdminNotificationRUDView.as_view(), name='admin_notifications_rud'),
    path('auth/admin/users/<int:pk>/password/', AdminUserPasswordView.as_view(), name='admin_user_password_change'),
    path('auth/admin/requests/<int:pk>/assign/', AdminAssignRodieView.as_view(), name='admin_request_assign'),
    path('auth/admin/reports/jobs-performance/', JobsPerformanceReportView.as_view(), name='admin_jobs_performance_report'),
    path('auth/admin/withdrawals/', AdminWithdrawalListView.as_view(), name='admin_withdrawals_list'),
    path('auth/admin/withdrawals/<int:pk>/', AdminWithdrawalDetailView.as_view(), name='admin_withdrawals_detail'),
]

# Add router URLs
urlpatterns += router.urls
