import secrets
import uuid
from datetime import timedelta
from hashlib import sha256
from smtplib import SMTPException

import qrcode
from allauth.account.models import EmailAddress
from allauth.core.ratelimit import consume_or_429
from django.conf import settings
from django.contrib import messages
from django.contrib.auth import logout
from django.contrib.auth.decorators import login_required
from django.core import signing
from django.core.exceptions import PermissionDenied
from django.core.mail import send_mail
from django.db import transaction
from django.db.models import Count
from django.http import FileResponse, Http404, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_GET, require_http_methods, require_POST
from qrcode.image.svg import SvgPathImage

from .access import active_roles, groups_for, school_view
from .forms import (
    TERMS_VERSION,
    GroupForm,
    InviteForm,
    RenameSchoolForm,
    SchoolForm,
    TermsForm,
)
from .models import Employee, Event, Group, Learner, School, StaffInvite
from .notices import notify


def page(request, template, **context):
    employee = getattr(request, "employee", None)
    return render(
        request,
        "portal/" + template + ".html",
        {
            "employee": employee,
            "roles": active_roles(request.user) if employee else [],
            **context,
        },
    )


def form_page(request, form, title, action, section="", back="home", **extra):
    return page(
        request,
        "form",
        title=title,
        form=form,
        action=action,
        section=section,
        back=back,
        **extra,
    )


def log(employee, action, subject=""):
    Event.objects.create(
        school=employee.school, actor=employee.user, action=action, subject=str(subject)
    )


def ordered_groups(employee):
    return (
        groups_for(employee)
        .annotate(size=Count("learners"))
        .order_by("-created_at", "name")
    )


def group_link(request, group):
    if group.invite_nonce:
        token = signing.Signer(salt="schools.group-invite.v1").sign(
            str(group.invite_nonce)
        )
        return request.build_absolute_uri(reverse("join", args=[token]))
    return ""


@school_view
@require_GET
def home(request):
    if request.session.get("pending_staff"):
        return redirect("accept")
    staff = request.employee
    if not staff.manager:
        return redirect("groups")
    qs = ordered_groups(staff)
    return page(
        request,
        "home",
        title="Обзор",
        section="home",
        groups=qs[:4],
        group_count=qs.count(),
        learner_count=Learner.objects.filter(group__in=qs).count(),
        instructor_count=staff.school.staff.filter(
            active=True, role=Employee.Role.INSTRUCTOR
        ).count(),
    )


@login_required
@require_http_methods(["GET", "POST"])
def start(request):
    if request.session.get("pending_staff"):
        return redirect("accept")
    if active_roles(request.user).exists():
        return redirect("home")
    form = SchoolForm(request.POST if request.method == "POST" else None)
    if request.method == "POST" and form.is_valid():
        with transaction.atomic():
            if not active_roles(request.user).exists():
                school = School.objects.create(name=form.cleaned_data["school"])
                employee = Employee.objects.create(
                    school=school,
                    user=request.user,
                    name=form.cleaned_data["name"],
                    role=Employee.Role.MANAGER,
                    terms_version=TERMS_VERSION,
                )
                request.session["school_id"] = school.pk
                log(employee, "school_created")
        return redirect("home")
    return form_page(request, form, "Ваша автошкола", "Создать кабинет", terms=True)


@login_required
@require_POST
def switch(request):
    school_id = request.POST.get("school", "")
    if not school_id.isdecimal() or len(school_id) > 18:
        raise Http404
    role = get_object_or_404(active_roles(request.user), school_id=int(school_id))
    request.session["school_id"] = role.school_id
    return redirect("home")


@school_view
@require_GET
def group_list(request):
    employee = request.employee
    return page(
        request,
        "groups",
        title="Группы" if employee.manager else "Мои группы",
        section="groups",
        groups=ordered_groups(employee),
    )


@school_view
@require_http_methods(["GET", "POST"])
def group_edit(request, pk=None):
    employee = request.employee
    group = get_object_or_404(groups_for(employee), pk=pk) if pk else None
    if group and not employee.manager:
        raise PermissionDenied
    initial = {
        "instructor": group.instructor_id if group else employee.pk,
        "name": group.name if group else "",
    }
    form = GroupForm(
        request.POST if request.method == "POST" else None,
        initial=initial,
        employee=employee,
    )
    if request.method == "POST" and form.is_valid():
        instructor = form.cleaned_data.get("instructor", employee)
        if group:
            group.name, group.instructor = form.cleaned_data["name"], instructor
            group.save(update_fields=["name", "instructor"])
        else:
            group = Group.objects.create(
                instructor=instructor, name=form.cleaned_data["name"]
            )
        log(employee, "group_updated" if pk else "group_created", group.pk)
        return redirect("group", pk=group.pk)
    return form_page(
        request,
        form,
        "Изменить группу" if pk else "Новая группа",
        "Сохранить" if pk else "Создать группу",
        "groups",
        "groups",
    )


