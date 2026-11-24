import secrets
import time

from allauth.core.ratelimit import consume_or_429
from allauth.socialaccount.adapter import get_adapter
from allauth.socialaccount.helpers import complete_social_login
from allauth.socialaccount.providers.apple import views as apple
from allauth.socialaccount.providers.yandex import views as yandex
from django.conf import settings
from django.core.exceptions import ValidationError
from django.shortcuts import render
from django.urls import reverse
from django.utils.crypto import constant_time_compare
from django.views.decorators.http import require_POST


def problem(request, provider, message, status=400):
    return render(
        request,
        "socialaccount/problem.html",
        {"provider": provider, "message": message},
        status=status,
    )


def connect_user(request):
    return (
        request.user.pk
        if request.user.is_authenticated and request.POST.get("process") == "connect"
        else None
    )


def finish(request, sociallogin, connected_user=None):
    if connected_user is not None:
        if not request.user.is_authenticated or request.user.pk != connected_user:
            return problem(
                request,
                "аккаунт",
                "Сеанс изменился. Подключите способ входа ещё раз.",
                403,
            )
        sociallogin.state = {
            "process": "connect",
            "next": reverse("socialaccount_connections"),
        }
        return complete_social_login(request, sociallogin)
    sociallogin.state = {
        "process": "login",
        "next": reverse("accept") if request.session.get("pending_staff") else "/",
    }
    return complete_social_login(request, sociallogin)


@require_POST
def google_start(request):
    nonce = secrets.token_urlsafe(32)
    request.session["school_google"] = [nonce, time.time() + 600, connect_user(request)]
    return render(
        request,
        "socialaccount/google.html",
        {"nonce": nonce, "client_id": settings.SCHOOL_GOOGLE_ID},
    )


@require_POST
def google_finish(request):
    limited = consume_or_429(request, action="school_google")
    if limited:
        return limited
    flow = request.session.pop("school_google", None)
    credential = request.POST.get("credential", "")
    if not flow or flow[1] < time.time() or not 1 <= len(credential) <= 16384:
        return problem(request, "Google", "Время входа истекло. Попробуйте ещё раз.")
    provider = get_adapter().get_provider(request, "google")
    try:
        account = provider.verify_token(request, {"id_token": credential})
    except (KeyError, ValueError, TypeError, ValidationError):
        return problem(request, "Google", "Не удалось подтвердить аккаунт Google.")
    if not constant_time_compare(account.account.extra_data.get("nonce", ""), flow[0]):
        return problem(request, "Google", "Начните вход в этой вкладке ещё раз.")
    return finish(request, account, flow[2])


def leave(request, name, response):
    if response.status_code == 302:
        # A browser POST followed by provider-specific redirects is subject to form-action.
        # Navigate to the library-generated authorization URL as a top-level GET instead.
        return render(
            request,
            "socialaccount/leaving.html",
            {"provider": name, "destination": response.url},
        )
    return response


@require_POST
def yandex_start(request):
    return leave(request, "Яндекс", yandex.oauth2_login(request))


@require_POST
def apple_start(request):
    config = settings.SOCIALACCOUNT_PROVIDERS["apple"]["APP"]
    if not (
        request.is_secure()
        and config["key"]
        and config["secret"]
        and config["settings"]["certificate_key"]
    ):
        return problem(
            request,
            "Apple",
            "Вход через Apple на этом адресе пока недоступен.",
            503,
        )
    return leave(request, "Apple", apple.oauth2_login(request))


def provider_names(request):
    return {
        "school_shared_login": not settings.LOCAL,
        "school_providers": (
            ("google", "Google"),
            ("yandex", "Яндекс"),
            ("telegram", "Telegram"),
            ("apple", "Apple"),
        )
    }


def apple_callback(request):
    response = apple.oauth2_callback(request)
    # allauth stores Apple's cross-site POST in its own, temporary callback session.
    if "apple-login-session" in response.cookies:
        response.cookies["apple-login-session"]["httponly"] = True
        response.cookies["apple-login-session"]["max-age"] = 600
    return response
