# Arquitetura do Sistema

## Visão: Contexto Ilimitado
O sistema deve manter contexto ilimitado através de bancos vetoriais e memória local persistente, permitindo agentes autônomos trabalharem em projetos complexos sem perda de estado.

## Redundância de APIs/Playwright
- Integração primária com APIs de IA (OpenAI, Gemini, etc.)
- Fallback automático via Playwright para raspagem web quando APIs atingem limites
- Sistema resiliente com múltiplas camadas de contingência

## Componentes Principais
1. **Orquestração**: Flask app para gerenciar agentes
2. **Integrações**: Módulos para APIs e Playwright
3. **Armazenamento**: Vetorial para contexto, local para estado
4. **Logs/Auditoria**: Rastreamento completo de ações dos agentes