@school_view
@require_GET
def group_detail(request, pk):
    group = get_object_or_404(groups_for(request.employee), pk=pk)
    return page(
        request,
        "group",
        title=group.name,
        section="groups",
        group=group,
        link=group_link(request, group),
        learners=group.learners.order_by("name"),
    )


@school_view
@require_POST
def group_invite_toggle(request, pk):
    group = get_object_or_404(groups_for(request.employee), pk=pk)
    enable = request.POST.get("action") == "enable"
    if enable and group.invite_nonce is None:
        group.invite_nonce = uuid.uuid4()
    elif not enable:
        group.invite_nonce = None
    group.save(update_fields=["invite_nonce"])
    log(
        request.employee,
        "group_link_enabled" if enable else "group_link_revoked",
        group.pk,
    )
    return redirect("group", pk=pk)


@school_view(manager=True)
@require_POST
def archive(request, pk):
    group = get_object_or_404(groups_for(request.employee), pk=pk)
    group.archived = True
    group.invite_nonce = None
    group.save(update_fields=["archived", "invite_nonce"])
    log(request.employee, "group_archived", group.pk)
    return redirect("groups")


@school_view
@require_GET
def qr(request, pk):
    group = get_object_or_404(
        groups_for(request.employee), pk=pk, invite_nonce__isnull=False
    )
    code = qrcode.make(group_link(request, group), image_factory=SvgPathImage)
    return HttpResponse(code.to_string(), content_type="image/svg+xml")


@require_GET
def join(request, token):
    try:
        nonce = uuid.UUID(signing.Signer(salt="schools.group-invite.v1").unsign(token))
        group = Group.objects.select_related("instructor__school").get(
            invite_nonce=nonce,
            archived=False,
            instructor__active=True,
            instructor__school__active=True,
        )
    except (ValueError, signing.BadSignature, Group.DoesNotExist):
        return render(request, "portal/expired.html", status=410)
    return page(request, "join", title=group.name, group=group)


@school_view
@require_GET
def learners(request):
    rows = (
        Learner.objects.filter(group__in=groups_for(request.employee))
        .select_related("group")
        .order_by("name")
    )
    return page(request, "learners", title="Ученики", section="learners", learners=rows)


@school_view
@require_GET
def invitations(request):
    return page(
        request,
        "invitations",
        title="Приглашения",
        section="invitations",
        groups=ordered_groups(request.employee),
    )


@school_view(manager=True)
@require_GET
def team(request):
    school = request.employee.school
    return page(
        request,
        "team",
        title="Инструкторы",
        section="team",
        instructors=school.staff.filter(
            role=Employee.Role.INSTRUCTOR, active=True
        ).order_by("name"),
        invites=school.invites.filter(expires_at__gt=timezone.now()).order_by("email"),
    )


def digest(token):
    return sha256(token.encode()).hexdigest()


def mail(subject, body, recipient):
    send_mail(subject, body, settings.DEFAULT_FROM_EMAIL, [recipient])


@school_view(manager=True)
@require_http_methods(["GET", "POST"])
def invite(request):
    staff = request.employee
    form = InviteForm(request.POST if request.method == "POST" else None)
    if request.method == "POST" and form.is_valid():
        limited = consume_or_429(request, action="staff_invite", user=request.user)
        if limited:
            return limited
        email = form.cleaned_data["email"].lower()
        if staff.school.staff.filter(active=True, user__email__iexact=email).exists():
            form.add_error("email", "Этот сотрудник уже в школе.")
        else:
            token = secrets.token_urlsafe(32)
            try:
                with transaction.atomic():
                    StaffInvite.objects.update_or_create(
                        school=staff.school,
                        email=email,
                        defaults={
                            "sender": staff,
                            "digest": digest(token),
                            "expires_at": timezone.now() + timedelta(days=3),
                        },
                    )
                    url = request.build_absolute_uri(
                        reverse("staff_link", args=[token])
                    )
                    mail(
                        "Приглашение в автошколу",
                        f"{staff.name} приглашает вас в «{staff.school.name}» как инструктора.\n\n{url}\n\nСсылка действует три дня.",
                        email,
                    )
            except (SMTPException, OSError):
                form.add_error(None, "Не удалось отправить письмо. Попробуйте ещё раз.")
                return form_page(
                    request,
                    form,
                    "Пригласить инструктора",
                    "Отправить приглашение",
                    "team",
                    "team",
                )
            log(staff, "staff_invited")
            messages.success(request, "Приглашение отправлено")
            return redirect("team")
    return form_page(
        request, form, "Пригласить инструктора", "Отправить приглашение", "team", "team"
    )


