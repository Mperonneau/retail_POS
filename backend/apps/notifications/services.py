from .models import Notification


def notify(business, kind: str, title: str, body: str = "", **data) -> Notification:
    return Notification.objects.create(business=business, kind=kind, title=title[:120], body=body[:300], data=data)
