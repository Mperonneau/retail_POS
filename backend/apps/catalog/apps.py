from django.apps import AppConfig


class CatalogConfig(AppConfig):
    name = "apps.catalog"
    label = "catalog"

    def ready(self) -> None:
        from . import signals  # noqa: F401
