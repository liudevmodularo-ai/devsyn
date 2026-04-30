import { EditorView, basicSetup } from "https://cdn.jsdelivr.net/npm/codemirror@6.0.1/dist/index.min.js";
import { EditorState } from "https://cdn.jsdelivr.net/npm/@codemirror/state@6.4.1/dist/index.min.js";
import { python } from "https://cdn.jsdelivr.net/npm/@codemirror/lang-python@6.1.6/dist/index.min.js";
import { oneDark } from "https://cdn.jsdelivr.net/npm/@codemirror/theme-one-dark@6.1.2/dist/index.min.js";


document.addEventListener('DOMContentLoaded', () => {
    const settingsBtn = document.querySelector('.settings-btn');
    const settingsModalOverlay = document.querySelector('.settings-modal-overlay');
    const closeBtn = document.querySelector('.settings-modal .close-btn');
    const saveSettingsBtn = document.querySelector('.save-settings-btn');

    // --- Lógica do Modal ---
    const openSettingsModal = () => {
        if (settingsModalOverlay) {
            settingsModalOverlay.classList.remove('hidden');
        }
    };

    const closeSettingsModal = () => {
        if (settingsModalOverlay) {
            settingsModalOverlay.classList.add('hidden');
        }
    };

    if (settingsBtn) {
        settingsBtn.addEventListener('click', openSettingsModal);
    }

    if (closeBtn) {
        closeBtn.addEventListener('click', closeSettingsModal);
    }

    if (settingsModalOverlay) {
        // Fecha o modal ao clicar no fundo
        settingsModalOverlay.addEventListener('click', (event) => {
            if (event.target === settingsModalOverlay) {
                closeSettingsModal();
            }
        });
    }

    // --- Persistência das Configurações (localStorage) ---
    const providerInputs = document.querySelectorAll('.provider-config input[type="password"]');

    const saveSettings = () => {
        providerInputs.forEach(input => {
            // Salva a chave no localStorage usando o ID do input (ex: 'key-openai')
            if (input.value) {
                localStorage.setItem(input.id, input.value);
            } else {
                // Remove a chave se o campo estiver vazio
                localStorage.removeItem(input.id);
            }
        });
        alert('Configurações salvas localmente!');
        closeSettingsModal();
    };

    const loadSettings = () => {
        providerInputs.forEach(input => {
            const savedKey = localStorage.getItem(input.id);
            if (savedKey) {
                input.value = savedKey;
            }
        });
    };

    if (saveSettingsBtn) {
        saveSettingsBtn.addEventListener('click', saveSettings);
    }

    // Carrega as configurações salvas assim que a página é carregada
    loadSettings();

    // --- Lógica do Chat ---
    const chatInput = document.getElementById('chat-input');
    const chatMessages = document.getElementById('chat-messages');

    const addMessage = (text, sender, type = 'message') => {
        const messageEl = document.createElement('div');
        messageEl.classList.add(type, sender);
        messageEl.textContent = text;
        chatMessages.appendChild(messageEl);
        // Auto-scroll para a nova mensagem
        chatMessages.scrollTop = chatMessages.scrollHeight;
    };

    const showTypingIndicator = () => {
        const typingEl = document.createElement('div');
        typingEl.classList.add('message', 'agent', 'typing-indicator');
        typingEl.innerHTML = '<span></span><span></span><span></span>';
        chatMessages.appendChild(typingEl);
        chatMessages.scrollTop = chatMessages.scrollHeight;
    };

    const removeTypingIndicator = () => {
        const typingEl = document.querySelector('.typing-indicator');
        if (typingEl) {
            typingEl.remove();
        }
    };

    const handleSendMessage = async () => {
        const messageText = chatInput.value.trim();
        if (!messageText) return;

        addMessage(messageText, 'user');
        chatInput.value = '';
        chatInput.disabled = true;
        showTypingIndicator();

        try {
            const response = await fetch('/api/chat', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ message: messageText }),
            });

            removeTypingIndicator();

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.details || 'A resposta da API não foi bem-sucedida.');
            }

            const data = await response.json();
            addMessage(data.text, 'agent');
        } catch (error) {
            console.error('Erro ao enviar mensagem:', error);
            addMessage(`Erro ao contatar o agente: ${error.message}`, 'agent', 'error');
        } finally {
            chatInput.disabled = false;
            chatInput.focus();
        }
    };

    if (chatInput) {
        chatInput.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                handleSendMessage();
            }
        });
    }

    // --- Lógica do Editor de Código (CodeMirror) ---
    const editorContainer = document.getElementById('editor-container');
    let editorView = null;
    let currentFilePath = null;
    const saveFileBtn = document.getElementById('save-file-btn');

    const initializeEditor = () => {
        if (!editorContainer) return;

        const initialState = EditorState.create({
            doc: "// Selecione um arquivo na árvore de projetos para começar.",
            extensions: [
                basicSetup,
                python(),
                oneDark,
                EditorView.lineWrapping,
                EditorState.readOnly.of(true) // Começa como somente leitura
            ]
        });

        editorView = new EditorView({
            state: initialState,
            parent: editorContainer
        });
    };

    const loadFileContent = async (filePath) => {
        if (!editorView) return;
        
        // Desabilita o botão de salvar enquanto carrega
        saveFileBtn.disabled = true;

        try {
            const response = await fetch(`/api/file-content?path=${encodeURIComponent(filePath)}`);
            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.error || 'Falha ao carregar o arquivo.');
            }
            const data = await response.json();
            currentFilePath = data.path;

            // Habilita a edição e atualiza o conteúdo
            editorView.dispatch({
                changes: { from: 0, to: editorView.state.doc.length, insert: data.content },
                effects: EditorState.readOnly.of(false)
            });

            // Habilita o botão de salvar
            saveFileBtn.disabled = false;

        } catch (error) {
            console.error('Erro ao carregar conteúdo do arquivo:', error);
            currentFilePath = null;
            editorView.dispatch({
                changes: { from: 0, to: editorView.state.doc.length, insert: `// Erro ao carregar ${filePath}\n// ${error.message}` },
                effects: EditorState.readOnly.of(true)
            });
        }
    };

    const handleSaveFile = async () => {
        if (!currentFilePath || !editorView || saveFileBtn.disabled) return;

        const content = editorView.state.doc.toString();
        saveFileBtn.textContent = 'Salvando...';
        saveFileBtn.disabled = true;

        try {
            const response = await fetch('/api/save-file', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: currentFilePath, content: content }),
            });
            if (!response.ok) throw new Error('Falha ao salvar o arquivo.');
            // Poderíamos adicionar um toast/notificação de sucesso aqui
        } catch (error) {
            console.error('Erro ao salvar arquivo:', error);
            alert(`Erro ao salvar: ${error.message}`); // Alerta simples por enquanto
        } finally {
            saveFileBtn.textContent = 'Salvar';
            saveFileBtn.disabled = false;
        }
    };

    // --- Lógica da Área de Progresso ---
    const taskList = document.getElementById('task-list');
    const statusMap = {
        'doing': { icon: '⏳', text: 'Em andamento' },
        'done': { icon: '✅', text: 'Concluído' },
        'error': { icon: '❌', text: 'Falhou' },
        'todo': { icon: '📋', text: 'A fazer' }
    };

    const renderTasks = (tasks) => {
        if (!taskList) return;
        taskList.innerHTML = ''; // Limpa a lista

        if (tasks.length === 0) {
            const li = document.createElement('li');
            li.textContent = 'Nenhuma tarefa iniciada.';
            li.style.color = 'var(--text-color-secondary)';
            li.style.paddingLeft = '16px';
            taskList.appendChild(li);
            return;
        }

        // Mostra as tarefas mais recentes primeiro
        tasks.reverse().forEach(task => {
            const li = document.createElement('li');
            li.classList.add('task-item');
            const status = statusMap[task.status] || statusMap['todo'];
            
            li.innerHTML = `
                <span title="${status.text}">${status.icon}</span>
                <span>${task.description}</span>
            `;
            taskList.appendChild(li);
        });
    };

    const fetchAndRenderTasks = async () => {
        try {
            const response = await fetch('/api/tasks');
            if (!response.ok) throw new Error('Falha ao buscar tarefas.');
            const tasks = await response.json();
            renderTasks(tasks);
        } catch (error) {
            console.error(error);
        }
    };

    // --- Lógica do File Tree ---
    const fileTreeContainer = document.getElementById('file-tree');

    const createTreeItem = (item) => {
        const itemEl = document.createElement('div');
        itemEl.classList.add('tree-item');
        itemEl.dataset.path = item.path;

        if (item.type === 'folder') {
            itemEl.classList.add('tree-folder', 'collapsed');
            itemEl.innerHTML = `
                <span class="folder-toggle">▶</span>
                <span>📁</span>
                <span class="item-name">${item.name}</span>
            `;
        } else {
            itemEl.classList.add('tree-file');
            itemEl.innerHTML = `
                <span style="width: 10px; display: inline-block;"></span>
                <span>📄</span>
                <span class="item-name">${item.name}</span>
            `;
        }
        return itemEl;
    };

    const renderTree = (nodes, container) => {
        nodes.forEach(node => {
            const itemEl = createTreeItem(node);
            container.appendChild(itemEl);

            if (node.type === 'folder' && node.children && node.children.length > 0) {
                const childrenContainer = document.createElement('div');
                childrenContainer.classList.add('tree-children', 'hidden');
                container.appendChild(childrenContainer);

                itemEl.addEventListener('click', () => {
                    itemEl.classList.toggle('collapsed');
                    childrenContainer.classList.toggle('hidden');
                    const toggle = itemEl.querySelector('.folder-toggle');
                    if (toggle) {
                        toggle.textContent = itemEl.classList.contains('collapsed') ? '▶' : '▼';
                    }
                });

                renderTree(node.children, childrenContainer);
            } else if (node.type === 'file') {
                itemEl.addEventListener('click', (e) => {
                    e.stopPropagation(); // Impede que o clique se propague para a pasta pai
                    loadFileContent(node.path);

                    document.querySelectorAll('.tree-item.active').forEach(activeEl => {
                        activeEl.classList.remove('active');
                    });
                    itemEl.classList.add('active');
                });
            }
        });
    };

    const loadAndRenderFileTree = async () => {
        if (!fileTreeContainer) return;
        try {
            const response = await fetch('/api/files');
            if (!response.ok) throw new Error('Falha ao buscar a árvore de arquivos');
            const fileTreeData = await response.json();
            fileTreeContainer.innerHTML = ''; // Limpa conteúdo anterior
            renderTree(fileTreeData, fileTreeContainer);
        } catch (error) {
            console.error('Erro ao carregar a árvore de arquivos:', error);
            fileTreeContainer.innerHTML = '<div class="tree-item error">Falha ao carregar arquivos.</div>';
        }
    };

    // --- Lógica de Contexto ---
    const contextInfoDisplay = document.getElementById('context-info-display');

    const updateContextInfo = async () => {
        if (!contextInfoDisplay) return;
        try {
            const response = await fetch('/api/context-info');
            if (!response.ok) throw new Error('Falha ao buscar informações de contexto.');
            const data = await response.json();
            contextInfoDisplay.textContent = `🧠 Contexto: ${data.vector_count} vetores`;
        } catch (error) {
            console.error(error);
            contextInfoDisplay.textContent = '🧠 Contexto: Erro';
        }
    };

    if (saveFileBtn) {
        saveFileBtn.addEventListener('click', handleSaveFile);
    }

    // Inicia o polling da lista de tarefas
    fetchAndRenderTasks();
    updateContextInfo(); // Chama uma vez no início
    setInterval(fetchAndRenderTasks, 3000); // Atualiza a cada 3 segundos
    setInterval(updateContextInfo, 10000); // Atualiza a cada 10 segundos

    initializeEditor();
    loadAndRenderFileTree();
});