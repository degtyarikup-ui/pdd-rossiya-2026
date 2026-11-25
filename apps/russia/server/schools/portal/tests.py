import re
import secrets
import time
from datetime import timedelta
from urllib.parse import urlsplit

from allauth.account.models import EmailAddress
from allauth.mfa.totp.internal.auth import (
    TOTP,
    format_hotp_value,
    generate_totp_secret,
    hotp_value,
)
from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.test import Client, TransactionTestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from .models import Employee, Event, Group, Learner, School, StaffInvite


def user(email, password=None):
    person = get_user_model().objects.create_user(
        username=email, email=email, password=password
    )
    EmailAddress.objects.create(user=person, email=email, primary=True, verified=True)
    return person


def code(secret):
    return format_hotp_value(hotp_value(secret, int(time.time()) // 30))


def mail_path(fragment):
    for letter in reversed(mail.outbox):
        for url in re.findall(r"https?://[^\s<>]+", letter.body):
            if fragment in url:
                return urlsplit(url).path
    raise AssertionError(f"No message with path {fragment}")


@override_settings(
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class CabinetTests(TransactionTestCase):
    def setUp(self):
        cache.clear()
        self.password = secrets.token_urlsafe(18)
        self.a, self.b = (
            School.objects.create(name="Старт"),
            School.objects.create(name="Старт"),
        )
        self.owner = self.member(self.a, "owner", manager=True)
        self.other = self.member(self.b, "other", manager=True)
        self.teacher = self.member(self.a, "teacher")
        self.group = Group.objects.create(name="Моя группа", instructor=self.teacher)
        self.private = Group.objects.create(
            name="Только директор", instructor=self.owner
        )
        self.foreign = Group.objects.create(name="Чужая группа", instructor=self.other)
        Learner.objects.create(group=self.group, name="Ученик один")
        Learner.objects.create(group=self.foreign, name="Чужой ученик")

    def member(self, school, name, manager=False):
        employee = Employee.objects.create(
            school=school,
            user=user(name + "@example.test", self.password),
            name=name,
            role="manager" if manager else "instructor",
            terms_version="test",
        )
        if manager:
            TOTP.activate(employee.user, generate_totp_secret())
        return employee

    def signed_in(self, member):
        client = Client()
        client.force_login(member.user)
        session = client.session
        session["school_id"] = member.school_id
        if member.manager:
            session["totp_enrolled_user"] = member.user_id
        session.save()
        return client

    def test_two_directors_and_teacher_scope(self):
        for member, yes, no in [
            (self.owner, self.group, self.foreign),
            (self.other, self.foreign, self.group),
            (self.teacher, self.group, self.private),
        ]:
            client = self.signed_in(member)
            self.assertContains(client.get(reverse("groups")), yes.name)
            self.assertNotContains(client.get(reverse("groups")), no.name)
            self.assertEqual(
                client.get(reverse("group", args=[no.pk])).status_code, 404
            )
            self.assertEqual(client.get(reverse("qr", args=[no.pk])).status_code, 404)
        teacher = self.signed_in(self.teacher)
        self.assertNotContains(teacher.get(reverse("learners")), "Чужой ученик")
        for name in ("team", "finance", "invite"):
            self.assertEqual(teacher.get(reverse(name)).status_code, 403)
        teacher.post(
            reverse("new_group"), {"name": "Практика", "instructor": self.other.pk}
        )
        self.assertEqual(Group.objects.get(name="Практика").instructor, self.teacher)
        result = self.signed_in(self.owner).post(
            reverse("new_group"), {"name": "Нет", "instructor": self.other.pk}
        )
        self.assertEqual(result.status_code, 200)
        self.assertFalse(Group.objects.filter(name="Нет").exists())

    def test_assigned_group_and_open_session_revocation(self):
        client = self.signed_in(self.teacher)
        owner = self.signed_in(self.owner)
        owner.post(
            reverse("edit_group", args=[self.private.pk]),
            {"name": self.private.name, "instructor": self.teacher.pk},
        )
        self.assertContains(
            client.get(reverse("group", args=[self.private.pk])), self.private.name
        )
        owner.post(reverse("disable", args=[self.teacher.pk]))
        self.assertEqual(
            client.get(reverse("group", args=[self.group.pk])).status_code, 403
        )
        self.group.refresh_from_db()
        self.assertEqual(self.group.instructor, self.owner)
        self.assertTrue(Event.objects.filter(action="staff_disabled").exists())
        self.assertEqual(len(mail.outbox), 2)
        self.a.active = False
        self.a.save()
        self.assertEqual(owner.get(reverse("finance")).status_code, 403)

    def test_group_link_revoke_reissue_and_archive(self):
        client = self.signed_in(self.teacher)
        detail = reverse("group", args=[self.group.pk])
        endpoint = reverse("group_link", args=[self.group.pk])
        path = urlsplit(client.get(detail).context["link"]).path
        public = self.client.get(path)
        self.assertContains(public, self.group.name)
        self.assertNotContains(public, "Ученик один")
        self.assertContains(public, "Вступить в группу")
        self.assertContains(public, f'href="https://join.pdd-drive.app{path}"')
        self.assertIn("no-store", public["Cache-Control"])
        self.assertIn("noindex", public["X-Robots-Tag"])
        client.post(endpoint)
        self.assertEqual(self.client.get(path).status_code, 410)
        client.post(endpoint, {"action": "enable"})
        second = urlsplit(client.get(detail).context["link"]).path
        self.assertNotEqual(path, second)
        self.assertEqual(self.client.get(second).status_code, 200)
        self.assertEqual(self.client.get(path).status_code, 410)
        self.signed_in(self.owner).post(reverse("archive", args=[self.group.pk]))
        self.assertEqual(self.client.get(second).status_code, 410)
        self.assertEqual(client.get(detail).status_code, 404)

    def test_addressed_staff_invitation_accept_and_expiry(self):
        client = self.signed_in(self.owner)
        email = "invited@example.test"
        client.post(reverse("invite"), {"email": email})
        first = mail_path("/staff/")
        client.post(reverse("invite"), {"email": email})
        second = mail_path("/staff/")
        self.assertEqual(self.client.get(first).status_code, 410)
        wrong = self.signed_in(self.other)
        self.assertEqual(wrong.get(second, follow=True).status_code, 403)
        visitor = Client()
        visitor.force_login(user(email))
        self.assertContains(visitor.get(second, follow=True), self.a.name)
        visitor.post(reverse("accept"), {"name": "Ирина", "terms": "on"})
        self.assertEqual(self.client.get(second).status_code, 410)
        self.assertTrue(self.a.staff.filter(name="Ирина", role="instructor").exists())
        self.assertEqual(visitor.get(reverse("finance")).status_code, 403)
        client.post(reverse("invite"), {"email": "late@example.test"})
        late = mail_path("/staff/")
        StaffInvite.objects.update(expires_at=timezone.now() - timedelta(minutes=1))
        self.assertEqual(self.client.get(late).status_code, 410)

    def test_school_onboarding_prefills_name_and_requires_consent(self):
        member = user("onboarding@example.test")
        member.first_name = "Анна"
        member.save()
        self.client.force_login(member)
        response = self.client.get(reverse("start"))
        self.assertContains(response, 'value="Анна"')
        self.assertContains(response, reverse("terms"))
        self.assertFalse(response.context["form"]["terms"].value())
        posted = self.client.post(reverse("start"), {"school": "Вираж", "name": "Анна"})
        self.assertFormError(posted.context["form"], "terms", "Обязательное поле.")
        self.assertFalse(School.objects.filter(name="Вираж").exists())

    def test_verified_signup_opens_school_then_allows_optional_mfa(self):
        client = self.client
        email = "new@example.test"
        client.post(
            reverse("account_signup"), {"email": email, "password1": self.password}
        )
        confirm = mail_path("/confirm-email/")
        self.assertEqual(School.objects.count(), 2)
        client.post(confirm)
        client.post(
            reverse("account_login"), {"login": email, "password": self.password}
        )
        client.post(
            reverse("start"), {"school": self.a.name, "name": "Мария", "terms": "on"}
        )
        self.assertEqual(School.objects.count(), 3)
        client.post(
            reverse("start"), {"school": self.a.name, "name": "Мария", "terms": "on"}
        )
        self.assertEqual(School.objects.count(), 3)
        self.assertContains(client.get(reverse("home")), "Учебные группы")
        client.post(reverse("account_logout"))
        returning = client.post(
            reverse("account_login"), {"login": email, "password": self.password}, follow=True
        )
        self.assertEqual(returning.resolver_match.url_name, "home")
        enroll = client.get(reverse("mfa_activate_totp"), follow=True)
        if enroll.resolver_match.url_name == "account_reauthenticate":
            enroll = client.post(
                reverse("account_reauthenticate"),
                {"password": self.password, "next": reverse("mfa_activate_totp")},
                follow=True,
            )
        self.assertContains(enroll, "Защитите вход")
        secret = enroll.context["form"].secret
        result = client.post(
            reverse("mfa_activate_totp"), {"code": code(secret)}, follow=True
        )
        self.assertContains(result, "recovery_codes")
        self.assertContains(client.get(reverse("home")), "Создайте")
        client.post(reverse("account_logout"))
        self.assertRedirects(
            client.get(reverse("home")),
            reverse("account_login") + "?next=/",
            fetch_redirect_response=False,
        )
        response = client.post(
            reverse("account_login"),
            {"login": email, "password": self.password},
            follow=True,
        )
        self.assertEqual(response.resolver_match.url_name, "mfa_authenticate")
        client.post(reverse("mfa_authenticate"), {"code": code(secret)})
        self.assertContains(client.get(reverse("home")), "Учебные группы")
        self.assertNotContains(client.get(reverse("groups")), self.group.name)

    def test_old_session_must_prove_new_factor_and_reset_invalidates_login(self):
        old = Client()
        old.force_login(self.owner.user)
        self.assertRedirects(
            old.get(reverse("home")),
            reverse("account_login"),
            fetch_redirect_response=False,
        )
        existing = self.signed_in(self.teacher)
        recovery = Client()
        recovery.post(
            reverse("account_reset_password"), {"email": self.teacher.user.email}
        )
        url = mail_path("/password/reset/key/")
        stage = recovery.get(url, follow=True)
        new_password = secrets.token_urlsafe(20)
        recovery.post(
            stage.request["PATH_INFO"],
            {"password1": new_password, "password2": new_password},
        )
        self.teacher.user.refresh_from_db()
        self.assertTrue(self.teacher.user.check_password(new_password))
        self.assertEqual(existing.get(reverse("groups")).status_code, 302)
        self.assertNotContains(Client().get(url, follow=True), 'name="password1"')

    def test_school_switch_and_csrf(self):
        second = Employee.objects.create(
            user=self.teacher.user,
            school=self.b,
            role="instructor",
            name="Совместитель",
            terms_version="test",
        )
        assigned = Group.objects.create(name="Суббота", instructor=second)
        client = self.signed_in(self.teacher)
        self.assertNotContains(client.get(reverse("groups")), assigned.name)
        client.post(reverse("switch"), {"school": self.b.pk})
        self.assertContains(client.get(reverse("groups")), assigned.name)
        self.assertNotContains(client.get(reverse("groups")), self.group.name)
        strict = Client(enforce_csrf_checks=True)
        strict.force_login(self.teacher.user)
        self.assertEqual(
            strict.post(reverse("new_group"), {"name": "Лишняя"}).status_code, 403
        )

    def test_mail_outage_leaves_access_revoked_and_notice_retryable(self):
        from smtplib import SMTPException
        from unittest.mock import patch

        from .models import AccessNotice
        from .notices import deliver

        owner = self.signed_in(self.owner)
        client = self.signed_in(self.teacher)
        with patch("portal.notices.send_mail", side_effect=SMTPException):
            owner.post(reverse("disable", args=[self.teacher.pk]))
        self.assertEqual(
            client.get(reverse("group", args=[self.group.pk])).status_code, 403
        )
        self.assertEqual(AccessNotice.objects.count(), 2)
        for notice in AccessNotice.objects.all():
            self.assertTrue(deliver(notice.pk))
        self.assertEqual(AccessNotice.objects.count(), 0)
        self.assertEqual(len(mail.outbox), 2)
