from django.core.cache import cache

DIRECTORY_KEY = "sf:directory"
CATALOG_TTL = 300


def catalog_key(business_id) -> str:
    return f"sf:catalog:{business_id}"


def invalidate_shop(business_id) -> None:
    cache.delete_many([catalog_key(business_id), DIRECTORY_KEY])
