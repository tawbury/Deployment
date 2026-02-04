# Observer app image. Build context: repo root. Copies src/ into /app/src.
FROM python:3.11-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

COPY src /app/src

RUN mkdir -p /opt/platform/runtime/observer/data/scalp /opt/platform/runtime/observer/data/swing \
    && mkdir -p /opt/platform/runtime/observer/logs/scalp /opt/platform/runtime/observer/logs/swing /opt/platform/runtime/observer/logs/system /opt/platform/runtime/observer/logs/maintenance \
    && mkdir -p /opt/platform/runtime/observer/config/scalp /opt/platform/runtime/observer/config/swing /opt/platform/runtime/observer/config/symbols /opt/platform/runtime/observer/config/universe \
    && mkdir -p /opt/platform/runtime/observer/data/cache

ENV OBSERVER_STANDALONE=1
ENV PYTHONPATH=/app/src
ENV TZ=Asia/Seoul
ENV OBSERVER_DATA_DIR=/opt/platform/runtime/observer/data
ENV OBSERVER_LOG_DIR=/opt/platform/runtime/observer/logs
ENV OBSERVER_SYSTEM_LOG_DIR=/opt/platform/runtime/observer/logs/system
ENV OBSERVER_MAINTENANCE_LOG_DIR=/opt/platform/runtime/observer/logs/maintenance
ENV OBSERVER_CONFIG_DIR=/opt/platform/runtime/observer/config
ENV KIS_TOKEN_CACHE_DIR=/opt/platform/runtime/observer/data/cache
ENV OBSERVER_ENV_FILE=/opt/platform/runtime/observer/config/.env

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN groupadd -r observer && useradd -r -g observer observer
RUN chown -R observer:observer /app /opt/platform/runtime/observer

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=2 \
    CMD ["python","-c","import urllib.request,sys; r=urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3); sys.exit(0 if r.getcode()==200 else 1)"]

EXPOSE 8000
USER observer

CMD ["python", "-m", "observer"]
