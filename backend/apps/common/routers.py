from rest_framework.routers import SimpleRouter


class OptionalSlashRouter(SimpleRouter):
    """`/orders` and `/orders/` both resolve (APPEND_SLASH is off)."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.trailing_slash = "/?"
