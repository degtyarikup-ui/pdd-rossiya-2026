from smtplib import SMTPException

from django.conf import settings
from django.core.mail import send_mail
from django.db import transaction

from .models import AccessNotice


def deliver(pk):
    # SMTP failure must never reinstate a revoked instructor or invalidate a successful acceptance.
    with transaction.atomic():
        notice = AccessNotice.objects.select_for_update().filter(pk=pk).first()
        if notice is None:
            return True
        try:
            send_mail(
                notice.subject, notice.body, settings.DEFAULT_FROM_EMAIL, [notice.email]
            )
        except (SMTPException, OSError):
            return False
        notice.delete()
        return True


def notify(email, subject, body):
    notice = AccessNotice.objects.create(email=email, subject=subject, body=body)
    transaction.on_commit(lambda: deliver(notice.pk), robust=True)
