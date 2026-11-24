import base64

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from django.contrib.auth.hashers import PBKDF2PasswordHasher
from django.utils.encoding import force_bytes


class WorkerPasswordHasher(PBKDF2PasswordHasher):
    """Use OpenSSL in cryptography on Pyodide, which omits hashlib.pbkdf2_hmac."""

    def encode(self, password, salt, iterations=None):
        self._check_encode_args(password, salt)
        rounds = iterations or self.iterations
        key = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=force_bytes(salt),
            iterations=rounds,
        ).derive(force_bytes(password))
        return (
            f"{self.algorithm}${rounds}${salt}${base64.b64encode(key).decode('ascii')}"
        )
