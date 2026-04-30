"""Utility functions for configuration loading."""

from config.settings import config
from typing import Any

def get_config() -> Any:
    """Get the global DevSyn configuration."""
    return config

def setup_config():
    """Initialize configuration."""
    global config
    from config.settings import config
    return config
