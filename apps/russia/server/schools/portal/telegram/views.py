import re
import time

import requests
from allauth.core.ratelimit import consume_or_429
from allauth.socialaccount.adapter import get_adapter
from django.conf import settings
from django.shortcuts import render
from django.views.decorators.http import require_POST

from portal.social import connect_user, finish, problem


def bot_request(path, body):
    response = requests.post(
        "https://api.pdd-drive.app/api/auth/telegram/" + path,
        json=body,
        headers={"x-install-secret": settings.SCHOOL_BOT_BRIDGE_KEY},
        timeout=8,
        allow_redirects=False,
    )
    if response.status_code != 200:
        raise ValueError("Unavailable Telegram bridge")
    result = response.json()
    if not isinstance(result, dict):
        raise ValueError("Invalid Telegram response")
    return result


def wait_page(request, flow, pending=False):
    return render(
        request,
        "socialaccount/telegram.html",
        {"bot_url": flow["url"], "pending": pending},
    )


@require_POST
def start(request):
    if not settings.SCHOOL_BOT_BRIDGE_KEY:
        return problem(
            request, "Telegram", "Соединение с ботом пока не настроено.", 503
        )
    limited = consume_or_429(request, action="school_bot_start")
    if limited:
        return limited
    try:
        reply = bot_request("request", {"protocolVersion": 2})
        nonce, verifier, bot = (
            reply.get("nonce", ""),
            reply.get("verifier", ""),
            reply.get("botUsername", ""),
        )
        if not (
            reply.get("ok") is True
            and reply.get("protocolVersion") == 2
            and re.fullmatch(r"auth_[a-f0-9]{32}", nonce)
            and re.fullmatch(r"[a-f0-9]{64}", verifier)
            and re.fullmatch(r"[a-zA-Z0-9_]{5,32}", bot)
        ):
            raise ValueError("Invalid challenge")
    except (ValueError, TypeError, requests.RequestException):
        return problem(
            request, "Telegram", "Бот временно недоступен. Попробуйте ещё раз.", 503
        )
    flow = {
        "nonce": nonce,
        "verifier": verifier,
        "expires": time.time() + 300,
        "connect_user": connect_user(request),
        "url": f"https://t.me/{bot}?start={nonce}",
    }
    request.session["school_bot"] = flow
    return wait_page(request, flow)


@require_POST
def check(request):
    flow = request.session.get("school_bot")
    if not flow or flow["expires"] < time.time():
        return problem(request, "Telegram", "Ссылка устарела. Начните вход ещё раз.")
    limited = consume_or_429(request, action="school_bot_check")
    if limited:
        return limited
    try:
        reply = bot_request(
            "check", {"nonce": flow["nonce"], "verifier": flow["verifier"]}
        )
    except (ValueError, requests.RequestException):
        return wait_page(request, flow, pending=True)
    if reply.get("status") == "pending":
        return wait_page(request, flow, pending=True)
    request.session.pop("school_bot", None)
    person = reply.get("user") or {}
    subject = (
        re.fullmatch(r"telegram_([0-9]{1,20})", str(person.get("id", "")))
        if isinstance(person, dict)
        else None
    )
    if (
        reply.get("ok") is not True
        or reply.get("status") != "confirmed"
        or not subject
        or person.get("provider") != "telegram"
    ):
        return problem(
            request, "Telegram", "Вход не подтверждён. Получите новую ссылку."
        )
    provider = get_adapter().get_provider(request, "telegram")
    # Exclude the app session and synthetic Telegram email from school identity.
    account = provider.sociallogin_from_response(
        request, {"id": subject[1], "first_name": str(person.get("name", ""))[:100]}
    )
    return finish(request, account, flow.get("connect_user"))
