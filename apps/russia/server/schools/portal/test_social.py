import json
import re
import secrets
import time
from copy import deepcopy
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

import jwt
import requests
from allauth.account.models import EmailAddress
from allauth.socialaccount.models import SocialAccount, SocialToken
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core import mail
from django.test import Client, TransactionTestCase, override_settings
from django.urls import reverse

from .models import Employee, School


def reply(data):
    response = requests.Response()
    response.status_code = 200
    response.headers["content-type"] = "application/json"
    response._content = json.dumps(data).encode()
    return response


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class ProviderTests(TransactionTestCase):
    def test_worker_hashes_are_compatible_with_django(self):
        from django.contrib.auth.hashers import PBKDF2PasswordHasher

        from .cloud_password import WorkerPasswordHasher

        password, salt = secrets.token_urlsafe(), secrets.token_hex(12)
        self.assertEqual(
            WorkerPasswordHasher().encode(password, salt, iterations=2048),
            PBKDF2PasswordHasher().encode(password, salt, iterations=2048),
        )

    def test_methods_on_login_and_signup(self):
        for route in ("account_login", "account_signup"):
            html = self.client.get(reverse(route))
            for name in ("google", "yandex", "telegram", "apple"):
                self.assertContains(html, reverse(name + "_login"))
                self.assertContains(html, "/auth-icons/" + name + ".svg")

    @patch("allauth.socialaccount.internal.jwtkit.fetch_key")
    def test_google_identity_recognized_on_return(self, fetch_key):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        fetch_key.return_value = ("RS256", key.public_key())
        for _ in range(2):
            self.client = Client()
            flow = self.client.post(reverse("google_login"))
            nonce = flow.context["nonce"]
            credential = jwt.encode(
                {
                    "sub": "google-fixture",
                    "email": "google@example.test",
                    "email_verified": True,
                    "iat": int(time.time()),
                    "exp": int(time.time()) + 60,
                    "iss": "https://accounts.google.com",
                    "aud": settings.SCHOOL_GOOGLE_ID,
                    "nonce": nonce,
                },
                key,
                algorithm="RS256",
                headers={"kid": "fixture"},
            )
            result = self.client.post(
                reverse("school_google_finish"), {"credential": credential}, follow=True
            )
            self.assertContains(result, "Ваша автошкола")
            self.assertIn("_auth_user_id", self.client.session)
        self.assertEqual(SocialAccount.objects.filter(provider="google").count(), 1)
        self.assertEqual(School.objects.count(), 0)
        self.assertEqual(
            self.client.post(
                reverse("school_google_finish"), {"credential": credential}
            ).status_code,
            400,
        )

    @patch("requests.sessions.Session.request")
    def test_yandex_code_pkce_profile_and_signup(self, transport):
        start = self.client.post(reverse("yandex_login"))
        params = parse_qs(urlparse(start.context["destination"]).query)
        self.assertEqual(params["code_challenge_method"], ["S256"])
        transport.side_effect = [
            reply({"access_token": "fixture"}),
            reply(
                {"id": "123", "default_email": "ya@example.test", "first_name": "Ирина"}
            ),
        ]
        done = self.client.get(
            reverse("yandex_callback"),
            {"state": params["state"][0], "code": "fixture"},
            follow=True,
        )
        self.assertContains(done, "Ваша автошкола")
        self.assertIn("code_verifier", transport.call_args_list[0].kwargs["data"])
        self.assertTrue(
            SocialAccount.objects.filter(provider="yandex", uid="123").exists()
        )
        self.assertFalse(SocialToken.objects.exists())

    @patch("requests.sessions.Session.request")
    def test_apple_cross_site_post_and_signed_token(self, transport):
        apps = deepcopy(settings.SOCIALACCOUNT_PROVIDERS)
        key = ec.generate_private_key(ec.SECP256R1())
        apps["apple"]["APP"].update(
            key="team",
            secret="kid",
            settings={
                "certificate_key": key.private_bytes(
                    serialization.Encoding.PEM,
                    serialization.PrivateFormat.PKCS8,
                    serialization.NoEncryption(),
                ).decode()
            },
        )
        signing_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        public_jwk = jwt.algorithms.RSAAlgorithm.to_jwk(
            signing_key.public_key(), as_dict=True
        )
        public_jwk.update(kid="fixture", alg="RS256")
        token = jwt.encode(
            {
                "sub": "apple-test",
                "email": "relay@privaterelay.appleid.com",
                "email_verified": "true",
                "iat": int(time.time()),
                "exp": int(time.time()) + 90,
                "iss": "https://appleid.apple.com",
                "aud": apps["apple"]["APP"]["client_id"],
            },
            signing_key,
            algorithm="RS256",
            headers={"kid": "fixture"},
        )
        with override_settings(
            SOCIALACCOUNT_PROVIDERS=apps, ACCOUNT_DEFAULT_HTTP_PROTOCOL="https"
        ):
            start = self.client.post(reverse("apple_login"), secure=True)
            params = parse_qs(urlparse(start.context["destination"]).query)
            self.assertEqual(
                urlparse(start.context["destination"]).hostname, "appleid.apple.com"
            )
            # Safari omits the regular Lax session cookie on Apple's cross-site form POST.
            postback = Client().post(
                reverse("apple_callback"),
                {"state": params["state"][0], "code": "fixture"},
                secure=True,
            )
            self.client.cookies.update(postback.cookies)
            transport.side_effect = [
                reply({"access_token": "fixture", "id_token": token}),
                reply({"keys": [public_jwk]}),
            ]
            done = self.client.get(postback.url, follow=True, secure=True)
        self.assertContains(done, "Ваша автошкола")
        self.assertTrue(
            SocialAccount.objects.filter(provider="apple", uid="apple-test").exists()
        )

    @override_settings(SCHOOL_BOT_BRIDGE_KEY="fixture")
    @patch("portal.telegram.views.bot_request")
    def test_telegram_invited_instructor_confirms_email_and_accepts(self, bridge):
        from datetime import timedelta

        from django.utils import timezone

        from .views import digest

        school = School.objects.create(name="Тест")
        owner = get_user_model().objects.create_user(
            username="owner", email="owner@example.test"
        )
        manager = Employee.objects.create(
            user=owner, school=school, name="Анна", role="manager", terms_version="test"
        )
        raw = secrets.token_urlsafe(32)
        addr = "invite@example.test"
        school.invites.create(
            sender=manager,
            digest=digest(raw),
            email=addr,
            expires_at=timezone.now() + timedelta(days=1),
        )
        self.client.get(reverse("staff_link", args=[raw]))
        bridge.side_effect = [
            {
                "ok": True,
                "protocolVersion": 2,
                "nonce": "auth_" + "a" * 32,
                "verifier": "b" * 64,
                "botUsername": "fixture_bot",
            },
            {"ok": False, "status": "pending"},
            {
                "ok": True,
                "status": "confirmed",
                "token": "app-session",
                "user": {"provider": "telegram", "id": "telegram_17", "name": "Иван"},
            },
        ]
        begin = self.client.post(reverse("telegram_login"))
        self.assertContains(begin, "t.me/fixture_bot")
        self.assertNotContains(begin, "b" * 64)
        self.assertContains(
            self.client.post(reverse("telegram_check")), "Ждём подтверждение"
        )
        signup = self.client.post(reverse("telegram_check"), follow=True)
        self.assertContains(signup, "Завершите регистрацию")
        self.client.post(reverse("socialaccount_signup"), {"email": addr})
        self.assertEqual(school.staff.count(), 1)
        link = next(
            re.search(r"https?://[^\s]+/confirm-email/[^\s]+", letter.body)[0]
            for letter in mail.outbox
            if re.search(r"https?://[^\s]+/confirm-email/[^\s]+", letter.body)
        )
        self.client.post(urlparse(link).path)
        self.assertTrue(EmailAddress.objects.filter(email=addr, verified=True).exists())
        if "_auth_user_id" not in self.client.session:
            bridge.side_effect = [
                {
                    "ok": True,
                    "protocolVersion": 2,
                    "nonce": "auth_" + "c" * 32,
                    "verifier": "d" * 64,
                    "botUsername": "fixture_bot",
                },
                {
                    "ok": True,
                    "status": "confirmed",
                    "user": {
                        "provider": "telegram",
                        "id": "telegram_17",
                        "name": "Иван",
                    },
                },
            ]
            self.client.post(reverse("telegram_login"))
            self.client.post(reverse("telegram_check"))
        self.client.post(reverse("accept"), {"name": "Иван", "terms": "on"})
        self.assertTrue(school.staff.filter(name="Иван", role="instructor").exists())
        self.assertFalse(SocialToken.objects.exists())
        self.assertNotIn(
            "app-session",
            str(SocialAccount.objects.get(provider="telegram").extra_data),
        )

    @patch("allauth.socialaccount.internal.jwtkit.fetch_key")
    def test_matching_google_email_requires_explicit_connection(self, fetch_key):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        fetch_key.return_value = ("RS256", key.public_key())
        password = secrets.token_urlsafe(20)
        address = "known@example.test"
        existing = get_user_model().objects.create_user(
            username=address, email=address, password=password
        )
        EmailAddress.objects.create(
            user=existing, email=address, primary=True, verified=True
        )

        def finish_google(connect=False):
            flow = self.client.post(
                reverse("google_login"), {"process": "connect"} if connect else {}
            )
            credential = jwt.encode(
                {
                    "sub": "same-email",
                    "iss": "https://accounts.google.com",
                    "aud": settings.SCHOOL_GOOGLE_ID,
                    "email": address,
                    "email_verified": True,
                    "nonce": flow.context["nonce"],
                    "exp": int(time.time()) + 60,
                },
                key,
                algorithm="RS256",
                headers={"kid": "fixture"},
            )
            return self.client.post(
                reverse("school_google_finish"), {"credential": credential}, follow=True
            )

        finish_google()
        self.assertNotIn("_auth_user_id", self.client.session)
        self.assertFalse(SocialAccount.objects.filter(user=existing).exists())
        self.client.post(
            reverse("account_login"), {"login": address, "password": password}
        )
        finish_google(connect=True)
        linked = SocialAccount.objects.get(provider="google", uid="same-email")
        self.assertEqual(linked.user_id, existing.pk)
        self.assertEqual(get_user_model().objects.count(), 1)

    @patch("portal.pdd_login.requests.post")
    def test_app_login_keeps_identity_and_checks_the_initiating_session(self, redeem):
        for provider in ("google", "yandex", "apple", "telegram"):
            for _ in range(2):
                self.client = Client()
                response = self.client.post(reverse("pdd_login"))
                query = parse_qs(urlparse(response.url).query)
                code = "a" * 64
                self.assertEqual(
                    self.client.get(
                        reverse("pdd_callback"), {"code": code, "state": "b" * 64}
                    ).status_code,
                    400,
                )
                redeem.return_value = reply(
                    {
                        "provider": provider,
                        "uid": "id-with_suffix",
                        "email": f"{provider}@example.test",
                        "name": "Сотрудник",
                    }
                )
                callback = {"code": code, "state": query["school_state"][0]}
                self.client.get(reverse("pdd_callback"), callback)
                self.assertIn("_auth_user_id", self.client.session)
                self.assertEqual(
                    self.client.get(reverse("pdd_callback"), callback).status_code, 400
                )
            self.assertEqual(
                SocialAccount.objects.filter(
                    provider=provider, uid="id-with_suffix"
                ).count(),
                1,
            )
        self.assertFalse(Employee.objects.exists())

    @patch("portal.pdd_login.requests.post")
    def test_app_login_offers_a_fresh_start_when_exchange_fails(self, redeem):
        for upstream, expected in [(400, 400), (302, 503), (500, 503)]:
            with self.subTest(upstream=upstream):
                started = self.client.post(reverse("pdd_login"))
                state = parse_qs(urlparse(started.url).query)["school_state"][0]
                redeem.return_value.status_code = upstream
                result = self.client.get(
                    reverse("pdd_callback"), {"code": "b" * 64, "state": state}
                )
                self.assertContains(result, reverse("account_login"), status_code=expected)
                self.assertNotIn("_auth_user_id", self.client.session)
