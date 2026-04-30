"""Sistema centralizado de logging para DevSyn."""

import logging
import os
from datetime import datetime
from typing import Optional
from config.settings import config

def setup_logger(name: str = 'devsyn') -> logging.Logger:
    """Configura logger centralizado."""
    
    # Cria diretório de logs se não existir
    log_dir = os.path.dirname(config.LOG_PATH)
    os.makedirs(log_dir, exist_ok=True)
    
    logger = logging.getLogger(name)
    if logger.hasHandlers():
        logger.handlers.clear()
    
    logger.setLevel(getattr(logging, config.LOG_LEVEL))
    
    # Formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    # File handler
    file_handler = logging.FileHandler(config.LOG_PATH)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    
    return logger

def get_logger(name: str = 'devsyn') -> logging.Logger:
    """Obtém logger configurado."""
    return logging.getLogger(name)
