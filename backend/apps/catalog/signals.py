from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from apps.storefront.cache import invalidate_shop

from .models import Category, Product, ProductOptionChoice, ProductOptionGroup


@receiver([post_save, post_delete], sender=Product)
@receiver([post_save, post_delete], sender=Category)
def _catalog_changed(sender, instance, **kwargs):
    invalidate_shop(instance.business_id)


@receiver([post_save, post_delete], sender=ProductOptionGroup)
def _group_changed(sender, instance, **kwargs):
    invalidate_shop(instance.product.business_id)


@receiver([post_save, post_delete], sender=ProductOptionChoice)
def _choice_changed(sender, instance, **kwargs):
    invalidate_shop(instance.group.product.business_id)
