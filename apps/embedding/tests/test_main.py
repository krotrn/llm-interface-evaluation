import pytest
from httpx import AsyncClient, ASGITransport
from src.main import app

@pytest.fixture
def anyio_backend():
    return "asyncio"

@pytest.fixture
async def client():
    async with app.router.lifespan_context(app):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            yield ac

@pytest.mark.anyio
async def test_healthcheck(client):
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert "model_loaded" in data

@pytest.mark.anyio
async def test_metrics(client):
    response = await client.get("/metrics")
    assert response.status_code == 200
    assert "llmforge_embedding" in response.text

@pytest.mark.anyio
async def test_single_embedding_success(client):
    response = await client.post("/embed", json={"text": "Hello world"})
    assert response.status_code == 200
    data = response.json()
    assert "embedding" in data
    assert isinstance(data["embedding"], list)
    assert len(data["embedding"]) > 0
    assert data["model"] == "all-MiniLM-L6-v2"
    assert "latency_ms" in data
    assert "X-Request-Id" in response.headers
    assert "X-Process-Time" in response.headers

@pytest.mark.anyio
async def test_single_embedding_validation_failure(client):
    response = await client.post("/embed", json={"text": "   "})
    assert response.status_code == 422
    data = response.json()
    assert data["error"] == "Validation Error"
    assert "details" in data

@pytest.mark.anyio
async def test_batch_embedding_success(client):
    response = await client.post("/embed/batch", json={"texts": ["Hello", "World"]})
    assert response.status_code == 200
    data = response.json()
    assert "embeddings" in data
    assert len(data["embeddings"]) == 2
    assert isinstance(data["embeddings"][0], list)
    assert data["model"] == "all-MiniLM-L6-v2"
    assert "latency_ms" in data

@pytest.mark.anyio
async def test_batch_embedding_validation_failure(client):
    # Empty list of texts
    response1 = await client.post("/embed/batch", json={"texts": []})
    assert response1.status_code == 422
    
    # List containing empty string
    response2 = await client.post("/embed/batch", json={"texts": ["Hello", "   "]})
    assert response2.status_code == 422
