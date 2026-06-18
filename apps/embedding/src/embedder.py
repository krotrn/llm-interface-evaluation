import logging
from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)

class Embedder:
    """Handles loading and inference for the SentenceTransformer model."""

    def __init__(self, model_name: str = "all-MiniLM-L6-v2"):
        self.model_name = model_name
        self.model: SentenceTransformer | None = None

    def load(self) -> None:
        """Synchronously load the model (CPU/disk-bound)."""
        logger.info("Loading sentence-transformers model: %s...", self.model_name)
        try:
            self.model = SentenceTransformer(self.model_name)
            logger.info("Model %s loaded successfully.", self.model_name)
        except Exception as e:
            logger.error("Failed to load model %s: %s", self.model_name, e)
            raise

    def embed(self, text: str) -> list[float]:
        """Generate embedding for a single text."""
        if self.model is None:
            raise RuntimeError("Model is not loaded. Call load() first.")
        # encode returns a numpy array, normalize_embeddings=True ensures unit length vectors
        result = self.model.encode(text, normalize_embeddings=True)
        return result.tolist()

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for a batch of texts."""
        if self.model is None:
            raise RuntimeError("Model is not loaded. Call load() first.")
        result = self.model.encode(texts, normalize_embeddings=True)
        return result.tolist()
