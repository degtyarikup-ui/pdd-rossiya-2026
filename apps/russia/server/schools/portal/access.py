import base64
from contextlib import nullcontext
from functools import wraps

from allauth.account.adapter import DefaultAccountAdapter
from allauth.account.authentication import get_authentication_records
from allauth.mfa.adapter import DefaultMFAAdapter
from allauth.mfa.models import Authenticator
from cryptography.fernet import Fernet
from django.contrib.auth import logout
from django.contrib.auth.decorators import login_required
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.shortcuts import redirect
from django.utils.crypto import salted_hmac

from .models import Employee, Group


def private_responses(get_response):
    def middleware(request):
        response = get_response(request)
        response["X-Robots-Tag"] = "noindex, nofollow, noarchive"
        response["Cache-Control"] = "private, no-store"
        response["Content-Security-Policy"] = (
            "default-src 'self'; img-src 'self' data:; object-src 'none'; "
            "frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        )
        if request.path == "/accounts/google/login/" and response.status_code == 200:
            response["Content-Security-Policy"] += (
                "; script-src 'self' https://accounts.google.com/gsi/client; "
                "frame-src https://accounts.google.com/gsi/; connect-src 'self' https://accounts.google.com/gsi/; "
                "style-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/style"
            )
            response["Cross-Origin-Opener-Policy"] = "same-origin-allow-popups"
            response["Referrer-Policy"] = "strict-origin-when-cross-origin"
        return response

    return middleware


class AccountAdapter(DefaultAccountAdapter):
    def get_client_ip(self, request):
        # Never trust forwarding headers supplied by a visitor.
        return request.META.get("REMOTE_ADDR", "")


class MFAAdapter(DefaultMFAAdapter):
    def _cipher(self):
        key = salted_hmac("schools.mfa.encryption.v1", "", algorithm="sha256").digest()
        return Fernet(base64.urlsafe_b64encode(key))

    def encrypt(self, text):
        return self._cipher().encrypt(text.encode()).decode()

    def decrypt(self, encrypted_text):
        return self._cipher().decrypt(encrypted_text.encode()).decode()

    def can_delete_authenticator(self, authenticator):
        return not Employee.objects.filter(
            user=authenticator.user, role=Employee.Role.MANAGER
        ).exists()


def active_roles(user):
    return (
        user.school_roles.select_related("school")
        .filter(active=True, school__active=True)
        .order_by("pk")
    )


def groups_for(employee):
    qs = Group.objects.filter(
        instructor__school=employee.school, archived=False
    ).select_related("instructor")
    return qs if employee.manager else qs.filter(instructor=employee)


def has_totp(user):
    return Authenticator.objects.filter(
        user=user, type=Authenticator.Type.TOTP
    ).exists()


def school_view(view=None, *, manager=False):
    def decorate(fn):
        @login_required
        @wraps(fn)
        def wrapped(request, *args, **kwargs):
            with transaction.atomic() if request.method == "POST" else nullcontext():
                return authorized(request, *args, **kwargs)

        def authorized(request, *args, **kwargs):
            roles = active_roles(request.user)
            chosen = request.session.get("school_id")
            employee = (
                roles.filter(school_id=chosen).first() if chosen else roles.first()
            )
            if not employee:
                if chosen:
                    request.session.pop("school_id", None)
                    raise PermissionDenied
                return redirect("start")
            if manager and not employee.manager:
                raise PermissionDenied
            if employee.manager and not has_totp(request.user):
                return redirect("mfa_activate_totp")
            if employee.manager:
                methods = get_authentication_records(request, request.user)
                enrolled_here = (
                    request.session.get("totp_enrolled_user") == request.user.pk
                )
                if not enrolled_here and not any(
                    step["method"] == "mfa" for step in methods
                ):
                    logout(request)
                    return redirect("account_login")
            request.employee = employee
            return fn(request, *args, **kwargs)

        return wrapped

    return decorate(view) if view else decorate
