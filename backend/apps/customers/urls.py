from apps.common.routers import OptionalSlashRouter

from . import views

router = OptionalSlashRouter()
router.register("customers", views.CustomerViewSet, basename="customer")

urlpatterns = router.urls
