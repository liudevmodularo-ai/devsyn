"""DevSyn Configuration Settings."""

import os
from pydantic import BaseSettings
from typing import Optional, List

class Settings(BaseSettings):
    # API Keys
    OPENAI_API_KEY: Optional[str] = None
    GEMINI_API_KEY: Optional[str] = None
    
    # Orchestration
    MAX_AGENTS: int = 10
    TASK_TIMEOUT: int = 300  # seconds
    
    # Storage
    VECTOR_DB_PATH: str = "data/vector_store"
    MEMORY_DB_PATH: str = "data/memory.db"
    
    # Logging
    LOG_LEVEL: str = "INFO"
    LOG_PATH: str = "logs/devsyn.log"
    
    # Fallback
    PLAYWRIGHT_HEADLESS: bool = True
    
    class Config:
        env_file = ".env"

config = Settings()
