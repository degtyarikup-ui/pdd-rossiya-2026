import json

from django.core.mail.backends.base import BaseEmailBackend


class EmailBackend(BaseEmailBackend):
    def send_messages(self, messages):
        from pyodide.ffi import run_sync
        from workers import import_from_javascript

        sender = import_from_javascript("school-mail.mjs")
        sent = 0
        for message in messages:
            for recipient in message.recipients():
                envelope = {
                    "from": str(message.from_email),
                    "to": str(recipient),
                    "subject": str(message.subject),
                    "text": str(message.body),
                }
                try:
                    run_sync(sender.sendMail(json.dumps(envelope)))
                except Exception as exc:
                    if self.fail_silently:
                        continue
                    raise OSError("School email delivery failed") from exc
                sent += 1
        return sent
