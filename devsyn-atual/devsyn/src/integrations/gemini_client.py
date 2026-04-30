"""Cliente Gemini como segunda opção."""

import google.generativeai as genai
from typing import Optional, List, Dict
from logging import Logger
from config.settings import config
from src.logging import get_logger

class GeminiClient:
    def __init__(self):
        genai.configure(api_key=config.GEMINI_API_KEY)
        self.model = genai.GenerativeModel('gemini-1.5-flash')
        self.logger = get_logger('integrations.gemini')
    
    def chat(self, messages: List[Dict[str, str]]) -> Optional[str]:
        """Chat com Gemini."""
        try:
            history = []
            for msg in messages:
                role = "user" if msg['role'] == "user" else "model"
                history.append(f"{role}: {msg['content']}")
            
            prompt = "\\n".join(history[-10:])  # Últimas 10 mensagens
            
            response = self.model.generate_content(prompt)
            if response.text:
                self.logger.debug(f"Gemini success: {len(response.text)} chars")
                return response.text
            return None
                
        except Exception as e:
            self.logger.error(f"Gemini error: {str(e)}")
            return None

gemini_client = None

def get_gemini_client() -> GeminiClient:
    global gemini_client
    if gemini_client is None:
        gemini_client = GeminiClient()
    return gemini_client
