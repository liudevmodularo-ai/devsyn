from flask import Flask, render_template, request, jsonify, abort
from config.settings import config, AI_PROVIDERS
from src.integrations.llm_client import invoke_llm
import os
from pathlib import Path
import logging
import uuid
import chromadb
import sqlite3
import json
import threading

# Configure logging
logging.basicConfig(level=config.LOG_LEVEL)
logger = logging.getLogger(__name__)

app = Flask(__name__, template_folder='templates', static_folder='static')

# --- Cliente ChromaDB ---
# Inicializa o cliente para o banco de dados vetorial persistente.
chroma_client = chromadb.PersistentClient(path=config.VECTOR_DB_PATH)
# Assume-se que uma coleção padrão 'devsyn_context' é usada.
context_collection = chroma_client.get_or_create_collection(name="devsyn_context")

# --- Persistent Task Manager (SQLite) ---
class TaskManager:
    def __init__(self, db_path):
        self.db_path = db_path
        self.lock = threading.Lock()
        self._init_db()

    def _get_conn(self):
        # A conexão deve ser criada por thread em um app web.
        # O timeout lida com a contenção de lock do SQLite.
        return sqlite3.connect(self.db_path, timeout=10)

    def _init_db(self):
        with self.lock:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS tasks (
                        id TEXT PRIMARY KEY,
                        description TEXT NOT NULL,
                        status TEXT NOT NULL,
                        result TEXT,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                conn.commit()

    def add_task(self, description):
        task_id = str(uuid.uuid4())
        with self.lock:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "INSERT INTO tasks (id, description, status) VALUES (?, ?, ?)",
                    (task_id, description, "doing")
                )
                conn.commit()
        logger.info(f"Task {task_id} added to the database.")
        return task_id

    def update_task(self, task_id, status, result=None):
        result_json = json.dumps(result) if result is not None else None
        with self.lock:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "UPDATE tasks SET status = ?, result = ? WHERE id = ?",
                    (status, result_json, task_id)
                )
                conn.commit()
        logger.info(f"Task {task_id} updated to status '{status}'.")

    def get_all_tasks(self):
        with self._get_conn() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute("SELECT id, description, status, result FROM tasks ORDER BY created_at DESC")
            tasks = []
            for row in cursor.fetchall():
                task = dict(row)
                if task['result']:
                    try:
                        # O resultado é armazenado como uma string JSON
                        task['result'] = json.loads(task['result'])
                    except json.JSONDecodeError:
                        task['result'] = {"error": "Invalid JSON result in DB"}
                tasks.append(task)
        return tasks

# Inicializa o TaskManager com um arquivo de banco de dados persistente
task_db_path = Path(config.VECTOR_DB_PATH).parent / "tasks.sqlite"
task_manager = TaskManager(db_path=str(task_db_path))

@app.route('/')
def index():
    """Serve a interface principal."""
    return render_template('index.html', providers=AI_PROVIDERS, fallback_order=config.FALLBACK_ORDER)

def build_file_tree(dir_path: Path):
    """Constrói recursivamente uma árvore de arquivos em formato de dicionário."""
    tree = []
    try:
        # Ordena para que as pastas apareçam antes dos arquivos
        for entry in sorted(dir_path.iterdir(), key=lambda e: (e.is_file(), e.name.lower())):
            # Ignora arquivos/pastas ocultas, venv e pycache
            if entry.name.startswith('.') or entry.name == 'venv' or entry.name == '__pycache__':
                continue
            
            node = {
                "name": entry.name,
                "path": str(entry.relative_to(Path('.').resolve())),
                "type": "folder" if entry.is_dir() else "file"
            }
            if entry.is_dir():
                node["children"] = build_file_tree(entry)
            
            tree.append(node)
    except OSError as e:
        logger.error(f"Erro ao escanear o diretório {dir_path}: {e}")
    return tree

@app.route('/api/files')
def api_files():
    """Endpoint para listar a estrutura de arquivos do projeto."""
    project_root = Path('.') # Escaneia a partir da raiz do projeto
    file_tree = build_file_tree(project_root)
    return jsonify(file_tree)

