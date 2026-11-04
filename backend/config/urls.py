from django.conf import settings
from django.contrib import admin
from django.urls import include, path, re_path

from apps.catalog_import import views as import_views
from apps.payments import legacy
from apps.payments.views import StripeWebhookView
from apps.storefront.urls import public_urlpatterns, staff_urlpatterns

api_v1 = [
    path("", include("apps.accounts.urls")),
    path("", include("apps.catalog.urls")),
    path("", include("apps.customers.urls")),
    path("", include("apps.sales.urls")),
    path("", include("apps.payments.urls")),
    path("", include("apps.cash.urls")),
    path("", include("apps.timeclock.urls")),
    path("", include("apps.notifications.urls")),
    path("", include("apps.reports.urls")),
    path("", include("apps.sync.urls")),
    path("", include(staff_urlpatterns)),
    path("catalog/imports", import_views.ImportJobsView.as_view()),
    path("catalog/imports/<str:job_id>", import_views.ImportJobView.as_view()),
    path("catalog/imports/<str:job_id>/apply", import_views.ImportApplyView.as_view()),
]

# Same paths and payloads as the payments/vitrine server, so the current
# apps can point here without a rebuild.
legacy_routes = [
    re_path(r"^health/?$", legacy.HealthView.as_view()),
    re_path(r"^config/?$", legacy.LegacyConfigView.as_view()),
    re_path(r"^payments/checkout/?$", legacy.LegacyCheckoutView.as_view()),
    re_path(r"^payments/checkout/(?P<session_id>[^/]+)/?$", legacy.LegacyCheckoutView.as_view()),
    re_path(r"^payments/intent/?$", legacy.LegacyIntentView.as_view()),
    re_path(r"^payments/intent/(?P<intent_id>[^/]+)/?$", legacy.LegacyIntentView.as_view()),
    re_path(r"^payments/moncash/?$", legacy.LegacyMonCashView.as_view()),
    re_path(r"^payments/moncash/(?P<order_id>[^/]+)/?$", legacy.LegacyMonCashView.as_view()),
    re_path(r"^payments/webhook/?$", StripeWebhookView.as_view()),
    re_path(r"^paid/?$", legacy.paid_page),
    re_path(r"^cancel/?$", legacy.cancel_page),
    re_path(r"^catalog/imports/?$", import_views.LegacyImportJobsView.as_view()),
    re_path(r"^catalog/imports/(?P<job_id>[^/]+)/?$", import_views.LegacyImportJobView.as_view()),
    path("storefront/", include(public_urlpatterns)),
]

urlpatterns = [path("api/v1/", include(api_v1)), *legacy_routes]

if settings.ADMIN_URL:
    urlpatterns.append(path(settings.ADMIN_URL, admin.site.urls))
