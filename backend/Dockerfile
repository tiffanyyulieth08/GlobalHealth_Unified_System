FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update \
    && apt-get install --no-install-recommends -y netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/app ./app
COPY scripts/wait-for-service.sh /usr/local/bin/wait-for-service.sh
RUN sed -i 's/\r$//' /usr/local/bin/wait-for-service.sh \
    && chmod +x /usr/local/bin/wait-for-service.sh

EXPOSE 8000

CMD ["wait-for-service.sh", "postgres-primary", "5432", "--", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
