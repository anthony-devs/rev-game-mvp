FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY console ./console
COPY wsgi.py actions.json ./
# One worker: the monitor runs inside it. Keep the SQLite file on a persistent disk (CONSOLE_DB).
CMD exec gunicorn --bind :${PORT:-9090} --workers 1 --threads 8 --timeout 120 wsgi:app
