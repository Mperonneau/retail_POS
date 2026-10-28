from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash="/?")
router.register("notifications", views.NotificationViewSet, basename="notification")

urlpatterns = router.urls
