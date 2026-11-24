import hashlib
import json
import os
import re
import secrets
import time
from urllib.parse import urlencode

import requests
from allauth.account.models import EmailAddress
from allauth.socialaccount.adapter import get_adapter
from allauth.socialaccount.models import SocialAccount, SocialLogin
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.shortcuts import redirect
from django.utils.crypto import constant_time_compare
from django.views.decorators.http import require_GET, require_POST

from .social import connect_user, finish, problem

PROVIDERS = {"apple", "google", "telegram", "yandex"}
TOKEN = re.compile("[a-f0-9]{64}")


@require_POST
def start(request):
    verifier, state = secrets.token_hex(32), secrets.token_hex(32)
    request.session["school_pdd_login"] = {
        "verifier": verifier,
        "state": state,
        "expires": time.time() + 600,
        "connect": connect_user(request),
    }
    return redirect(
        "https://pdd-drive.app/app/?"
        + urlencode(
            {
                "school_login": hashlib.sha256(verifier.encode("ascii")).hexdigest(),
                "school_state": state,
            }
        )
    )


def redeem(code, verifier):
    endpoint = "https://api.pdd-drive.app/api/auth/schools/redeem"
    data = {"code": code, "verifier": verifier}
    if os.environ.get("PDD_SCHOOLS_CLOUDFLARE"):
        from pyodide.ffi import run_sync
        from workers import fetch

        async def exchange():
            response = await fetch(
                endpoint,
                method="POST",
                redirect="error",
                headers={"Content-Type": "application/json"},
                body=json.dumps(data),
            )
            return await response.json() if response.status == 200 else None

        return run_sync(exchange())
    response = requests.post(endpoint, json=data, timeout=8, allow_redirects=False)
    return response.json() if response.status_code == 200 else None


@require_GET
def callback(request):
    flow = request.session.get("school_pdd_login")
    code, state = request.GET.get("code", ""), request.GET.get("state", "")
    if (
        not flow
        or flow["expires"] < time.time()
        or not TOKEN.fullmatch(code)
        or not TOKEN.fullmatch(state)
        or not constant_time_compare(state, flow["state"])
    ):
        return problem(request, "ПДД России", "Начните вход в кабинет ещё раз.")
    try:
        identity = redeem(code, flow["verifier"])
        if not isinstance(identity, dict):
            return problem(
                request,
                "ПДД России",
                "Не удалось подтвердить вход. Попробуйте ещё раз.",
            )
    except (OSError, requests.RequestException, ValueError):
        return problem(
            request,
            "ПДД России",
            "Сервис временно недоступен. Попробуйте ещё раз.",
            503,
        )
    request.session.pop("school_pdd_login", None)
    provider, uid = identity.get("provider"), identity.get("uid")
    if provider not in PROVIDERS or not isinstance(uid, str) or not 0 < len(uid) <= 180:
        return problem(request, "ПДД России", "Не удалось подтвердить аккаунт.")
    email = identity.get("email") or ""
    try:
        validate_email(email)
    except ValidationError:
        email = ""
    sociallogin = SocialLogin(
        provider=get_adapter().get_provider(request, provider),
        user=get_user_model()(
            email=email, first_name=(identity.get("name") or "")[:150]
        ),
        account=SocialAccount(provider=provider, uid=uid),
        email_addresses=[EmailAddress(email=email, verified=True, primary=True)]
        if email
        else [],
    )
    return finish(request, sociallogin, flow["connect"])
