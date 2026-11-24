from allauth.socialaccount.providers.telegram.provider import TelegramProvider
from django.urls import reverse


class SchoolTelegramProvider(TelegramProvider):
    """Identity comes from the existing PDD bot challenge, not the Login Widget."""

    uses_apps = False
    supports_redirect = False

    @classmethod
    def get_package(cls):
        return "portal.telegram"

    def get_login_url(self, request, **kwargs):
        return reverse("telegram_login")


provider_classes = [SchoolTelegramProvider]
