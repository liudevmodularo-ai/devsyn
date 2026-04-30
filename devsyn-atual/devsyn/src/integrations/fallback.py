"""Fallback baseado em Playwright para tarefas que exigem renderização JS."""

import logging
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


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
        headless: bool = True,
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


__all__ = ["PlaywrightFallback"]
