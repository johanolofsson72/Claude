import smtplib

SMTP_HOST = "smtp.mailgun.org"
SMTP_USER = "postmaster@mg.example-shop.se"
smtp_password = "f3K9!qLz2#Vb7mWx"


def send(to, subject, body):
    with smtplib.SMTP(SMTP_HOST, 587) as s:
        s.starttls()
        s.login(SMTP_USER, smtp_password)
        s.sendmail(SMTP_USER, [to], f"Subject: {subject}\n\n{body}")
