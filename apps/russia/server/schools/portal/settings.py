import os
import secrets
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
PRODUCT = BASE.parents[1]
LOCAL = os.environ.get("PDD_SCHOOLS_LOCAL") == "1"
STATE = Path(os.environ["PDD_SCHOOLS_STATE"]).resolve()
STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
if LOCAL:
    key_file = STATE / "local.key"
    if not key_file.exists():
        try:
            with key_file.open("x") as f:
                key_file.chmod(0o600)
                f.write(secrets.token_urlsafe(64))
        except FileExistsError:
            pass
    SECRET_KEY = key_file.read_text()
else:
    SECRET_KEY = os.environ["PDD_SCHOOLS_SECRET"]

DEBUG = LOCAL
ALLOWED_HOSTS = (
    ["localhost", "127.0.0.1", "[::1]"] if LOCAL else ["schools.pdd-drive.app"]
)
ROOT_URLCONF = "portal.urls"
INSTALLED_APPS = [
    "portal",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "allauth",
    "allauth.account",
    "allauth.mfa",
    "allauth.socialaccount",
    "allauth.socialaccount.providers.google",
    "allauth.socialaccount.providers.yandex",
    "allauth.socialaccount.providers.apple",
]
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "portal.access.private_responses",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "allauth.account.middleware.AccountMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": STATE / "schools.sqlite3",
        "OPTIONS": {"transaction_mode": "IMMEDIATE", "timeout": 10},
    }
}
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.db.DatabaseCache",
        "LOCATION": "school_limits",
    }
}
TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "portal.social.provider_names",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ]
        },
    }
]
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTHENTICATION_BACKENDS = ["allauth.account.auth_backends.AuthenticationBackend"]
AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 10},
    },
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
]
LANGUAGE_CODE = "ru"
TIME_ZONE = "Europe/Moscow"
USE_TZ = True
LOGIN_URL = "account_login"
LOGIN_REDIRECT_URL = "/"
LOGOUT_REDIRECT_URL = "/accounts/login/"
ACCOUNT_LOGIN_METHODS = {"email"}
ACCOUNT_SIGNUP_FIELDS = ["email*", "password1*"]
ACCOUNT_EMAIL_VERIFICATION = "mandatory"
ACCOUNT_LOGIN_ON_EMAIL_CONFIRMATION = True
ACCOUNT_EMAIL_NOTIFICATIONS = True
ACCOUNT_RATE_LIMITS = {
    "staff_invite": "15/h/user",
    "school_google": "20/m/ip",
    "school_bot_start": "10/m/ip",
    "school_bot_check": "45/m/ip",
}
ACCOUNT_SESSION_REMEMBER = False
ACCOUNT_EMAIL_SUBJECT_PREFIX = "[ПДД России] "
ACCOUNT_DEFAULT_HTTP_PROTOCOL = "http" if LOCAL else "https"
ACCOUNT_ADAPTER = "portal.access.AccountAdapter"
MFA_SUPPORTED_TYPES = ["totp", "recovery_codes"]
MFA_ADAPTER = "portal.access.MFAAdapter"
MFA_TOTP_ISSUER = "ПДД России · Автошколы"
PASSWORD_RESET_TIMEOUT = 3600
SESSION_COOKIE_NAME = "pdd_school_session" if LOCAL else "__Host-pdd_school_session"
CSRF_COOKIE_NAME = "pdd_school_csrf" if LOCAL else "__Host-pdd_school_csrf"
SESSION_COOKIE_HTTPONLY = CSRF_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE = CSRF_COOKIE_SECURE = not LOCAL
SESSION_COOKIE_AGE = 12 * 3600
SESSION_COOKIE_SAMESITE = CSRF_COOKIE_SAMESITE = "Lax"
SECURE_SSL_REDIRECT = not LOCAL
SECURE_HSTS_SECONDS = 0 if LOCAL else 31536000
SECURE_REFERRER_POLICY = "same-origin"

if LOCAL:
    EMAIL_BACKEND = "django.core.mail.backends.filebased.EmailBackend"
    EMAIL_FILE_PATH = STATE / "mail"
    DEFAULT_FROM_EMAIL = "schools@pdd.test"
else:
    EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
    EMAIL_HOST = os.environ["PDD_SCHOOLS_SMTP_HOST"]
    EMAIL_PORT = int(os.environ.get("PDD_SCHOOLS_SMTP_PORT", "587"))
    EMAIL_TIMEOUT = 8
    EMAIL_USE_TLS = True
    EMAIL_HOST_USER = os.environ["PDD_SCHOOLS_SMTP_USER"]
    EMAIL_HOST_PASSWORD = os.environ["PDD_SCHOOLS_SMTP_PASSWORD"]
    DEFAULT_FROM_EMAIL = os.environ["PDD_SCHOOLS_FROM"]
STATIC_URL = "/assets/"
STATICFILES_DIRS = [
    PRODUCT / "web_landing/ru/assets",
    ("auth-icons", PRODUCT / "assets/icons/auth"),
]
STATIC_ROOT = STATE / "static"


# Public app IDs match AuthService in the Russian client. Private credentials come from the host.
SCHOOL_GOOGLE_ID = os.environ.get(
    "PDD_SCHOOLS_GOOGLE_ID",
    "513938972930-a7sh1di6odgf77ijltu31lvpuhijcis1.apps.googleusercontent.com",
)
_bot_key_path = os.environ.get("PDD_SCHOOLS_BOT_BRIDGE_FILE")
SCHOOL_BOT_BRIDGE_KEY = (
    Path(_bot_key_path).read_text().strip()
    if _bot_key_path
    else os.environ.get("PDD_SCHOOLS_BOT_BRIDGE_KEY", "")
)
_apple_key_path = os.environ.get("PDD_SCHOOLS_APPLE_KEY_FILE")
SOCIALACCOUNT_PROVIDERS = {
    "google": {"APP": {"client_id": SCHOOL_GOOGLE_ID}},
    "yandex": {
        "OAUTH_PKCE_ENABLED": True,
        "APP": {
            "client_id": os.environ.get(
                "PDD_SCHOOLS_YANDEX_ID", "94aa539db4634e44bf0b209d9a2205d2"
            )
        },
    },
    "apple": {
        "APP": {
            "client_id": os.environ.get("PDD_SCHOOLS_APPLE_ID", "ru.pdd.pddapp.auth"),
            "key": os.environ.get("PDD_SCHOOLS_APPLE_TEAM", ""),
            "secret": os.environ.get("PDD_SCHOOLS_APPLE_KEY_ID", ""),
            "settings": {
                "certificate_key": Path(_apple_key_path).read_text()
                if _apple_key_path
                else ""
            },
        }
    },
}
SOCIALACCOUNT_STORE_TOKENS = False
SOCIALACCOUNT_EMAIL_AUTHENTICATION = False
SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT = False
SOCIALACCOUNT_LOGIN_ON_GET = False
