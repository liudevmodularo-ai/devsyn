"""
Exemplo de um agente especializado que utiliza o cliente LLM unificado.
"""

from typing import Any
from src.orchestration.agent import BaseAgent
from src.orchestration.task import Task
from src.integrations.llm_client import invoke_llm

class DeveloperAgent(BaseAgent):
    """
    Um agente especializado em escrever e analisar código.
    """
    async def execute(self, task: Task) -> Any:
        """
        Executa uma tarefa de desenvolvimento usando o cliente LLM.
        """
        self.logger.info(f"Iniciando tarefa: {task.description}")
        
        prompt = task.description
        
        await self._log_action(
            action="invoke_llm_start",
            context={"prompt": prompt}
        )

        try:
            # Usa o novo cliente LLM unificado
            llm_response = invoke_llm(prompt)
            
            result = {
                "code": llm_response["text"],
                "provider": llm_response["provider"],
                "model": llm_response["model"],
            }

            await self._log_action(action="llm_success", context=result)
            self.logger.info(f"Tarefa concluída com sucesso usando {result['provider']}.")
            return result

        except Exception as e:
            self.logger.error(f"Tarefa falhou após todos os fallbacks: {e}")
            await self._log_action(action="llm_failure", context={"error": str(e)})
            return {"error": "Falha ao completar a tarefa.", "details": str(e)}