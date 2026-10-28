from apps.common.routers import OptionalSlashRouter

from . import views

router = OptionalSlashRouter()
router.register("notifications", views.NotificationViewSet, basename="notification")

urlpatterns = router.urls
