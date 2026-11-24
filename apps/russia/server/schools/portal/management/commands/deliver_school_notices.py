from django.core.management.base import BaseCommand

from portal.models import AccessNotice
from portal.notices import deliver


class Command(BaseCommand):
    help = "Повторить недоставленные уведомления об изменении доступа"

    def handle(self, *args, **options):
        queued = list(
            AccessNotice.objects.order_by("pk").values_list("pk", flat=True)[:100]
        )
        sent = sum(deliver(pk) for pk in queued)
        self.stdout.write(f"Доставлено {sent} из {len(queued)}")
