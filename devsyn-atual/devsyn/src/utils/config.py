"""Utility functions for configuration loading."""

from typing import Any
from config.settings import config as _settings


# Alias de classe — permite `from src.utils import Config` continuar funcionando.
# Apenas referencia o tipo do objeto config (Settings).
Config = type(_settings)


def get_config() -> Any:
    """Get the global DevSyn configuration."""
    return _settings


def setup_config() -> Any:
    """Initialize configuration (idempotente — apenas retorna o singleton)."""
    return _settings
