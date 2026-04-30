"""Armazenamento vetorial com ChromaDB (>=0.4)."""

import os
import chromadb
from chromadb.config import Settings as ChromaSettings
from typing import List, Dict, Any, Optional
from config.settings import config
from src.logging import get_logger


class VectorStore:
    def __init__(self):
        self.logger = get_logger('storage.vector')

        # Garante que o diretorio existe
        os.makedirs(config.VECTOR_DB_PATH, exist_ok=True)

        # ChromaDB 0.4+ — PersistentClient com telemetry desabilitada
        # (evita o warning "Failed to send telemetry event" causado por
        # incompatibilidade entre posthog e chromadb 0.4).
        self.client = chromadb.PersistentClient(
            path=config.VECTOR_DB_PATH,
            settings=ChromaSettings(anonymized_telemetry=False),
        )
        self.collection = self._get_or_create_collection()

    def _get_or_create_collection(self, name: str = "devsyn_context"):
        """Obtem ou cria colecao principal (idempotente em 0.4+)."""
        return self.client.get_or_create_collection(name=name)

    def add_documents(self,
                      documents: List[str],
                      metadatas: Optional[List[Dict[str, Any]]] = None,
                      ids: Optional[List[str]] = None):
        """Adiciona documentos ao vector store."""
        if metadatas is None:
            metadatas = [{"source": f"doc_{i}"} for i in range(len(documents))]
        if ids is None:
            ids = [f"doc_{i}" for i in range(len(documents))]

        self.collection.add(
            documents=documents,
            metadatas=metadatas,
            ids=ids,
        )
        self.logger.info(f"Added {len(documents)} documents to vector store")

    def query(self,
              query_texts: List[str],
              n_results: int = 5) -> Dict[str, Any]:
        """Busca por similaridade."""
        results = self.collection.query(
            query_texts=query_texts,
            n_results=n_results,
        )
        try:
            n = len(results['documents'][0])
        except (KeyError, IndexError, TypeError):
            n = 0
        self.logger.debug(f"Vector query returned {n} results")
        return results


_vector_store: Optional[VectorStore] = None


def get_vector_store() -> VectorStore:
    global _vector_store
    if _vector_store is None:
        _vector_store = VectorStore()
    return _vector_store
