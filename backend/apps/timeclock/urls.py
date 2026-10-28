from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash="/?")
router.register("timeclock", views.TimeclockViewSet, basename="timeclock")

urlpatterns = router.urls
