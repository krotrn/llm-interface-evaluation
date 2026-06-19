# Use a Python 3.13 slim base image
FROM python:3.13-slim

# Create a non-root user and group
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -m -s /bin/bash appuser

# Copy uv binary for dependency management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory inside the container
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Pre-create the cache and app directories
RUN mkdir -p /home/appuser/.cache/huggingface /home/appuser/.cache/uv /app && \
    chown -R appuser:appgroup /home/appuser /app

# Run all subsequent operations as non-root user
USER appuser

# Copy workspace configuration for apps/embedding
COPY --chown=appuser:appgroup apps/embedding/pyproject.toml apps/embedding/uv.lock ./apps/embedding/

# Install the dependencies without the project source code itself (improves build caching)
WORKDIR /app/apps/embedding
RUN --mount=type=cache,id=embedding-uv-cache,target=/home/appuser/.cache/uv,uid=10001,gid=10001 \
    uv sync --frozen --no-install-project

# Copy the source code of apps/embedding
COPY --chown=appuser:appgroup apps/embedding/src ./src

# Sync the project including the newly copied source code
RUN --mount=type=cache,id=embedding-uv-cache,target=/home/appuser/.cache/uv,uid=10001,gid=10001 \
    uv sync --frozen

# Expose the port FastAPI runs on
EXPOSE 8000

# Set Hugging Face cache directory to a persistent location
ENV HF_HOME=/home/appuser/.cache/huggingface

# Command to run the application using uvicorn
CMD ["uv", "run", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
