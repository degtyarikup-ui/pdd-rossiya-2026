from django.core import signing
from django.core.cache import cache
from django.test import TestCase

from .membership import CONSENT_VERSION, student_group
from .models import Employee, Group, Learner, School, SchoolAttribution
from .student_links import student_app_link, student_web_fallback
from urllib.parse import parse_qs, urlsplit
from django.contrib.auth import get_user_model


class StudentMembershipTests(TestCase):
    def test_links_keep_the_invitation_on_web_fallback(self):
        token = self.token(self.first)
        for value in ("my", token, self.first.invite_code):
            launch = urlsplit(student_app_link(value))
            self.assertEqual(launch.hostname, "join.pdd-drive.app")
            target = urlsplit(student_web_fallback(launch.path.replace(":", "%3A")))
            self.assertEqual((target.hostname, target.path), ("pdd-drive.app", "/app/"))
            self.assertEqual(parse_qs(target.query), {"school_group": [value]})
        self.assertEqual(
            student_web_fallback("/student/"), student_web_fallback("/join/my/")
        )
        self.assertIsNone(student_web_fallback("/accounts/login/"))
        self.assertIsNone(student_web_fallback("/join/not-an-invitation/"))

    @classmethod
    def setUpTestData(cls):
        teacher = get_user_model().objects.create_user(username="teacher")

        def make_group(label):
            school = School.objects.create(name=label)
            staff = Employee.objects.create(
                user=teacher, school=school, name="Ирина", role="manager"
            )
            return Group.objects.create(name="Вечерняя", instructor=staff)

        cls.first, cls.second = make_group("Старт"), make_group("Вираж")

    def setUp(self):
        cache.clear()

    def token(self, group):
        return signing.Signer(salt="schools.group-invite.v1").sign(
            str(group.invite_nonce)
        )

    def call(self, action, data, account="google_1"):
        return student_group(account, action, data)

    def confirmation(self, invite, version="0"):
        return dict(
            invite=invite, name="Анна", version=version, consentVersion=CONSENT_VERSION
        )

    def test_link_code_transfer_leave_and_delayed_requests(self):
        token = self.token(self.first)
        status, preview = self.call("preview", {"invite": token})
        self.assertEqual(status, 200)
        self.assertEqual(preview["group"]["school"], "Старт")
        self.assertFalse(Learner.objects.exists())
        first = self.confirmation(token)
        self.assertEqual(self.call("join", {**first, "consentVersion": ""})[0], 409)
        status, joined = self.call("join", first)
        self.assertEqual(status, 200)
        self.assertEqual(self.call("join", first), (200, joined))
        self.assertEqual(self.call("mine", {}, "yandex_1")[1]["current"], None)
        second = self.confirmation(self.second.invite_code.lower(), joined["version"])
        self.assertEqual(self.call("join", {**second, "version": "0"})[0], 409)
        status, moved = self.call("join", second)
        self.assertEqual(status, 200)
        old, new = Learner.objects.order_by("pk")
        self.assertEqual((old.join_method, new.join_method), ("link", "code"))
        self.assertEqual(old.ended_at, new.joined_at)
        self.assertEqual(
            old.schoolattribution.ended_at, new.schoolattribution.started_at
        )
        self.assertEqual(self.call("leave", {"version": joined["version"]})[0], 409)
        self.assertEqual(self.call("join", first)[0], 409)
        self.assertEqual(
            self.call("leave", {"version": moved["version"]})[1]["current"], None
        )
        self.assertEqual(self.call("join", second)[0], 409)
        self.assertFalse(Learner.objects.filter(ended_at=None).exists())
        self.assertFalse(SchoolAttribution.objects.filter(ended_at=None).exists())

    def test_revoked_invite_does_not_unenroll_or_allow_new_members(self):
        token = self.token(self.first)
        self.call("join", self.confirmation(token))
        Group.objects.filter(pk=self.first.pk).update(invite_nonce=None)
        for invitation in (token, self.first.invite_code):
            self.assertEqual(
                self.call("join", self.confirmation(invitation), "apple_new")[0], 410
            )
        self.assertEqual(self.call("mine", {})[1]["current"]["id"], str(self.first.pk))
        self.second.instructor.school.active = False
        self.second.instructor.school.save()
        self.assertEqual(
            self.call("preview", {"invite": self.second.invite_code})[0], 410
        )

    def test_manual_code_attempts_are_limited_per_account(self):
        for _ in range(25):
            self.assertEqual(self.call("preview", {"invite": "AAAAAAAAAA"})[0], 410)
        self.assertEqual(
            self.call("preview", {"invite": self.first.invite_code})[0], 429
        )
        self.assertEqual(
            self.call("preview", {"invite": self.first.invite_code}, "google_2")[0], 200
        )
