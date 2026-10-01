import os

DATABASE_URL = os.environ["DATABASE_URL"]
stripe_secret_key = os.environ.get("STRIPE_SECRET_KEY", "")
smtp_password = os.environ.get("SMTP_PASSWORD")
PASSWORD_MIN_LENGTH = 12
API_KEY_HEADER = "X-Api-Key"

if not stripe_secret_key:
    raise RuntimeError("STRIPE_SECRET_KEY is not set")
