"""Cliente OpenAI com retry e fallback."""

import openai
from typing import Optional, List, Dict, Any
from openai import AsyncOpenAI
import asyncio
from logging import Logger
from config.settings import config
from src.logging import get_logger

class OpenAIClient:
    def __init__(self):
        self.client = AsyncOpenAI(
            api_key=config.OPENAI_API_KEY,
        )
        self.logger = get_logger('integrations.openai')
    
    async def chat_completion(self, 
                            messages: List[Dict[str, str]],
                            model: str = "gpt-4o-mini",
                            max_retries: int = 3,
                            **kwargs) -> Optional[str]:
        """Chat completion com retry automático."""
        
        for attempt in range(max_retries):
            try:
                response = await self.client.chat.completions.create(
                    model=model,
                    messages=messages,
                    **kwargs
                )
                content = response.choices[0].message.content
                self.logger.debug(f"OpenAI success (attempt {attempt + 1}): {len(content)} chars")
                return content
                
            except openai.RateLimitError:
                if attempt < max_retries - 1:
                    wait = (2 ** attempt) + 1
                    self.logger.warning(f"Rate limit, waiting {wait}s (attempt {attempt + 1})")
                    await asyncio.sleep(wait)
                else:
                    self.logger.error("Max retries reached for OpenAI")
                    raise
            
            except Exception as e:
                self.logger.error(f"OpenAI error (attempt {attempt + 1}): {str(e)}")
                if attempt == max_retries - 1:
                    raise
        
        return None

openai_client = None

def get_openai_client() -> OpenAIClient:
    global openai_client
    if openai_client is None:
        openai_client = OpenAIClient()
    return openai_client