@school_view(manager=True)
@require_POST
def cancel_invite(request, pk):
    invite = get_object_or_404(request.employee.school.invites, pk=pk)
    invite.delete()
    log(request.employee, "staff_invite_revoked", pk)
    return redirect("team")


@school_view(manager=True)
@require_POST
def disable_staff(request, pk):
    employee = request.employee
    person = get_object_or_404(
        employee.school.staff, pk=pk, role=Employee.Role.INSTRUCTOR, active=True
    )
    person.active = False
    person.save(update_fields=["active"])
    person.groups.update(instructor=employee)
    log(employee, "staff_disabled", person.pk)
    notify(
        employee.user.email,
        "Доступ инструктора отключён",
        f"Доступ {person.name} к кабинету «{employee.school.name}» закрыт.",
    )
    notify(
        person.user.email,
        "Доступ к кабинету закрыт",
        f"Ваш доступ к кабинету «{employee.school.name}» закрыт.",
    )
    return redirect("team")


def valid_staff_invite(key):
    return (
        StaffInvite.objects.select_related("school", "sender")
        .filter(
            digest=key,
            expires_at__gt=timezone.now(),
            school__active=True,
            sender__active=True,
            sender__role=Employee.Role.MANAGER,
        )
        .first()
    )


@require_GET
def staff_link(request, token):
    key = digest(token)
    if not valid_staff_invite(key):
        return render(request, "portal/expired.html", status=410)
    request.session["pending_staff"] = key
    return redirect("accept")


@require_http_methods(["GET", "POST"])
@transaction.atomic
def accept(request):
    entry = valid_staff_invite(request.session.get("pending_staff", ""))
    if not entry:
        request.session.pop("pending_staff", None)
        return render(request, "portal/expired.html", status=410)
    if not request.user.is_authenticated:
        return page(request, "invite_login", title="Приглашение", entry=entry)
    if not EmailAddress.objects.filter(
        user=request.user, email__iexact=entry.email, verified=True
    ).exists():
        return render(request, "portal/wrong_email.html", status=403)
    form = TermsForm(request.POST if request.method == "POST" else None)
    if request.method == "POST" and form.is_valid():
        with transaction.atomic():
            if not StaffInvite.objects.filter(
                pk=entry.pk, digest=entry.digest, expires_at__gt=timezone.now()
            ).delete()[0]:
                return render(request, "portal/expired.html", status=410)
            member, created = Employee.objects.get_or_create(
                school=entry.school,
                user=request.user,
                defaults={
                    "name": form.cleaned_data["name"],
                    "role": Employee.Role.INSTRUCTOR,
                    "terms_version": TERMS_VERSION,
                },
            )
            if not created and not member.active:
                member.name, member.active, member.terms_version = (
                    form.cleaned_data["name"],
                    True,
                    TERMS_VERSION,
                )
                member.save(update_fields=["name", "active", "terms_version"])
            log(member, "staff_joined", member.pk)
            notify(
                entry.sender.user.email,
                "Инструктор принял приглашение",
                f"{member.name} присоединился к «{entry.school.name}».",
            )
            request.session["school_id"] = entry.school_id
            request.session.pop("pending_staff", None)
        return redirect("home")
    return form_page(
        request,
        form,
        f"Вступить в «{entry.school.name}»",
        "Принять приглашение",
        terms=True,
    )


@require_POST
def leave_invitation(request):
    key = request.session.pop("pending_staff", None)
    if request.POST.get("change_account") and key and valid_staff_invite(key):
        logout(request)
        request.session["pending_staff"] = key
        return redirect("accept")
    return redirect("home")


@school_view(manager=True)
@require_GET
def finance(request):
    return page(request, "finance", title="Финансы", section="finance")


@school_view
@require_http_methods(["GET", "POST"])
def preferences(request):
    employee = request.employee
    form = RenameSchoolForm(
        request.POST if request.method == "POST" else None,
        initial={"school": employee.school.name},
    )
    if request.method == "POST":
        if not employee.manager:
            raise PermissionDenied
        if form.is_valid():
            employee.school.name = form.cleaned_data["school"]
            employee.school.save(update_fields=["name"])
            log(employee, "school_renamed")
            messages.success(request, "Название сохранено")
            return redirect("settings")
    return page(request, "settings", title="Настройки", section="settings", form=form)


@require_GET
def car(request):
    return FileResponse(
        (settings.PRODUCT / "assets/images/onboarding_car.png").open("rb"),
        content_type="image/png",
    )
