FROM python:3.12-slim

LABEL maintainer="liruixiang"
LABEL description="ProxyHub - Proxy service management panel"

# ── System dependencies ──────────────────────────────────────────
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        curl \
        simple-obfs \
        procps \
    && rm -rf /var/lib/apt/lists/*

# ── Python dependencies ──────────────────────────────────────────
WORKDIR /opt/proxyhub
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8080

CMD ["python", "run.py"]