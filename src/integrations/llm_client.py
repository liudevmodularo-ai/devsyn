"""
Cliente unificado para múltiplos provedores de LLM com lógica de fallback.
"""

from typing import Dict, Any, Optional

# Assume-se que os clientes estão instalados via requirements.txt
# pip install openai google-generativeai groq
import openai
import google.generativeai as genai
from groq import Groq

from config.settings import config
from src.logging import get_logger
from .fallback import run_playwright_fallback

logger = get_logger(__name__)

# A ordem de fallback pode ser dinamizada a partir da config no futuro
FALLBACK_ORDER = ["openai", "gemini", "groq"]

# --- Implementações específicas por provedor ---

def _call_openai(prompt: str, model: str) -> str:
    """Chama a API da OpenAI."""
    client = openai.OpenAI(api_key=config.OPENAI_API_KEY)
    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
    )
    return response.choices[0].message.content

def _call_gemini(prompt: str, model: str) -> str:
    """Chama a API do Google Gemini."""
    genai.configure(api_key=config.GEMINI_API_KEY)
    gemini_model = genai.GenerativeModel(model)
    response = gemini_model.generate_content(prompt)
    return response.text

def _call_groq(prompt: str, model: str) -> str:
    """Chama a API da Groq."""
    client = Groq(api_key=config.GROQ_API_KEY)
    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
    )
    return response.choices[0].message.content

# --- Invocador principal com lógica de Fallback ---

PROVIDER_MAP = {
    "openai": {
        "caller": _call_openai,
        "api_key_name": "OPENAI_API_KEY",
        "default_model": "gpt-4o",
    },
    "gemini": {
        "caller": _call_gemini,
        "api_key_name": "GEMINI_API_KEY",
        "default_model": "gemini-1.5-flash",
    },
    "groq": {
        "caller": _call_groq,
        "api_key_name": "GROQ_API_KEY",
        "default_model": "llama3-8b-8192",
    },
    # Adicione Anthropic, Cohere, etc. aqui no futuro
}

def invoke_llm(prompt: str, model_override: Optional[str] = None) -> Dict[str, Any]:
    """
    Invoca um LLM usando a ordem de fallback padrão.

    Retorna:
        Um dicionário com o resultado, provedor e modelo usados.
        Ex: {'text': '...', 'provider': 'openai', 'model': 'gpt-4o'}
    
    Levanta:
        Exception: Se todos os provedores na cadeia falharem.
    """
    for provider_name in FALLBACK_ORDER:
        provider_config = PROVIDER_MAP.get(provider_name)
        if not provider_config:
            logger.warning(f"Provedor '{provider_name}' não configurado. Pulando.")
            continue

        api_key = getattr(config, provider_config["api_key_name"], None)
        if not api_key or api_key == "your_api_key_here":
            logger.debug(f"Chave de API para '{provider_name}' não encontrada. Pulando.")
            continue

        model = model_override or provider_config["default_model"]
        
        try:
            logger.info(f"Tentando usar o provedor: {provider_name} com o modelo: {model}")
            result_text = provider_config["caller"](prompt, model)
            logger.info(f"Resposta recebida com sucesso de {provider_name}.")
            return {"text": result_text, "provider": provider_name, "model": model}
        except Exception as e:
            logger.error(f"Provedor '{provider_name}' falhou: {e}", exc_info=False)
            # Continua para o próximo provedor na cadeia de fallback
    
    # Fallback final para o Playwright
    logger.warning("Todos os provedores de LLM falharam. Acionando fallback com Playwright.")
    try:
        return run_playwright_fallback(prompt)
    except Exception as e:
        logger.critical(f"O fallback final com Playwright também falhou: {e}")
        raise Exception("Todos os provedores de LLM e o fallback final falharam.") from e