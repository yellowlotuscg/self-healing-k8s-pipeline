# Multi-stage so the runtime image stays small and doesn't ship build cruft.
# Pinned to a slim Python base; I keep these pinned because "latest" surprised
# me in CI more than once.
FROM python:3.12-slim AS build

WORKDIR /app
COPY requirements.txt .
# --no-cache-dir keeps the layer lean; wheels go straight into a venv we copy.
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim AS runtime

# Run as a non-root user. This is a GRC habit more than a k8s one, but it also
# satisfies the restricted Pod Security Standard the Deployment asks for.
RUN groupadd -r app && useradd -r -g app -u 10001 app

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_NAME=echo-svc \
    READY_AFTER_SECONDS=5

WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY main.py .

EXPOSE 8080
USER 10001

# Single worker on purpose - horizontal scaling is k8s's job (HPA), not
# uvicorn's, and one worker per pod makes resource requests easy to reason about.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
