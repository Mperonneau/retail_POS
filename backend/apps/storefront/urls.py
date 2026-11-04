from django.urls import path, re_path

from . import views

# Mounted at /storefront/ (same paths as the vitrine server).
public_urlpatterns = [
    re_path(r"^shops/?$", views.DirectoryView.as_view()),
    re_path(r"^shops/(?P<slug>[^/]+)/requests/?$", views.CreateRequestView.as_view()),
    re_path(r"^shops/(?P<slug>[^/]+)/?$", views.PublicShopView.as_view()),
    re_path(r"^photos/(?P<name>[^/]+)$", views.PhotoView.as_view()),
    re_path(r"^requests/(?P<request_id>[^/]+)/card/confirm/?$", views.CardConfirmView.as_view()),
    re_path(r"^requests/(?P<request_id>[^/]+)/card/?$", views.CardIntentView.as_view()),
    re_path(r"^requests/(?P<request_id>[^/]+)/moncash/?$", views.MonCashView.as_view()),
    re_path(r"^requests/(?P<request_id>[^/]+)/?$", views.RequestView.as_view()),
    re_path(r"^account/?$", views.AccountView.as_view()),
    re_path(r"^account/orders/?$", views.AccountOrdersView.as_view()),
    re_path(r"^account/code/?$", views.AccountCodeView.as_view()),
    re_path(r"^account/verify/?$", views.AccountVerifyView.as_view()),
    re_path(r"^account/register/?$", views.AccountRegisterView.as_view()),
    re_path(r"^account/login/?$", views.AccountLoginView.as_view()),
    re_path(r"^shop/publish/?$", views.LegacyPublishView.as_view()),
    re_path(r"^shop/requests/?$", views.LegacyShopRequestView.as_view()),
    re_path(r"^shop/inbox/?$", views.LegacyInboxView.as_view()),
    re_path(r"^shop/slug/?$", views.LegacySlugView.as_view()),
]

# Mounted at /api/v1/.
staff_urlpatterns = [
    path("storefront/shop", views.StaffShopView.as_view()),
    path("storefront/shop/key", views.StaffShopKeyView.as_view()),
    path("storefront/shop/slug", views.StaffSlugView.as_view()),
    path("storefront/requests", views.StaffRequestsView.as_view()),
    path("storefront/requests/<str:request_id>", views.StaffRequestDetailView.as_view()),
    path("storefront/requests/<str:request_id>/<str:op>", views.StaffRequestDetailView.as_view()),
]
