"""DevSyn Configuration Settings."""

import os
from pydantic import BaseSettings
from typing import Optional, List, Dict

class Settings(BaseSettings):
    # === OpenAI ===
    OPENAI_API_KEY: Optional[str] = None
    OPENAI_MODEL: str = "gpt-4o-mini"
    OPENAI_ENABLED: bool = True
    
    # === Anthropic/Claude ===
    ANTHROPIC_API_KEY: Optional[str] = None
    ANTHROPIC_MODEL: str = "claude-3-5-sonnet-20241022"
    ANTHROPIC_ENABLED: bool = False
    
    # === Google Gemini ===
    GEMINI_API_KEY: Optional[str] = None
    GEMINI_MODEL: str = "gemini-1.5-flash"
    GEMINI_ENABLED: bool = True
    
    # === Groq ===
    GROQ_API_KEY: Optional[str] = None
    GROQ_MODEL: str = "mixtral-8x7b-32768"
    GROQ_ENABLED: bool = False
    
    # === Mistral ===
    MISTRAL_API_KEY: Optional[str] = None
    MISTRAL_MODEL: str = "mistral-small-latest"
    MISTRAL_ENABLED: bool = False
    
    # === Cohere ===
    COHERE_API_KEY: Optional[str] = None
    COHERE_MODEL: str = "command-r-plus"
    COHERE_ENABLED: bool = False
    
    # === Fallback Order (prioridade) ===
    FALLBACK_ORDER: List[str] = ["openai", "gemini", "groq", "anthropic", "mistral", "cohere"]
    
    # === Orchestration ===
    MAX_AGENTS: int = 10
    TASK_TIMEOUT: int = 300  # seconds
    
    # === Storage ===
    VECTOR_DB_PATH: str = "data/vector_store"
    MEMORY_DB_PATH: str = "data/memory.db"
    
    # === Logging ===
    LOG_LEVEL: str = "INFO"
    LOG_PATH: str = "logs/devsyn.log"
    
    # === Fallback Playwright ===
    PLAYWRIGHT_HEADLESS: bool = True
    
    # === URLs para obter chaves ===
    OPENAI_KEY_URL: str = "https://platform.openai.com/api-keys"
    ANTHROPIC_KEY_URL: str = "https://console.anthropic.com/settings/keys"
    GEMINI_KEY_URL: str = "https://aistudio.google.com/app/apikey"
    GROQ_KEY_URL: str = "https://console.groq.com"
    MISTRAL_KEY_URL: str = "https://console.mistral.ai"
    COHERE_KEY_URL: str = "https://dashboard.cohere.com"
    
    class Config:
        env_file = ".env"

config = Settings()

# Provedores disponíveis
AI_PROVIDERS = {
    "openai": {
        "name": "OpenAI",
        "url": config.OPENAI_KEY_URL,
        "enabled": config.OPENAI_ENABLED,
        "model": config.OPENAI_MODEL,
    },
    "anthropic": {
        "name": "Anthropic (Claude)",
        "url": config.ANTHROPIC_KEY_URL,
        "enabled": config.ANTHROPIC_ENABLED,
        "model": config.ANTHROPIC_MODEL,
    },
    "gemini": {
        "name": "Google Gemini",
        "url": config.GEMINI_KEY_URL,
        "enabled": config.GEMINI_ENABLED,
        "model": config.GEMINI_MODEL,
    },
    "groq": {
        "name": "Groq",
        "url": config.GROQ_KEY_URL,
        "enabled": config.GROQ_ENABLED,
        "model": config.GROQ_MODEL,
    },
    "mistral": {
        "name": "Mistral",
        "url": config.MISTRAL_KEY_URL,
        "enabled": config.MISTRAL_ENABLED,
        "model": config.MISTRAL_MODEL,
    },
    "cohere": {
        "name": "Cohere",
        "url": config.COHERE_KEY_URL,
        "enabled": config.COHERE_ENABLED,
        "model": config.COHERE_MODEL,
    },
}
