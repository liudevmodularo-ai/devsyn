#!/usr/bin/env python3
"""Script principal para executar DevSyn."""

import os
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent))

from src.logging import setup_logger
from src.app import app
from config.settings import config

if __name__ == "__main__":
    # Setup logging
    logger = setup_logger()
    
    # Validações
    if not config.OPENAI_API_KEY:
        logger.warning("No OPENAI_API_KEY found. Copy .env.example to .env")
    
    logger.info("Starting DevSyn Platform...")
    app.run(host='0.0.0.0', port=5000, debug=True)
