"""Sistema de auditoria para acoes dos agentes."""

import logging
import json
import os
from datetime import datetime
from typing import Dict, Any
from .logger import get_logger


class AuditLogger:
    """Logger especializado para auditoria de agentes."""

    def __init__(self, logger: logging.Logger):
        self.logger = logger
        self.audit_file = "logs/audit.jsonl"
        os.makedirs(os.path.dirname(self.audit_file), exist_ok=True)

    def log_action(self, agent_id: str, action: str,
                   context: Dict[str, Any], result: Any = None):
        """Registra acao completa do agente."""
        audit_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'agent_id': agent_id,
            'action': action,
            'context': context,
            'result': result,
        }

        self.logger.info(
            f"AUDIT[{agent_id}]: {action}",
            extra={'audit': audit_entry},
        )

        # Salva em arquivo JSONL (uma entrada por linha — sem escapar \n)
        with open(self.audit_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(audit_entry, ensure_ascii=False) + '\n')


_audit_logger: "AuditLogger | None" = None


def get_audit_logger() -> AuditLogger:
    """Singleton acessor para o AuditLogger."""
    global _audit_logger
    if _audit_logger is None:
        _audit_logger = AuditLogger(get_logger('audit'))
    return _audit_logger
