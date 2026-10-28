from django.urls import path
from apps.common.routers import OptionalSlashRouter

from . import views

router = OptionalSlashRouter()
router.register("paylinks", views.PayLinkViewSet, basename="paylink")

urlpatterns = [
    path("payments/config", views.ConfigView.as_view()),
    path("payments/card-intents", views.CardIntentView.as_view()),
    path("payments/card-intents/<str:intent_id>", views.CardIntentView.as_view()),
    path("payments/moncash", views.MonCashView.as_view()),
    path("payments/moncash/<str:order_id>", views.MonCashView.as_view()),
    path("payments/webhook/stripe", views.StripeWebhookView.as_view()),
] + router.urls
