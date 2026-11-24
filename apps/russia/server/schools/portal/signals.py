from allauth.mfa.models import Authenticator
from allauth.mfa.signals import authenticator_added
from django.dispatch import receiver


@receiver(authenticator_added)
def record_enrollment(sender, request, user, authenticator, **kwargs):
    if authenticator.type == Authenticator.Type.TOTP:
        request.session["totp_enrolled_user"] = user.pk
