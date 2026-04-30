"""Fallback baseado em Playwright para tarefas que exigem renderização JS."""

from typing import Any, Dict, Optional
from urllib.parse import quote_plus

from src.logging import get_logger
from config.settings import config

logger = get_logger(__name__)

class PlaywrightFallback:
    """
    Fallback via Playwright para quando integrações primárias (APIs) não bastam.

    Imports do Playwright são preguiçosos: o módulo carrega mesmo sem os
    browsers instalados. A falha só ocorre se o fallback for de fato acionado.

    Uso:
        with PlaywrightFallback() as pf:
            html = pf.fetch("https://example.com")
    """

    def __init__(
        self,
        headless: bool = config.PLAYWRIGHT_HEADLESS,
        timeout_ms: int = 30000,
        user_agent: Optional[str] = None,
        **kwargs: Any,
    ):
        self.headless = headless
        self.timeout_ms = timeout_ms
        self.user_agent = user_agent
        self.extra = kwargs
        self._playwright = None
        self._browser = None
        self._context = None

    # ---- ciclo de vida ---------------------------------------------------

    def start(self) -> "PlaywrightFallback":
        try:
            from playwright.sync_api import sync_playwright
        except ImportError as e:
            raise RuntimeError(
                "Playwright nao instalado. Rode: "
                "pip install playwright && playwright install chromium"
            ) from e

        self._playwright = sync_playwright().start()
        self._browser = self._playwright.chromium.launch(headless=self.headless)
        ctx_kwargs: Dict[str, Any] = {}
        if self.user_agent:
            ctx_kwargs["user_agent"] = self.user_agent
        self._context = self._browser.new_context(**ctx_kwargs)
        return self

    def close(self) -> None:
        try:
            if self._context:
                self._context.close()
            if self._browser:
                self._browser.close()
            if self._playwright:
                self._playwright.stop()
        except Exception as e:  # noqa: BLE001
            logger.warning("Erro fechando Playwright: %s", e)
        finally:
            self._context = self._browser = self._playwright = None

    def __enter__(self) -> "PlaywrightFallback":
        return self.start()

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    # ---- operacoes -------------------------------------------------------

    def fetch(self, url: str, wait_until: str = "load") -> str:
        """Abre a URL e devolve o HTML renderizado."""
        if not self._context:
            self.start()
        page = self._context.new_page()
        try:
            page.goto(url, wait_until=wait_until, timeout=self.timeout_ms)
            return page.content()
        finally:
            page.close()

    def screenshot(self, url: str, path: str, full_page: bool = True) -> str:
        if not self._context:
            self.start()
        page = self._context.new_page()
        try:
            page.goto(url, timeout=self.timeout_ms)
            page.screenshot(path=path, full_page=full_page)
            return path
        finally:
            page.close()

    def is_available(self) -> bool:
        try:
            import playwright  # noqa: F401
            return True
        except ImportError:
            return False


def run_playwright_fallback(prompt: str) -> Dict[str, Any]:
    """
    Como último recurso, usa o Playwright para pesquisar o prompt na web
    e extrair o conteúdo da primeira página de resultado.

    Nota: Requer `beautifulsoup4`. Instale com `pip install beautifulsoup4`.
    """
    logger.info("Acionando fallback final com Playwright para pesquisar na web.")

    try:
        from bs4 import BeautifulSoup
    except ImportError as e:
        raise RuntimeError(
            "BeautifulSoup não instalado. Rode: pip install beautifulsoup4"
        ) from e

    search_url = f"https://www.google.com/search?q={quote_plus(prompt)}"

    try:
        with PlaywrightFallback() as pf:
            # 1. Pesquisa no Google
            logger.debug(f"Buscando em: {search_url}")
            search_page_html = pf.fetch(search_url, wait_until="domcontentloaded")

            # 2. Extrai o primeiro link de resultado (seletor frágil)
            soup = BeautifulSoup(search_page_html, "html.parser")
            first_result_anchor = soup.select_one("div.g a[href^='http']")

            if not first_result_anchor or not first_result_anchor.get("href"):
                logger.warning("Não foi possível encontrar o primeiro link de resultado na pesquisa do Google.")
                raise IOError("Falha ao extrair link de resultado do Google.")

            target_url = first_result_anchor["href"]
            logger.info(f"Primeiro resultado encontrado: {target_url}")

            # 3. Busca o conteúdo da página de destino
            content_html = pf.fetch(target_url, wait_until="load")

            # 4. Limpa o HTML para extrair texto puro
            content_soup = BeautifulSoup(content_html, "html.parser")
            for script_or_style in content_soup(["script", "style"]):
                script_or_style.decompose()
            text_content = content_soup.get_text(separator="\n", strip=True)

            logger.info("Conteúdo extraído com sucesso via Playwright.")
            return {"text": text_content, "provider": "playwright-search", "model": "chromium/google"}
    except Exception as e:
        logger.critical(f"O fallback com Playwright também falhou: {e}", exc_info=False)
        raise


__all__ = ["PlaywrightFallback", "run_playwright_fallback"]
