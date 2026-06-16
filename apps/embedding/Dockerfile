# Use a Python 3.13 slim base image
FROM python:3.13-slim

# Copy uv binary for dependency management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory inside the container
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy workspace configuration for apps/embedding
COPY apps/embedding/pyproject.toml apps/embedding/uv.lock ./apps/embedding/

# Install the dependencies without the project source code itself (improves build caching)
WORKDIR /app/apps/embedding
RUN uv sync --frozen --no-install-project

# Copy the source code of apps/embedding
COPY apps/embedding/src ./src

# Sync the project including the newly copied source code
RUN uv sync --frozen

# Expose the port FastAPI runs on
EXPOSE 8000

# Set Hugging Face cache directory to a persistent location
ENV HF_HOME=/root/.cache/huggingface

# Command to run the application using uvicorn
CMD ["uv", "run", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
