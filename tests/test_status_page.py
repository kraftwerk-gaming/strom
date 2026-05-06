"""Integration test for the strom IPFS status page.

Serves the static status page, clicks 'Check all CIDs', and verifies
that at least 10 games return providers via the delegated routing API.
"""

import os
import threading
from http.server import HTTPServer, SimpleHTTPRequestHandler

import pytest
from playwright.sync_api import Page, expect

CHECK_ALL_TIMEOUT_MS = 120000
MIN_GAMES_WITH_PROVIDERS = 10


@pytest.fixture(scope="module")
def status_page_url():
    """Serve the pre-built status-page directory on a random port."""
    site_dir = os.environ["STATUS_PAGE_DIR"]

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=site_dir, **kwargs)

        def log_message(self, fmt, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{port}"
    server.shutdown()


def _wait_for_table(page: Page):
    """Wait for games.json to load and the table to render."""
    page.wait_for_function(
        """() => document.querySelectorAll('#game-table tr').length > 0""",
        timeout=10000,
    )


def _click_check_all_and_wait(page: Page):
    """Click 'Check all CIDs' and wait for completion."""
    page.click("#check-all")
    page.wait_for_function(
        """() => {
            const el = document.getElementById('progress');
            return el && el.textContent.includes('done');
        }""",
        timeout=CHECK_ALL_TIMEOUT_MS,
    )


def test_page_loads_json_and_renders_table(page: Page, status_page_url: str):
    """The table renders with game rows after loading games.json."""
    page.goto(status_page_url)
    _wait_for_table(page)
    rows = page.locator("#game-table tr")
    assert rows.count() > 10, f"Expected many game rows, got {rows.count()}"


def test_check_all_finds_providers(page: Page, status_page_url: str):
    """At least 10 games must have providers after checking."""
    page.goto(status_page_url)
    _wait_for_table(page)

    js_errors = []
    page.on("pageerror", lambda exc: js_errors.append(str(exc)))

    _click_check_all_and_wait(page)

    assert not js_errors, f"JS exceptions during check: {js_errors}"

    results = page.evaluate("() => results")
    games_with_providers = [
        name
        for name, data in results.items()
        if any(c["providers"] > 0 for c in data["perCid"])
    ]

    assert len(games_with_providers) >= MIN_GAMES_WITH_PROVIDERS, (
        f"Only {len(games_with_providers)} games had providers, "
        f"need at least {MIN_GAMES_WITH_PROVIDERS}. "
        f"Checked {len(results)} games total. "
        f"Games with providers: {games_with_providers}"
    )


def test_status_available_count(page: Page, status_page_url: str):
    """At least 10 games should show 'available' status in the DOM."""
    page.goto(status_page_url)
    _wait_for_table(page)
    _click_check_all_and_wait(page)

    available = page.locator("td.status-available")
    assert available.count() >= MIN_GAMES_WITH_PROVIDERS, (
        f"Only {available.count()} games showed 'available', "
        f"need at least {MIN_GAMES_WITH_PROVIDERS}"
    )
