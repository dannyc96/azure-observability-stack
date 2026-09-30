# Multi-stage build: dependencies compile in a throwaway layer, the runtime
# image ships only the venv and the source, and the process runs as a
# non-root user.

FROM python:3.12-slim AS builder

WORKDIR /build

# venv keeps the runtime copy to a single directory and avoids polluting the
# system site-packages in the final image.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# ---------------------------------------------------------------------------
FROM python:3.12-slim

# Non-root: Container Apps does not require it, but every base image scan and
# security reviewer will ask, so bake it in.
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --shell /usr/sbin/nologin --create-home app

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY main.py .

USER app
EXPOSE 8000

# Single worker per container: Container Apps scales horizontally via
# replicas, so in-process worker fan-out just muddies the telemetry.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
