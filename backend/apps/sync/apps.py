from django.apps import AppConfig


class SyncConfig(AppConfig):
    name = "apps.sync"
    label = "sync"

    def ready(self):
        from . import signals  # noqa: F401
