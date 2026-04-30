"""Sistema de auditoria para ações dos agentes."""

import logging
import json
from datetime import datetime
from typing import Dict, Any

class AuditLogger:
    """Logger especializado para auditoria de agentes."""
    
    def __init__(self, logger: logging.Logger):
        self.logger = logger
        self.audit_file = "logs/audit.jsonl"
    
    def log_action(self, agent_id: str, action: str, 
                   context: Dict[str, Any], result: Any = None):
        """Registra ação completa do agente."""
        audit_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'agent_id': agent_id,
            'action': action,
            'context': context,
            'result': result
        }
        
        self.logger.info(
            f"AUDIT[{agent_id}]: {action}",
            extra={'audit': audit_entry}
        )
        
        # Salva em arquivo JSONL
        with open(self.audit_file, 'a') as f:
            f.write(json.dumps(audit_entry) + '\\n')

audit_logger = None

def get_audit_logger() -> AuditLogger:
    global audit_logger
    if audit_logger is None:
        logger = get_logger('audit')
        audit_logger = AuditLogger(logger)
    return audit_logger
