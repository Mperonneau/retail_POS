from django.db import models

from apps.common.models import TenantModel


class Notification(TenantModel):
    KINDS = [
        ("storefront_order_paid", "Commande en ligne payée"),
        ("storefront_quote", "Nouveau devis reçu"),
        ("low_stock", "Stock bas"),
        ("check_pending", "Chèque en attente"),
        ("check_refused", "Chèque refusé"),
        ("paylink_paid", "Lien de paiement payé"),
        ("cash_variance", "Écart de caisse"),
        ("info", "Information"),
    ]

    kind = models.CharField(max_length=30, choices=KINDS, default="info")
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=300, blank=True)
    data = models.JSONField(default=dict, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["business", "read_at", "-created_at"], name="notif_biz_unread")]
