# WordVault — app + backend. No pip installs, standard library only.
FROM python:3.13-slim

WORKDIR /app

COPY . /app/

ENV PORT=8000 \
    WORDVAULT_DB=/data/wordvault.db \
    PYTHONUNBUFFERED=1

VOLUME ["/data"]
EXPOSE 8000

# the app itself is a single HTML file; this process serves it plus the API
CMD ["python3", "server.py"]
