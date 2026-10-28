"""Django settings for the retail POS + storefront backend.

Every secret comes from the environment. See `.env.example`.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import dj_database_url
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent
TESTING = len(sys.argv) > 1 and sys.argv[1] == "test"


def env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


def env_bool(name: str, default: bool = False) -> bool:
    raw = env(name)
    if not raw:
        return default
    return raw.lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    try:
        return int(env(name) or default)
    except ValueError:
        return default


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in env(name, default).split(",") if item.strip()]


DEBUG = env_bool("DJANGO_DEBUG", False)

SECRET_KEY = env("DJANGO_SECRET_KEY")
if not SECRET_KEY:
    if DEBUG or TESTING:
        SECRET_KEY = "dev-only-insecure-secret-key-change-me"
    else:
        raise ImproperlyConfigured("DJANGO_SECRET_KEY is required when DJANGO_DEBUG is off.")

# Staff PINs are only 4 digits, so they are keyed with this server-side pepper
# (HMAC) instead of being stored with a salt anyone could brute-force offline.
PIN_PEPPER = env("PIN_PEPPER") or SECRET_KEY

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
render_host = env("RENDER_EXTERNAL_HOSTNAME")
if render_host:
    ALLOWED_HOSTS.append(render_host)
if DEBUG or TESTING:
    ALLOWED_HOSTS.append("testserver")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "django_filters",
    "apps.common",
    "apps.accounts",
    "apps.catalog",
    "apps.customers",
    "apps.sales",
    "apps.payments",
    "apps.cash",
    "apps.timeclock",
    "apps.storefront",
    "apps.catalog_import",
    "apps.notifications",
    "apps.reports",
    "apps.sync",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.gzip.GZipMiddleware",
    "django.middleware.http.ConditionalGetMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
APPEND_SLASH = False

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

DATABASES = {
    "default": dj_database_url.config(
        default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}",
        conn_max_age=env_int("DB_CONN_MAX_AGE", 600),
        conn_health_checks=True,
    )
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 10}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
]

LANGUAGE_CODE = "fr"
TIME_ZONE = "America/Port-au-Prince"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_ROOT = Path(env("MEDIA_ROOT") or BASE_DIR / "media")
MEDIA_URL = "media/"

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": (
            "django.contrib.staticfiles.storage.StaticFilesStorage"
            if DEBUG or TESTING
            else "whitenoise.storage.CompressedManifestStaticFilesStorage"
        )
    },
}

# Vitrine publishes and catalog imports carry base64 photos and documents.
DATA_UPLOAD_MAX_MEMORY_SIZE = 25 * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024

redis_url = env("REDIS_URL")
CACHES = {
    "default": (
        {"BACKEND": "django.core.cache.backends.redis.RedisCache", "LOCATION": redis_url}
        if redis_url
        else {"BACKEND": "django.core.cache.backends.locmem.LocMemCache", "LOCATION": "retail-pos"}
    )
}

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "apps.accounts.authentication.StaffTokenAuthentication",
        "apps.accounts.authentication.FirebaseStaffAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["apps.accounts.permissions.IsStaff"],
    "DEFAULT_RENDERER_CLASSES": (
        ["rest_framework.renderers.JSONRenderer", "rest_framework.renderers.BrowsableAPIRenderer"]
        if DEBUG
        else ["rest_framework.renderers.JSONRenderer"]
    ),
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser", "rest_framework.parsers.MultiPartParser"],
    "DEFAULT_PAGINATION_CLASS": "apps.common.pagination.StandardPagination",
    "PAGE_SIZE": 50,
    "DEFAULT_FILTER_BACKENDS": [
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ],
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
        "rest_framework.throttling.ScopedRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": env("THROTTLE_ANON", "120/min"),
        "user": env("THROTTLE_USER", "1200/min"),
        "pin": "10/min",
        "pair": "10/min",
        "phone_code": "5/min",
        "phone_verify": "10/min",
        "storefront_order": "30/min",
        "storefront_pay": "30/min",
        "legacy_payments": "60/min",
        "catalog_import": "10/hour",
    },
    "EXCEPTION_HANDLER": "apps.common.exceptions.api_exception_handler",
    "COERCE_DECIMAL_TO_STRING": False,
    "UNAUTHENTICATED_USER": None,
    "TEST_REQUEST_DEFAULT_FORMAT": "json",
}

CORS_ALLOWED_ORIGINS = env_list("CORS_ALLOWED_ORIGINS")
CORS_ALLOW_ALL_ORIGINS = DEBUG or env_bool("CORS_ALLOW_ALL_ORIGINS", False)
CORS_ALLOW_HEADERS = [
    "accept",
    "authorization",
    "content-type",
    "idempotency-key",
    "stripe-signature",
    "x-business-id",
    "x-shop-key",
]
CORS_PREFLIGHT_MAX_AGE = 600

if not DEBUG and not TESTING:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SECURE_SSL_REDIRECT = env_bool("SECURE_SSL_REDIRECT", True)
    SECURE_REDIRECT_EXEMPT = [r"^health$"]
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = env_int("SECURE_HSTS_SECONDS", 31536000)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"
CSRF_TRUSTED_ORIGINS = env_list("CSRF_TRUSTED_ORIGINS")

ADMIN_URL = env("DJANGO_ADMIN_URL", "admin/")

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s %(name)s %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": env("LOG_LEVEL", "INFO")},
    "loggers": {
        "django.db.backends": {"level": "WARNING"},
        "django.request": {"level": "ERROR" if TESTING else "WARNING"},
    },
}

# ── Business rules ─────────────────────────────────────────────────────────────
DEFAULT_DAY_USD_RATE = float(env("DAY_USD_RATE") or 135)
STAFF_SESSION_HOURS = env_int("STAFF_SESSION_HOURS", 12)
OWNER_SESSION_DAYS = env_int("OWNER_SESSION_DAYS", 30)
DEVICE_INVITE_HOURS = 24
DEVICE_OFFLINE_WINDOW_DAYS = 14
PIN_MAX_ATTEMPTS = env_int("PIN_MAX_ATTEMPTS", 5)
PIN_LOCK_MINUTES = env_int("PIN_LOCK_MINUTES", 5)

# ── Firebase ───────────────────────────────────────────────────────────────────
# FIREBASE_CREDENTIALS_JSON: service-account JSON (inline or a file path).
FIREBASE_CREDENTIALS_JSON = env("FIREBASE_CREDENTIALS_JSON")
FIREBASE_PROJECT_ID = env("FIREBASE_PROJECT_ID")
# Accepts `dev:<uid>` tokens until Firebase exists. Never honored outside DEBUG/tests.
FIREBASE_DEV_MODE = (DEBUG or TESTING) and env_bool("FIREBASE_DEV_MODE", True)

# ── Storefront shoppers ────────────────────────────────────────────────────────
SHOPPER_SESSION_DAYS = env_int("SHOPPER_SESSION_DAYS", 90)
# console | twilio | firebase
PHONE_VERIFICATION_BACKEND = env("PHONE_VERIFICATION_BACKEND", "console")
# The vitrine accepted any code before SMS existed. Only allowed in DEBUG/tests.
STOREFRONT_ACCEPT_ANY_CODE = (DEBUG or TESTING) and env_bool("STOREFRONT_ACCEPT_ANY_CODE", True)
PHONE_CODE_TTL_MINUTES = 10
PHONE_CODE_MAX_ATTEMPTS = 5
TWILIO_ACCOUNT_SID = env("TWILIO_ACCOUNT_SID")
TWILIO_AUTH_TOKEN = env("TWILIO_AUTH_TOKEN")
TWILIO_VERIFY_SERVICE_SID = env("TWILIO_VERIFY_SERVICE_SID")
STOREFRONT_RESERVATION_MINUTES = env_int("STOREFRONT_RESERVATION_MINUTES", 60)
STOREFRONT_PUBLIC_URL = env("STOREFRONT_URL", "https://retail-pos-storefront.onrender.com")
# Lets the current POS build publish with only X-Shop-Key, as it does today.
STOREFRONT_LEGACY_PUBLISH = env_bool("STOREFRONT_LEGACY_PUBLISH", True)

# ── Payments ───────────────────────────────────────────────────────────────────
STRIPE_SECRET_KEY = env("STRIPE_SECRET_KEY")
STRIPE_WEBHOOK_SECRET = env("STRIPE_WEBHOOK_SECRET")
STRIPE_PUBLISHABLE_KEY = env("STRIPE_PUBLISHABLE_KEY")
MONCASH_CLIENT_ID = env("MONCASH_CLIENT_ID")
MONCASH_SECRET = env("MONCASH_SECRET")
MONCASH_BASE_URL = env("MONCASH_BASE_URL", "https://moncashbutton.digicelgroup.com").rstrip("/")
PUBLIC_BASE_URL = (env("PUBLIC_BASE_URL") or env("RENDER_EXTERNAL_URL")).rstrip("/")
# The current POS calls /payments/* without credentials. Turn off once it signs in.
LEGACY_PAYMENTS_OPEN = env_bool("LEGACY_PAYMENTS_OPEN", True)

# ── AI catalog import ──────────────────────────────────────────────────────────
CLAUDE_API_SECRET_KEY = env("CLAUDE_API_SECRET_KEY")
CLAUDE_MODEL = env("CLAUDE_MODEL", "claude-sonnet-4-5")
