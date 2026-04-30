"""Motor principal de orquestração DevSyn."""

import asyncio
from typing import List, Dict, Optional
from logging import Logger
import uuid
from .task import Task, TaskStatus
from .agent import Agent
from src.logging import get_logger
from config.settings import config

class OrchestrationEngine:
    def __init__(self):
        self.logger = get_logger('orchestration')
        self.agents: Dict[str, Agent] = {}
        self.tasks: Dict[str, Task] = {}
        self.running = False
        
    async def add_agent(self, agent_id: str, agent: Agent):
        """Adiciona agente ao motor."""
        self.agents[agent_id] = agent
        self.logger.info(f"Agent {agent_id} registered")
    
    async def create_task(self, name: str, context: Dict) -> str:
        """Cria nova tarefa."""
        task_id = str(uuid.uuid4())
        task = Task(id=task_id, name=name, context=context)
        self.tasks[task_id] = task
        self.logger.info(f"Task {task_id} created: {name}")
        return task_id
    
    async def execute_task(self, task_id: str, agent_id: str):
        """Executa tarefa com agente específico."""
        if task_id not in self.tasks:
            raise ValueError(f"Task {task_id} not found")
        
        task = self.tasks[task_id]
        if agent_id not in self.agents:
            raise ValueError(f"Agent {agent_id} not found")
        
        task.start()
        agent = self.agents[agent_id]
        
        try:
            result = await agent.execute(task)
            task.complete(result)
        except Exception as e:
            task.fail(str(e))
            self.logger.error(f"Task {task_id} failed: {str(e)}")
        
        return task
    
    async def start(self):
        """Inicia motor de orquestração."""
        self.running = True
        self.logger.info("Orchestration engine started")
    
    async def stop(self):
        """Para motor."""
        self.running = False
        self.logger.info("Orchestration engine stopped")
