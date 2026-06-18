import time
import os
import uuid
import logging
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel, Field, field_validator
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from src.embedder import Embedder
from src.metrics import llmforge_embedding_requests_total, llmforge_embedding_duration_seconds

# Setup basic logging format
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s"
)
logger = logging.getLogger("embedding_service")

# Read configurations
MODEL_NAME = os.getenv("MODEL_NAME", "all-MiniLM-L6-v2")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize and load the embedder
    embedder = Embedder(MODEL_NAME)
    # Load model in a worker thread to prevent blocking event loop startup
    await asyncio.to_thread(embedder.load)
    app.state.embedder = embedder
    logger.info("FastAPI service startup complete. Model loaded.")
    yield
    # Shutdown: Clean up state
    app.state.embedder = None
    logger.info("FastAPI service shutdown complete.")

app = FastAPI(
    title="Embedding Service",
    description="High-performance async microservice for generating semantic text embeddings",
    version="0.2.0",
    lifespan=lifespan
)

# Custom exception handler for validation errors
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.warning("Validation error on request: %s", exc.errors())
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "error": "Validation Error",
            "details": jsonable_encoder(exc.errors())
        }
    )

# Custom global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error occurred")
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal Server Error",
            "detail": "An unexpected error occurred during processing."
        }
    )

# Middleware for request tracing and timing
@app.middleware("http")
async def add_tracing_and_timing(request: Request, call_next):
    request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))
    request.state.request_id = request_id
    
    start_time = time.perf_counter()
    response: Response = await call_next(request)
    duration = time.perf_counter() - start_time
    
    response.headers["X-Request-Id"] = request_id
    response.headers["X-Process-Time"] = f"{duration:.6f}"
    
    return response

# Pydantic Schemas
class EmbedRequest(BaseModel):
    text: str = Field(..., min_length=1, description="The text to generate an embedding for")

    @field_validator("text")
    @classmethod
    def validate_text(cls, text: str) -> str:
        if not text.strip():
            raise ValueError("text cannot be empty or whitespace only")
        return text

class EmbedResponse(BaseModel):
    embedding: list[float] = Field(..., description="The unit-length normalized embedding vector")
    model: str = Field(..., description="The model name used for embedding")
    latency_ms: float = Field(..., description="Latency of embedding generation in milliseconds")

class EmbedBatchRequest(BaseModel):
    texts: list[str] = Field(..., min_length=1, description="List of texts to generate embeddings for")

    @field_validator("texts")
    @classmethod
    def validate_texts(cls, texts: list[str]) -> list[str]:
        if not texts:
            raise ValueError("texts list cannot be empty")
        for idx, text in enumerate(texts):
            if not text.strip():
                raise ValueError(f"text at index {idx} cannot be empty or whitespace only")
        return texts

class EmbedBatchResponse(BaseModel):
    embeddings: list[list[float]] = Field(..., description="List of normalized embedding vectors")
    model: str = Field(..., description="The model name used for embedding")
    latency_ms: float = Field(..., description="Latency of embedding generation in milliseconds")

# Endpoints
@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/health")
def health(request: Request):
    embedder: Embedder | None = getattr(request.app.state, "embedder", None)
    return {
        "status": "ok",
        "model_loaded": embedder is not None and embedder.model is not None,
        "model_name": MODEL_NAME
    }

@app.post("/embed", response_model=EmbedResponse)
async def get_embedding(request: EmbedRequest, req: Request):
    embedder: Embedder | None = getattr(req.app.state, "embedder", None)
    if not embedder:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding model is not initialized yet."
        )

    start_time = time.perf_counter()
    try:
        # Run synchronous/CPU-bound SentenceTransformer encoding in a worker thread
        embedding = await asyncio.to_thread(embedder.embed, request.text)
        latency = time.perf_counter() - start_time
        
        # Record metrics
        llmforge_embedding_duration_seconds.labels(endpoint="embed").observe(latency)
        llmforge_embedding_requests_total.labels(endpoint="embed", status="success").inc()
        
        return EmbedResponse(
            embedding=embedding,
            model=MODEL_NAME,
            latency_ms=latency * 1000.0
        )
    except Exception as e:
        llmforge_embedding_requests_total.labels(endpoint="embed", status="error").inc()
        logger.exception("Error generating single embedding (request_id=%s): %s", req.state.request_id, e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Embedding generation failed"
        )

@app.post("/embed/batch", response_model=EmbedBatchResponse)
async def get_embeddings_batch(request: EmbedBatchRequest, req: Request):
    embedder: Embedder | None = getattr(req.app.state, "embedder", None)
    if not embedder:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Embedding model is not initialized yet."
        )

    start_time = time.perf_counter()
    try:
        # Run synchronous/CPU-bound SentenceTransformer encoding in a worker thread
        embeddings = await asyncio.to_thread(embedder.embed_batch, request.texts)
        latency = time.perf_counter() - start_time
        
        # Record metrics
        llmforge_embedding_duration_seconds.labels(endpoint="embed_batch").observe(latency)
        llmforge_embedding_requests_total.labels(endpoint="embed_batch", status="success").inc()
        
        return EmbedBatchResponse(
            embeddings=embeddings,
            model=MODEL_NAME,
            latency_ms=latency * 1000.0
        )
    except Exception as e:
        llmforge_embedding_requests_total.labels(endpoint="embed_batch", status="error").inc()
        logger.exception("Error generating batch embeddings (request_id=%s): %s", req.state.request_id, e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Batch embedding generation failed"
        )
