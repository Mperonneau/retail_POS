from apps.common.routers import OptionalSlashRouter

from . import views

router = OptionalSlashRouter()
router.register("timeclock", views.TimeclockViewSet, basename="timeclock")

urlpatterns = router.urls
