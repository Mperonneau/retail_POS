from django.urls import path

from . import views

urlpatterns = [
    path("reports/summary", views.SummaryView.as_view()),
    path("reports/sales-by-day", views.SalesByDayView.as_view()),
    path("reports/payment-methods", views.PaymentMethodsView.as_view()),
    path("reports/cashiers", views.CashiersView.as_view()),
    path("reports/top-products", views.TopProductsView.as_view()),
    path("reports/stock-value", views.StockValueView.as_view()),
    path("reports/receivables", views.ReceivablesView.as_view()),
    path("reports/cash-variances", views.CashVariancesView.as_view()),
    path("dashboard", views.DashboardView.as_view()),
]
