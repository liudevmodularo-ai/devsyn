"""Memória persistente local para estado dos agentes."""

import sqlite3
import json
import os
from typing import Dict, Any, Optional
from datetime import datetime
from config.settings import config
from src.logging import get_logger

class MemoryStore:
    def __init__(self):
        self.logger = get_logger('storage.memory')
        self.db_path = config.MEMORY_DB_PATH
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self._init_db()
    
    def _init_db(self):
        """Inicializa schema da memória."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS agent_memory (
                agent_id TEXT PRIMARY KEY,
                state JSON,
                context JSON,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                version INTEGER DEFAULT 1
            )
        ''')
        conn.commit()
        conn.close()
    
    def save_agent_state(self, agent_id: str, state: Dict[str, Any], 
                        context: Dict[str, Any]):
        """Salva estado completo do agente."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT OR REPLACE INTO agent_memory 
            (agent_id, state, context, last_updated)
            VALUES (?, ?, ?, ?)
        ''', (
            agent_id, 
            json.dumps(state),
            json.dumps(context),
            datetime.utcnow()
        ))
        conn.commit()
        conn.close()
        self.logger.debug(f"Saved state for agent {agent_id}")
    
    def load_agent_state(self, agent_id: str) -> Optional[Dict[str, Any]]:
        """Carrega estado do agente."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('SELECT state, context FROM agent_memory WHERE agent_id = ?', 
                      (agent_id,))
        result = cursor.fetchone()
        conn.close()
        
        if result:
            return {
                "state": json.loads(result[0]),
                "context": json.loads(result[1])
            }
        return None

memory_store = None

def get_memory_store() -> MemoryStore:
    global memory_store
    if memory_store is None:
        memory_store = MemoryStore()
    return memory_store
