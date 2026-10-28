from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash="/?")
router.register("categories", views.CategoryViewSet, basename="category")
router.register("products", views.ProductViewSet, basename="product")
router.register("suppliers", views.SupplierViewSet, basename="supplier")
router.register("purchase-orders", views.PurchaseOrderViewSet, basename="purchase-order")
router.register("stock-movements", views.StockMovementViewSet, basename="stock-movement")

urlpatterns = router.urls
