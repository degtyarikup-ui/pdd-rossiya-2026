import asyncio
import os
from hashlib import sha256
from pathlib import Path

import js
from pyodide.ffi import to_js
from workers import DurableObject, Response, WorkerEntrypoint, wsgi

STATE = Path("/tmp/school-portal")
DATABASE = STATE / "schools.sqlite3"
CHUNK = 65536


class SchoolPortal(DurableObject):
    """One writer for the pilot. Only acknowledged SQLite pages survive a restart."""

    def __init__(self, ctx, env):
        super().__init__(ctx, env)
        self.lock = asyncio.Lock()
        self.application = None
        self.file_header = None
        self.digests = []
        self.sql = ctx.storage.sql

    def restore(self):
        from django.core.management import call_command
        from django.core.wsgi import get_wsgi_application

        os.environ.update(
            {
                "DJANGO_SETTINGS_MODULE": "portal.settings",
                "DJANGO_ALLOW_ASYNC_UNSAFE": "true",
                "PDD_SCHOOLS_CLOUDFLARE": "1",
                "PDD_SCHOOLS_STATE": str(STATE),
                "PDD_SCHOOLS_SECRET": self.env.PORTAL_SECRET,
            }
        )
        STATE.mkdir(parents=True, exist_ok=True)
        self.sql.exec(
            "CREATE TABLE IF NOT EXISTS pages (n INTEGER PRIMARY KEY, data BLOB NOT NULL)"
        )
        self.digests = []
        self.file_header = None
        with DATABASE.open("wb") as db:
            for index, row in enumerate(
                self.sql.exec("SELECT n, data FROM pages ORDER BY n")
            ):
                if row.n != index:
                    raise RuntimeError("Incomplete school database")
                chunk = bytes(js.Uint8Array.new(row.data).to_py())
                db.write(chunk)
                self.digests.append(sha256(chunk).digest())
        django_application = get_wsgi_application()

        def application(environ, start_response):
            # Cloudflare sets CF-Connecting-IP at the public edge.
            environ["REMOTE_ADDR"] = environ.get("HTTP_CF_CONNECTING_IP", "")
            return django_application(environ, start_response)

        call_command("migrate", interactive=False, verbosity=0)
        self.checkpoint()
        self.application = application

    def checkpoint(self):
        # Django uses its normal SQLite backend, including savepoints and rollback.
        # Atomically persist changed chunks before sending the HTTP response.
        # The rollback journal backend increments the SQLite header change
        # counter on commit. Read-only requests need no full database scan.
        with DATABASE.open("rb") as db:
            header = db.read(100)
        if header == self.file_header:
            return
        digests = []

        def save():
            with DATABASE.open("rb") as db:
                while chunk := db.read(CHUNK):
                    index = len(digests)
                    digest = sha256(chunk).digest()
                    digests.append(digest)
                    if index >= len(self.digests) or digest != self.digests[index]:
                        self.sql.exec(
                            "INSERT OR REPLACE INTO pages VALUES (?, ?)",
                            index,
                            to_js(chunk),
                        )
            if len(digests) < len(self.digests):
                self.sql.exec("DELETE FROM pages WHERE n >= ?", len(digests))

        self.ctx.storage.transactionSync(save)
        self.digests = digests
        self.file_header = header

    async def maintenance(self):
        from django.core.management import call_command
        from django.db import connections

        async with self.lock:
            try:
                if self.application is None:
                    self.restore()
                call_command("clearsessions", verbosity=0)
                call_command("deliver_school_notices", verbosity=0)
                connections.close_all()
                self.checkpoint()
            except BaseException:
                connections.close_all()
                self.application = None
                raise

    async def fetch(self, request):
        from django.db import connections

        async with self.lock:
            try:
                if self.application is None:
                    self.restore()
                response = await wsgi.fetch(self.application, request, self.env)
                # Materialize the short HTML/QR response before persisting. WSGI
                # closes the Django response and its connection on exhaustion.
                body = await response.arrayBuffer()
                connections.close_all()
                self.checkpoint()
                if request.method == "HEAD" or response.status in (204, 205, 304):
                    body = None
                return js.Response.new(
                    body, status=response.status, headers=response.headers
                )
            except BaseException:
                connections.close_all()
                self.application = None
                raise


class Default(WorkerEntrypoint):
    async def scheduled(self, controller):
        await self.env.PORTAL.getByName("schools-v1").maintenance()

    async def fetch(self, request):
        if request.method not in ("GET", "HEAD", "POST"):
            return Response("Method not allowed", status=405)
        stub = self.env.PORTAL.getByName("schools-v1")
        return await stub.fetch(request)
