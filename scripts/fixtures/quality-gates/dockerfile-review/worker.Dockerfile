FROM python:3.12-slim
WORKDIR /srv
ENV PAYMENT_API_SECRET=q8ZfR2mK9vLx4Tn7Wb3Yc6Hd1Gs5Pj0A
COPY . .
RUN pip install -r requirements.txt
CMD ["python", "worker.py"]
