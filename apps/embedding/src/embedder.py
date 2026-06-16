from sentence_transformers import SentenceTransformer

# Load model at module import time
print("Loading sentence-transformers model: all-MiniLM-L6-v2...")
model = SentenceTransformer('all-MiniLM-L6-v2')
print("Model loaded successfully.")

def embed(text: str) -> list[float]:
    """Generate embedding for a single text."""
    return model.encode(text).tolist()

def embed_batch(texts: list[str]) -> list[list[float]]:
    """Generate embeddings for a batch of texts."""
    return model.encode(texts).tolist()
