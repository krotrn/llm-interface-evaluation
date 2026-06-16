import time
from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel, Field
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from src.embedder import embed, embed_batch
from src.metrics import llmforge_embedding_requests_total, llmforge_embedding_duration_seconds

app = FastAPI(title="Embedding Service", version="0.1.0")

@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

class EmbedRequest(BaseModel):
    text: str = Field(..., description="The text to generate an embedding for")

class EmbedResponse(BaseModel):
    embedding: list[float] = Field(..., description="The embedding vector")
    model: str = Field("all-MiniLM-L6-v2", description="The model used for embedding")
    latency_ms: float = Field(..., description="Latency of embedding generation in milliseconds")

class EmbedBatchRequest(BaseModel):
    texts: list[str] = Field(..., description="List of texts to generate embeddings for")

class EmbedBatchResponse(BaseModel):
    embeddings: list[list[float]] = Field(..., description="List of embedding vectors")
    model: str = Field("all-MiniLM-L6-v2", description="The model used for embedding")
    latency_ms: float = Field(..., description="Latency of embedding generation in milliseconds")

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_loaded": True
    }

@app.post("/embed", response_model=EmbedResponse)
async def get_embedding(request: EmbedRequest):
    start_time = time.perf_counter()
    try:
        embedding = embed(request.text)
        latency = (time.perf_counter() - start_time)
        
        # Observe latency in Prometheus (in seconds)
        llmforge_embedding_duration_seconds.observe(latency)
        # Increment requests total
        llmforge_embedding_requests_total.labels(status="success").inc()
        
        return EmbedResponse(
            embedding=embedding,
            model="all-MiniLM-L6-v2",
            latency_ms=latency * 1000.0
        )
    except Exception as e:
        llmforge_embedding_requests_total.labels(status="error").inc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/embed/batch", response_model=EmbedBatchResponse)
async def get_embeddings_batch(request: EmbedBatchRequest):
    start_time = time.perf_counter()
    try:
        embeddings = embed_batch(request.texts)
        latency = (time.perf_counter() - start_time)
        
        # Observe latency in Prometheus (in seconds)
        llmforge_embedding_duration_seconds.observe(latency)
        # Increment requests total
        llmforge_embedding_requests_total.labels(status="success").inc()
        
        return EmbedBatchResponse(
            embeddings=embeddings,
            model="all-MiniLM-L6-v2",
            latency_ms=latency * 1000.0
        )
    except Exception as e:
        llmforge_embedding_requests_total.labels(status="error").inc()
        raise HTTPException(status_code=500, detail=str(e))
