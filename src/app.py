"""Aplicação Flask principal - DevSyn Platform."""

from flask import Flask, request, jsonify, render_template_string
from src.logging import setup_logger
from src.orchestration.engine import OrchestrationEngine
from src.orchestration.agent import BaseAgent
from src.integrations.openai_client import get_openai_client
from src.storage.vector import get_vector_store
from config.settings import config
import asyncio
import os

# Configuração inicial
logger = setup_logger('app')
app = Flask(__name__)

# Inicializa componentes principais
orchestrator = OrchestrationEngine()
vector_store = get_vector_store()
openai_client = get_openai_client()

@app.route('/')
def index():
    """Página inicial."""
    html = '''
    <!DOCTYPE html>
    <html>
    <head><title>DevSyn Platform</title></head>
    <body>
        <h1>🚀 DevSyn - Plataforma de Desenvolvimento Autônomo</h1>
        <p><strong>Motor de orquestração:</strong> {{ status }}</p>
        <p><strong>Vector Store:</strong> {{ vector_status }}</p>
        <p><strong>OpenAI:</strong> {{ openai_status }}</p>
    </body>
    </html>
    '''
    status = "🟢 RUNNING" if config.OPENAI_API_KEY else "🟡 CONFIG REQUIRED"
    return render_template_string(html, 
                                status=status,
                                vector_status="🟢 READY",
                                openai_status="🟢 READY" if config.OPENAI_API_KEY else "🔴 NO API KEY")

@app.route('/api/health')
def health():
    """Health check."""
    return jsonify({
        "status": "healthy",
        "version": "0.1.0",
        "features": ["orchestration", "vector_storage", "openai", "logging"]
    })

@app.route('/api/tasks', methods=['POST'])
async def create_task():
    """Cria e executa tarefa."""
    data = request.json
    task_id = await orchestrator.create_task(data['name'], data.get('context', {}))
    
    # Executa com agente padrão
    result = await orchestrator.execute_task(task_id, "default")
    
    return jsonify({
        "task_id": task_id,
        "status": result.status.value,
        "result": result.result
    })

@app.route('/api/tasks/<task_id>')
def get_task(task_id):
    """Status da tarefa."""
    if task_id in orchestrator.tasks:
        task = orchestrator.tasks[task_id]
        return jsonify({
            "task_id": task.id,
            "status": task.status.value,
            "result": task.result
        })
    return jsonify({"error": "Task not found"}), 404

if __name__ == '__main__':
    logger.info("🚀 Starting DevSyn Platform")
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=True)
