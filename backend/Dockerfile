# 1. create build image
# get builder image with uv integrated
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim AS builder
# use uv to optimize startup by pre-compiling Python files to bytecode
ENV UV_COMPILE_BYTECODE=1
WORKDIR /app
# copy only the lockfile and pyproject.toml
# ensures Docker only re-runs 'uv sync' if dependencies change
COPY pyproject.toml uv.lock ./
# install dependencies into a virtual environment (.venv)
# --frozen: error if uv.lock is out of sync.
# --no-install-project: don't install the app code yet (better caching)
RUN uv sync --frozen --no-install-project --no-dev

# 2. create final image
# switch to the standard slim image
FROM python:3.11-slim-bookworm
# create a non-root user for security
WORKDIR /app
# copy the virtual environment from the builder stage
# change ownership to our non-root user
COPY --from=builder /app/.venv /app/.venv
# copy source code and environment variables
COPY . .
# set the PATH to the virtual environment
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH="/app/.venv/lib/python3.11/site-packages"
CMD ["/app/.venv/bin/python", "main.py"]