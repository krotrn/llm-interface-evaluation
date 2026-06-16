# llm-forge

`llm-forge` is a self-hosted LLM inference gateway and evaluation platform. It provides semantic caching, BullMQ queuing, circuit-breaker fallback, SSE streaming, and full Prometheus/Grafana observability, combined with a CI-integrated multi-model evaluation platform.

## Initial Setup

Follow these steps to set up and run the platform locally:

1. **Clone the Repository**
   ```bash
   git clone <repository-url>
   cd llm-gateway
   ```

2. **Configure Environment Variables**
   Copy the example environment variables template to create your local `.env` configuration:
   ```bash
   cp .env.example .env
   ```

3. **Start the Infrastructure Stack**
   Start all 12 services in Docker Compose (ensure Docker daemon is running):
   ```bash
   make up
   ```
   This will start Postgres, Redis, Nginx, Prometheus, Grafana, Loki, Promtail, Ollama, and our application placeholders. The gateway and workers will wait until the Ollama service health check passes before starting.

4. **Pull LLM Models**
   Pull the 4 required GGUF models into the Ollama container:
   ```bash
   bash scripts/pull-models.sh
   ```
   *Note: This downloads about 7 GB of model data. Ensure you have sufficient disk space.*

5. **Verify Ollama Setup**
   Run the test script to verify that all models are loaded and generating responses successfully:
   ```bash
   bash scripts/test-ollama.sh
   ```
   On success, this script will output `4/4 PASS`.
