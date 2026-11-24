from allauth.socialaccount.providers.apple.views import oauth2_finish_login
from allauth.socialaccount.providers.yandex.views import (
    oauth2_callback as yandex_callback,
)
from django.conf import settings
from django.urls import include, path
from django.views.generic import TemplateView

from . import pdd_login, social
from . import views as v

urlpatterns = [
    path("", v.home, name="home"),
    path("accounts/", include("allauth.account.urls")),
    path("accounts/2fa/", include("allauth.mfa.urls")),
    path("accounts/social/", include("allauth.socialaccount.urls")),
    path("accounts/pdd/login/", pdd_login.start, name="pdd_login"),
    path("accounts/pdd/callback/", pdd_login.callback, name="pdd_callback"),
    *(
        [
            path("accounts/yandex/login/", social.yandex_start, name="yandex_login"),
            path(
                "accounts/yandex/login/callback/",
                yandex_callback,
                name="yandex_callback",
            ),
            path("accounts/", include("portal.telegram.urls")),
            path("accounts/google/login/", social.google_start, name="google_login"),
            path(
                "accounts/google/verify/",
                social.google_finish,
                name="school_google_finish",
            ),
            path("accounts/apple/login/", social.apple_start, name="apple_login"),
            path(
                "accounts/apple/login/callback/",
                social.apple_callback,
                name="apple_callback",
            ),
            path(
                "accounts/apple/login/callback/finish/",
                oauth2_finish_login,
                name="apple_finish_callback",
            ),
        ]
        if settings.LOCAL
        else [
            path(
                f"accounts/{provider}/login/", pdd_login.start, name=f"{provider}_login"
            )
            for provider in sorted(pdd_login.PROVIDERS)
        ]
    ),
    path("start/", v.start, name="start"),
    path("switch/", v.switch, name="switch"),
    path("groups/", v.group_list, name="groups"),
    path("groups/new/", v.group_edit, name="new_group"),
    path("groups/<uuid:pk>/", v.group_detail, name="group"),
    path("groups/<uuid:pk>/edit/", v.group_edit, name="edit_group"),
    path("groups/<uuid:pk>/archive/", v.archive, name="archive"),
    path("groups/<uuid:pk>/link/", v.group_invite_toggle, name="group_link"),
    path("groups/<uuid:pk>/qr.svg", v.qr, name="qr"),
    path("learners/", v.learners, name="learners"),
    path("invitations/", v.invitations, name="invitations"),
    path("team/", v.team, name="team"),
    path("team/invite/", v.invite, name="invite"),
    path("team/invites/<int:pk>/delete/", v.cancel_invite, name="cancel_invite"),
    path("team/<int:pk>/disable/", v.disable_staff, name="disable"),
    path("staff/<str:token>/", v.staff_link, name="staff_link"),
    path("invitation/", v.accept, name="accept"),
    path("invitation/leave/", v.leave_invitation, name="leave_invitation"),
    path("join/<str:token>/", v.join, name="join"),
    path("finance/", v.finance, name="finance"),
    path("settings/", v.preferences, name="settings"),
    path("art/car.png", v.car, name="car"),
    path(
        "terms/", TemplateView.as_view(template_name="portal/terms.html"), name="terms"
    ),
]
