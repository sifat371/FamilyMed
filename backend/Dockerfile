FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim

ENV PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# Install pinned production dependencies before copying application files.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./alembic.ini

# The public API never needs root privileges.
RUN useradd --system --uid 10001 --create-home familymed \
    && chown -R familymed:familymed /app
USER familymed

EXPOSE 10000

# Single-instance V1: migrate before accepting traffic; a failed migration
# prevents serving an API against the wrong schema.
CMD ["/bin/sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}"]
