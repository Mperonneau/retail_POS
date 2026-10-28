from django.core.management.base import BaseCommand

from apps.storefront.services import release_expired


class Command(BaseCommand):
    help = "Give back stock held by unpaid vitrine orders whose reservation lapsed."

    def handle(self, *args, **options):
        total = 0
        while True:
            released = release_expired(limit=200)
            total += released
            if released < 200:
                break
        self.stdout.write(f"{total} réservation(s) libérée(s)")
