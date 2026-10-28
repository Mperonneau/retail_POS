from apps.common.routers import OptionalSlashRouter

from . import views

router = OptionalSlashRouter()
router.register("cash/sessions", views.CashSessionViewSet, basename="cash-session")

urlpatterns = router.urls
