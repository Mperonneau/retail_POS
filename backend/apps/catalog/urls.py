from apps.common.routers import OptionalSlashRouter

from . import views

router = OptionalSlashRouter()
router.register("categories", views.CategoryViewSet, basename="category")
router.register("products", views.ProductViewSet, basename="product")
router.register("suppliers", views.SupplierViewSet, basename="supplier")
router.register("purchase-orders", views.PurchaseOrderViewSet, basename="purchase-order")
router.register("stock-movements", views.StockMovementViewSet, basename="stock-movement")

urlpatterns = router.urls
