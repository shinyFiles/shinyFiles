"""Touch: a tap opens a folder on a touch screen, where there is no double-click
(#36). Run in a browser context with touch enabled, using real taps (pointer
events with pointerType "touch"), so a mouse double-click still works as before."""

from __future__ import annotations

import pytest
from playwright.sync_api import Browser, Page, expect

from helpers import Dialog


@pytest.fixture
def touch_app(browser: Browser, app_url, browser_name):
    if browser_name == "firefox":
        pytest.skip("Firefox does not support touch emulation in Playwright")
    context = browser.new_context(has_touch=True, is_mobile=False, viewport={"width": 1100, "height": 800})
    page = context.new_page()
    errors: list[str] = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(app_url)
    page.wait_for_function("window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected()")
    page.wait_for_selector("button#file.shiny-bound-input")
    yield page
    context.close()
    assert errors == []


def tap(d: Dialog, name: str) -> None:
    d.find(".sF-fileList").locator(".sF-file, .sF-directory").filter(
        has=d.page.locator(".sF-file-name", has_text=name)
    ).first.tap()
    # Desktop Chrome turns two quick taps into a dblclick, but touch browsers
    # such as iOS Safari use a double tap to zoom and send no dblclick. Taps
    # are spaced out so the tests don't lean on one.
    d.page.wait_for_timeout(700)


@pytest.mark.parametrize("button", ["file", "save"])
def test_tapping_a_selected_folder_opens_it(touch_app: Page, button):
    d = Dialog(touch_app, button).open()
    tap(d, "folder")
    # The first tap selects, as a click does.
    expect(d.find(".sF-fileList .sF-directory.selected")).to_have_count(1)
    assert d.location() == [""]
    d.after_listing(lambda: tap(d, "folder"))
    assert d.location() == ["", "folder"]


def test_a_mouse_double_click_still_opens_a_folder(app: Page):
    d = Dialog(app, "file").open()
    d.after_listing(lambda: d.dblclick_row("folder"))
    assert d.location() == ["", "folder"]


def test_one_mouse_click_on_a_selected_folder_does_not_open_it(app: Page):
    # On a mouse, a second single click deselects as before; only taps open.
    d = Dialog(app, "file").open()
    d.click_row("folder")
    d.click_row("folder")
    app.wait_for_timeout(600)
    assert d.location() == [""]


def test_the_folder_dialog_needs_no_double_tap(touch_app: Page):
    # Its tree opens a folder with the arrow and selects one with a single tap.
    d = Dialog(touch_app, "dir").open()
    d.find(".sF-dirList .sF-directory.root > .sF-file-name").first.tap()
    touch_app.wait_for_timeout(700)
    node = d.tree_node("folder")
    node.locator(":scope > .sF-expander > span").tap()
    touch_app.wait_for_timeout(700)
    expect(d.tree_node("sub")).to_be_visible()
    d.tree_node("sub").locator(":scope > .sF-file-name").tap()
    touch_app.wait_for_timeout(700)
    expect(d.find(".sF-dirList .selected > .sF-file-name")).to_have_text("sub")
