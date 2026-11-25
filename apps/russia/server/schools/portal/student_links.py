import re
from urllib.parse import quote, unquote, urlencode


LAUNCH_HOST = "join.pdd-drive.app"
INVITE_PATH = re.compile(
    r"/join/(?P<invite>my|[23456789A-HJ-NP-Z]{10}|"
    r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}:[A-Za-z0-9_-]{43})/?"
)


def student_app_link(invite="my"):
    return f"https://{LAUNCH_HOST}/join/{quote(invite, safe=':')}/"


def student_web_fallback(path):
    if path == "/student/":
        invite = "my"
    else:
        match = INVITE_PATH.fullmatch(unquote(path))
        if not match:
            return None
        invite = match["invite"]
    return "https://pdd-drive.app/app/?" + urlencode({"school_group": invite})
