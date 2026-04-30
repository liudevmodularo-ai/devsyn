"""Armazenamento vetorial com ChromaDB."""

import chromadb
from chromadb.config import Settings
from typing import List, Dict, Any, Optional
from config.settings import config
from src.logging import get_logger

class VectorStore:
    def __init__(self):
        self.logger = get_logger('storage.vector')
        
        # Configura ChromaDB persistente
        chroma_settings = Settings(
            chroma_db_impl="duckdb+parquet",
            persist_directory=config.VECTOR_DB_PATH,
            anonymized_telemetry=False
        )
        
        self.client = chromadb.PersistentClient(
            path=config.VECTOR_DB_PATH,
            settings=chroma_settings
        )
        self.collection = self._get_or_create_collection()
    
    def _get_or_create_collection(self, name: str = "devsyn_context"):
        """Obtém ou cria coleção principal."""
        try:
            return self.client.get_collection(name)
        except:
            return self.client.create_collection(name)
    
    def add_documents(self, 
                     documents: List[str],
                     metadatas: List[Dict[str, Any]] = None,
                     ids: List[str] = None):
        """Adiciona documentos ao vetor store."""
        if metadatas is None:
            metadatas = [{"source": f"doc_{i}"} for i in range(len(documents))]
        if ids is None:
            ids = [f"doc_{i}" for i in range(len(documents))]
        
        self.collection.add(
            documents=documents,
            metadatas=metadatas,
            ids=ids
        )
        self.logger.info(f"Added {len(documents)} documents to vector store")
    
    def query(self, 
              query_texts: List[str],
              n_results: int = 5) -> List[Dict[str, Any]]:
        """Busca similaridade."""
        results = self.collection.query(
            query_texts=query_texts,
            n_results=n_results
        )
        self.logger.debug(f"Vector query returned {len(results['documents'][0])} results")
        return results

vector_store = None

def get_vector_store() -> VectorStore:
    global vector_store
    if vector_store is None:
        vector_store = VectorStore()
    return vector_store
