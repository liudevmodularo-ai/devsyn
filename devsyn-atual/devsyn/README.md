# DevSyn - Plataforma Autônoma de Desenvolvimento 🚀

## 🏗️ Arquitetura
- **Orquestrador**: Flask + Agentes Autônomos
- **APIs**: OpenAI/Gemini + Playwright fallback
- **Armazenamento**: ChromaDB vetorial + SQLite
- **Deploy**: VPS Linux (script automático)

## 🚀 Deploy VPS (Ubuntu 22.04)

O processo é semi-automatizado e seguro. Você se conecta à sua VPS e executa o script de instalação.

```bash
# 1. Conecte-se à sua VPS via SSH
ssh seu_usuario@ip_da_vps

# 2. Clone o repositório e execute o script de instalação
git clone https://github.com/SEU_USERNAME/devsyn.git /opt/devsyn
cd /opt/devsyn
chmod +x install.sh
sudo DOMAIN="seu.dominio.com" ./install.sh
```

## 🛠️ Desenvolvimento Local
```bash
pip install -r requirements.txt
cp .env.example .env  # Configure API keys
python run.py
```
**Acesse:** http://localhost:5000

## 🔧 Configuração (.env)
```
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
MAX_AGENTS=10
```

## 📚 Documentação
- [ARQUITETURA.md](ARQUITETURA.md)
- [ESTADO_ATUAL.md](ESTADO_ATUAL.md)

[![Deploy](https://img.shields.io/badge/Deploy-VPS-green)](install.sh)
