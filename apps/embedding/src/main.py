import time
from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel, Field, field_validator
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
import logging


from src.embedder import embed, embed_batch, model
from src.metrics import llmforge_embedding_requests_total, llmforge_embedding_duration_seconds

app = FastAPI(title="Embedding Service", version="0.1.0")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

class EmbedRequest(BaseModel):
    text: str = Field(..., min_length=1, description="The text to generate an embedding for")
    @field_validator("text")
    @classmethod
    def validate_text(cls, text):
        if not text.strip():
            raise ValueError("text cannot be empty")
        return text

class EmbedResponse(BaseModel):
    embedding: list[float] = Field(..., description="The embedding vector")
    model: str = Field("all-MiniLM-L6-v2", description="The model used for embedding")
    latency_ms: float = Field(..., description="Latency of embedding generation in milliseconds")

class EmbedBatchRequest(BaseModel):
    texts: list[str] = Field(..., min_length=1, description="List of texts to generate embeddings for")
    @field_validator("texts")
    @classmethod
    def validate_texts(cls, texts):
        if not texts:
            raise ValueError("texts cannot be empty")

        for text in texts:
            if not text.strip():
                raise ValueError("all texts must be non-empty")

        return texts

class EmbedBatchResponse(BaseModel):
    embeddings: list[list[float]] = Field(..., description="List of embedding vectors")
    model: str = Field("all-MiniLM-L6-v2", description="The model used for embedding")
    latency_ms: float = Field(..., description="Latency of embedding generation in milliseconds")

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_loaded": model is not None,
        "model_name": "all-MiniLM-L6-v2"
    }

@app.post("/embed", response_model=EmbedResponse)
async def get_embedding(request: EmbedRequest):
    start_time = time.perf_counter()
    try:
        embedding = embed(request.text)
        latency = (time.perf_counter() - start_time)
        
        # Observe latency in Prometheus (in seconds)
        llmforge_embedding_duration_seconds.labels(
            endpoint="embed"
)       .observe(latency)
        # Increment requests total
        llmforge_embedding_requests_total.labels(status="success", endpoint="embed").inc()
        
        return EmbedResponse(
            embedding=embedding,
            model="all-MiniLM-L6-v2",
            latency_ms=latency * 1000.0
        )
    except Exception:
        llmforge_embedding_requests_total.labels(
            endpoint="embed",
            status="error"
        ).inc()
        logger.exception("Embedding failed")
        raise HTTPException(
            status_code=500,
            detail="Embedding generation failed"
        )

@app.post("/embed/batch", response_model=EmbedBatchResponse)
async def get_embeddings_batch(request: EmbedBatchRequest):
    start_time = time.perf_counter()
    try:
        embeddings = embed_batch(request.texts)
        latency = (time.perf_counter() - start_time)
        
        # Observe latency in Prometheus (in seconds)
        llmforge_embedding_duration_seconds.labels(
            endpoint="embed_batch"
)       .observe(latency)
        # Increment requests total
        llmforge_embedding_requests_total.labels(status="success", endpoint="embed_batch").inc()
        
        return EmbedBatchResponse(
            embeddings=embeddings,
            model="all-MiniLM-L6-v2",
            latency_ms=latency * 1000.0
        )
    except Exception:
        llmforge_embedding_requests_total.labels(
            endpoint="embed_batch",
            status="error"
        ).inc()
        logger.exception("Embedding failed")
        raise HTTPException(
            status_code=500,
            detail="Embedding generation failed"
        )
