"""Classe base para agentes autonomos."""

import asyncio
from abc import ABC, abstractmethod
from typing import Dict, Any
from src.logging import get_logger, get_audit_logger
from src.orchestration.task import Task
from config.settings import config


class BaseAgent(ABC):
    """Classe base para todos os agentes."""

    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self.logger = get_logger(f'agent.{agent_id}')
        self.audit = get_audit_logger()

    @abstractmethod
    async def execute(self, task: Task) -> Any:
        """Executa tarefa especifica do agente."""
        pass

    async def _log_action(self, action: str, context: Dict[str, Any]):
        """Log de acao padronizado."""
        self.audit.log_action(self.agent_id, action, context)


# Alias para compatibilidade com outros modulos que importam 'Agent'
Agent = BaseAgent
