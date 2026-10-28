from apps.common.routers import OptionalSlashRouter

from . import views

router = OptionalSlashRouter()
router.register("orders", views.OrderViewSet, basename="order")
router.register("checks", views.CheckViewSet, basename="check")
router.register("quotes", views.QuoteViewSet, basename="quote")

urlpatterns = router.urls
