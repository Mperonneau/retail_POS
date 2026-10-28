from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash="/?")
router.register("customers", views.CustomerViewSet, basename="customer")

urlpatterns = router.urls
