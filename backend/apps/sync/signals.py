from django.db.models.signals import post_delete
from django.dispatch import receiver

from apps.catalog.models import Category, Product, Supplier
from apps.customers.models import Customer
from apps.sales.models import Quote

from .models import Tombstone

ENTITIES = {Category: "category", Product: "product", Supplier: "supplier", Customer: "customer", Quote: "quote"}


@receiver(post_delete)
def _record_tombstone(sender, instance, **kwargs):
    entity = ENTITIES.get(sender)
    if entity is None:
        return
    Tombstone.objects.create(business_id=instance.business_id, entity=entity, object_id=str(instance.pk))
