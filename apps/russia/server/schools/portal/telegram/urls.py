from django.urls import path

from . import views

urlpatterns = [
    path("telegram/login/", views.start, name="telegram_login"),
    path("telegram/check/", views.check, name="telegram_check"),
]
