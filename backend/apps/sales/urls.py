from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash="/?")
router.register("orders", views.OrderViewSet, basename="order")
router.register("checks", views.CheckViewSet, basename="check")
router.register("quotes", views.QuoteViewSet, basename="quote")

urlpatterns = router.urls
