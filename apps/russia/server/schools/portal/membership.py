import re
import uuid

from django.core import signing
from django.core.cache import cache
from django.db import transaction
from django.utils import timezone

from .models import Group, Learner, SchoolAttribution

CONSENT_VERSION = "group-2026-11-25"
RULES_VERSION = "school-30-v1"
CODE = re.compile(r"[23456789A-HJ-NP-Z]{10}")
SIGNER_SALT = "schools.group-invite.v1"


def available_groups():
    return Group.objects.select_related("instructor__school").filter(
        archived=False, instructor__active=True, instructor__school__active=True
    )


def group_by_invite(token):
    if not isinstance(token, str) or len(token) > 100:
        return None
    try:
        nonce = uuid.UUID(signing.Signer(salt=SIGNER_SALT).unsign(token))
    except (ValueError, signing.BadSignature):
        return None
    return available_groups().filter(invite_nonce=nonce).first()


def group_info(group):
    return {
        "id": str(group.pk),
        "name": group.name,
        "school": group.instructor.school.name,
        "instructor": group.instructor.name,
    }


@transaction.atomic
def student_group(account_id, operation, data):
    """Called only by the app API after it resolves the student's session."""
    latest = (
        Learner.objects.select_related("group__instructor__school")
        .filter(account_id=account_id)
        .order_by("-pk")
        .first()
    )
    active = latest if latest and not latest.ended_at else None
    version = f"{latest.pk}:{'in' if active else 'out'}" if latest else "0"

    def snapshot():
        return {
            "current": group_info(active.group) if active else None,
            "version": version,
        }

    if operation == "mine":
        return 200, snapshot()
    if operation == "leave":
        if not active:
            return 200, snapshot()
        if data.get("version") != version:
            return 409, {"error": "membership_changed"}
        end_membership(active, timezone.now())
        return 200, {"current": None, "version": f"{active.pk}:out"}
    if operation not in ("preview", "join"):
        return 400, {"error": "invalid_request"}

    invite = data.get("invite")
    if not isinstance(invite, str) or len(invite) > 100:
        return 400, {"error": "invalid_invite"}
    manual = ":" not in invite
    if manual:
        key = f"school-group-code:{account_id}"
        cache.add(key, 0, 300)
        if cache.incr(key) > 25:
            return 429, {"error": "too_many_attempts"}
        code = invite.replace("-", "").replace(" ", "").upper()
        group = (
            available_groups()
            .filter(invite_code=code, invite_nonce__isnull=False)
            .first()
            if CODE.fullmatch(code)
            else None
        )
    else:
        group = group_by_invite(invite)
    if not group:
        return 410, {"error": "invite_unavailable"}
    if operation == "preview":
        return 200, {
            **snapshot(),
            "group": group_info(group),
            "consentVersion": CONSENT_VERSION,
        }
    if active and active.group_id == group.pk:
        return 200, snapshot()
    if data.get("version") != version or data.get("consentVersion") != CONSENT_VERSION:
        return 409, {"error": "membership_changed"}
    name = data.get("name")
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
        return 400, {"error": "name_required"}
    confirmed = timezone.now()
    if active:
        end_membership(active, confirmed)
    member = Learner.objects.create(
        account_id=account_id,
        group=group,
        name=name.strip(),
        joined_at=confirmed,
        join_method="code" if manual else "link",
        consent_version=CONSENT_VERSION,
    )
    SchoolAttribution.objects.create(
        membership=member,
        school=group.instructor.school,
        started_at=member.joined_at,
        rules_version=RULES_VERSION,
    )
    return 200, {"current": group_info(group), "version": f"{member.pk}:in"}


def end_membership(member, at):
    member.ended_at = at
    member.save(update_fields=["ended_at"])
    SchoolAttribution.objects.filter(membership=member).update(ended_at=member.ended_at)
