from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash="/?")
router.register("cash/sessions", views.CashSessionViewSet, basename="cash-session")

urlpatterns = router.urls
