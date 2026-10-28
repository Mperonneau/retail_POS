from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash="/?")
router.register("staff", views.StaffViewSet, basename="staff")
router.register("devices", views.DeviceViewSet, basename="device")
router.register("locations", views.LocationViewSet, basename="location")

urlpatterns = [
    path("auth/register", views.RegisterView.as_view()),
    path("auth/session", views.OwnerSessionView.as_view()),
    path("auth/pin", views.PinUnlockView.as_view()),
    path("auth/me", views.MeView.as_view()),
    path("auth/logout", views.LogoutView.as_view()),
    path("devices/pair", views.PairDeviceView.as_view()),
    path("devices/verify", views.DeviceVerifyView.as_view()),
    path("business", views.BusinessView.as_view()),
    path("business/settings", views.BusinessSettingsView.as_view()),
    path("business/exchange-rate", views.ExchangeRateView.as_view()),
    path("business/discount-code/check", views.DiscountCodeCheckView.as_view()),
    *router.urls,
]
