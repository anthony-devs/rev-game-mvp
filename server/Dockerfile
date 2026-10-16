FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY wsgi.py .

# Cloud Run sends requests to $PORT. Threads (not processes) so one instance can
# hold many open crash streams. Timeout 0 lets long streams stay open.
CMD exec gunicorn --bind :${PORT:-8080} --workers 1 --threads 64 --timeout 0 wsgi:app
