import secrets
import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


class School(models.Model):
    name = models.CharField(max_length=100)
    active = models.BooleanField(default=True)


class Employee(models.Model):
    class Role(models.TextChoices):
        MANAGER = "manager", "Управляющий"
        INSTRUCTOR = "instructor", "Инструктор"

    school = models.ForeignKey(School, on_delete=models.PROTECT, related_name="staff")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="school_roles"
    )
    name = models.CharField(max_length=100)
    role = models.CharField(max_length=12, choices=Role.choices)
    active = models.BooleanField(default=True)
    accepted_at = models.DateTimeField(auto_now_add=True)
    terms_version = models.CharField(max_length=32)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["school", "user"], name="one_school_employee"
            )
        ]

    @property
    def manager(self):
        return self.role == self.Role.MANAGER

    def __str__(self):
        return self.name


def new_group_code():
    return "".join(
        secrets.choice("23456789ABCDEFGHJKLMNPQRSTUVWXYZ") for _ in range(10)
    )


class Group(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    instructor = models.ForeignKey(
        Employee, on_delete=models.PROTECT, related_name="groups"
    )
    name = models.CharField(max_length=90)
    created_at = models.DateTimeField(auto_now_add=True)
    archived = models.BooleanField(default=False)
    invite_code = models.CharField(
        max_length=10, null=True, unique=True, default=new_group_code
    )
    # Changing this nonce invalidates the signed public link without storing its bearer token.
    invite_nonce = models.UUIDField(
        default=uuid.uuid4, null=True, editable=False, unique=True
    )


class Learner(models.Model):
    """Membership history. Legacy demo rows have no PDD account."""

    group = models.ForeignKey(Group, on_delete=models.PROTECT, related_name="learners")
    name = models.CharField(max_length=100)
    joined_at = models.DateTimeField(default=timezone.now)
    account_id = models.CharField(max_length=190, null=True)
    ended_at = models.DateTimeField(null=True)
    join_method = models.CharField(max_length=8, default="")
    consent_version = models.CharField(max_length=32, default="")

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["account_id"],
                condition=models.Q(ended_at__isnull=True, account_id__isnull=False),
                name="one_current_learner_group",
            )
        ]


class SchoolAttribution(models.Model):
    membership = models.OneToOneField(Learner, on_delete=models.PROTECT)
    school = models.ForeignKey(School, on_delete=models.PROTECT)
    started_at = models.DateTimeField()
    ended_at = models.DateTimeField(null=True)
    rules_version = models.CharField(max_length=32)


class StaffInvite(models.Model):
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name="invites")
    email = models.EmailField()
    sender = models.ForeignKey(Employee, on_delete=models.PROTECT)
    digest = models.CharField(max_length=64, unique=True)
    expires_at = models.DateTimeField()

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["school", "email"], name="one_addressed_invite"
            )
        ]


class Event(models.Model):
    school = models.ForeignKey(School, on_delete=models.PROTECT)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    action = models.CharField(max_length=40)
    subject = models.CharField(max_length=100, blank=True)
    at = models.DateTimeField(auto_now_add=True)


class AccessNotice(models.Model):
    email = models.EmailField()
    subject = models.CharField(max_length=120)
    body = models.TextField()