@app.route('/api/file-content')
def api_file_content():
    """Endpoint para obter o conteúdo de um arquivo de forma segura."""
    file_path_str = request.args.get('path')
    if not file_path_str:
        return jsonify({"error": "O parâmetro 'path' é obrigatório."}), 400

    project_root = Path('.').resolve()
    # Normaliza o caminho para evitar '..' e resolve o caminho absoluto
    target_path = project_root.joinpath(file_path_str).resolve()

    # Verificação de Segurança: Garante que o caminho do arquivo está dentro do diretório do projeto.
    if project_root not in target_path.parents and target_path != project_root:
        logger.warning(f"Tentativa de acesso a caminho inválido (Path Traversal): {target_path}")
        abort(403) # Forbidden

    if not target_path.is_file():
        return jsonify({"error": "O caminho especificado não é um arquivo válido."}), 404

    try:
        content = target_path.read_text(encoding='utf-8')
        return jsonify({"content": content, "path": file_path_str})
    except Exception as e:
        logger.error(f"Erro ao ler o arquivo {target_path}: {e}")
        return jsonify({"error": f"Não foi possível ler o arquivo: {e}"}), 500

@app.route('/api/save-file', methods=['POST'])
def api_save_file():
    """Endpoint para salvar o conteúdo de um arquivo de forma segura."""
    data = request.get_json()
    file_path_str = data.get('path')
    content = data.get('content')

    if not file_path_str or content is None:
        return jsonify({"error": "Os parâmetros 'path' e 'content' são obrigatórios."}), 400

    project_root = Path('.').resolve()
    target_path = project_root.joinpath(file_path_str).resolve()

    # Verificação de Segurança: Garante que o caminho do arquivo está dentro do diretório do projeto.
    if project_root not in target_path.parents and target_path != project_root:
        logger.warning(f"Tentativa de acesso a caminho inválido (Path Traversal): {target_path}")
        abort(403) # Forbidden

    try:
        target_path.write_text(content, encoding='utf-8')
        logger.info(f"Arquivo salvo com sucesso: {target_path}")
        return jsonify({"message": "Arquivo salvo com sucesso!", "path": file_path_str})
    except Exception as e:
        logger.error(f"Erro ao salvar o arquivo {target_path}: {e}")
        return jsonify({"error": f"Não foi possível salvar o arquivo: {e}"}), 500

@app.route('/api/context-info')
def api_context_info():
    """Endpoint para obter informações sobre o contexto (memória vetorial)."""
    vector_count = context_collection.count()
    return jsonify({"vector_count": vector_count})

@app.route('/api/tasks')
def api_tasks():
    """Endpoint para obter a lista de tarefas e seus status."""
    return jsonify(task_manager.get_all_tasks())

@app.route('/api/chat', methods=['POST'])
def api_chat():
    """Endpoint para interagir com os agentes de IA."""
    data = request.get_json()
    if not data or 'message' not in data:
        return jsonify({"error": "A chave 'message' não foi fornecida."}), 400

    prompt = data['message']
    logger.info(f"Recebido prompt para /api/chat: '{prompt}'")

    task_id = task_manager.add_task(prompt)

    try:
        # As chaves de API são lidas do ambiente do servidor (.env).
        response = invoke_llm(prompt)

        # Adiciona o prompt do usuário e a resposta do agente ao contexto vetorial
        context_collection.add(
            documents=[prompt, response['text']],
            metadatas=[{"source": "user_prompt"}, {"source": "agent_response"}],
            # Usa o task_id para criar IDs únicos e relacionados
            ids=[f"user-{task_id}", f"agent-{task_id}"]
        )
        logger.info(f"Prompt e resposta da tarefa {task_id} adicionados ao contexto vetorial.")

        task_manager.update_task(task_id, "done", response)
        return jsonify(response)
    except Exception as e:
        logger.error(f"Erro crítico ao processar o chat: {e}", exc_info=True)
        error_details = {"error": "Falha ao se comunicar com o provedor de IA.", "details": str(e)}
        task_manager.update_task(task_id, "error", error_details)
        return jsonify({"error": "Falha ao se comunicar com o provedor de IA.", "details": str(e)}), 500

if __name__ == '__main__':
    logger.info("Iniciando servidor de desenvolvimento Flask...")
    # Nota: Em produção, use Gunicorn conforme o install.sh
    app.run(host='0.0.0.0', port=5000, debug=True)