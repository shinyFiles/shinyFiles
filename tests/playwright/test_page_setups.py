"""shinyFiles buttons in page layouts that render their UI differently.

Each layout must load shinyFiles' script once, so a click opens exactly one
dialog. These run against small apps of their own, started per test.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap
import time
import urllib.request
from pathlib import Path

import pytest
from playwright.sync_api import Page, expect

from conftest import RSCRIPT, _free_port

PKG = Path(__file__).resolve().parent.parent.parent

APPS = {
    # #192: a button inside a bslib accordion panel, and one outside it.
    "bslib_accordion": """
        ui <- bslib::page_fillable(
          shinyDirButton("outside", "Outside", "Pick"),
          bslib::accordion(bslib::accordion_panel("Panel",
            shinyDirButton("inside", "Inside", "Pick")))
        )
    """,
    # #172: a button hidden with shinyjs inside renderUI.
    "shinyjs_hidden": """
        ui <- fluidPage(shinyjs::useShinyjs(),
          shinyDirButton("outside", "Outside", "Pick"),
          uiOutput("dyn"))
        extra <- function(input, output, session) {
          output$dyn <- renderUI(tagList(
            shinyDirButton("inside", "Inside", "Pick"),
            shinyjs::hidden(shinyDirButton("hiddenbtn", "Hidden", "Pick"))
          ))
        }
    """,
    # An app that also links the script itself, as custom HTML pages are told to.
    "linked_by_hand": """
        ui <- fluidPage(tags$head(tags$script(src = "sF/shinyFiles.js")),
          shinyDirButton("outside", "Outside", "Pick"),
          shinyDirButton("inside", "Inside", "Pick"))
    """,
    # Buttons that only arrive later through renderUI.
    "render_ui": """
        ui <- fluidPage(uiOutput("dyn"), shinyDirButton("outside", "Outside", "Pick"))
        extra <- function(input, output, session) {
          output$dyn <- renderUI(shinyDirButton("inside", "Inside", "Pick"))
        }
    """,
}


def _start(name: str, tmp: Path):
    root = tmp / "root"
    (root / "sub").mkdir(parents=True)
    app = tmp / "app.R"
    body = textwrap.dedent(APPS[name])
    app.write_text(textwrap.dedent(f"""
        library(shiny)
        pkgload::load_all({str(PKG)!r}, quiet = TRUE, export_all = FALSE)
        roots <- c(r = {str(root)!r})
        extra <- function(input, output, session) NULL
    """) + body + textwrap.dedent("""
        server <- function(input, output, session) {
          for (id in c("outside", "inside", "hiddenbtn")) shinyDirChoose(input, id, roots = roots)
          extra(input, output, session)
        }
        shinyApp(ui, server)
    """))
    port = _free_port()
    log = open(tmp / "app.log", "w")
    proc = subprocess.Popen([RSCRIPT, "-e", f"shiny::runApp({str(tmp)!r}, port = {port})"],
                            stdout=log, stderr=subprocess.STDOUT)
    url = f"http://127.0.0.1:{port}/"
    for _ in range(120):
        if proc.poll() is not None:
            raise RuntimeError((tmp / "app.log").read_text())
        try:
            urllib.request.urlopen(url, timeout=1)
            return proc, url
        except OSError:
            time.sleep(0.5)
    proc.kill()
    raise RuntimeError("app did not start")


@pytest.fixture(params=list(APPS))
def layout_app(request, page: Page):
    pkg = {"bslib_accordion": "bslib", "shinyjs_hidden": "shinyjs"}.get(request.param)
    if pkg and subprocess.run([RSCRIPT, "-e", f"quit(status = !requireNamespace('{pkg}', quietly = TRUE))"]).returncode:
        pytest.skip(f"{pkg} is not installed")
    tmp = Path(tempfile.mkdtemp(prefix="sf-layout-"))
    proc = None
    try:
        proc, url = _start(request.param, tmp)
        page.goto(url)
        page.url_layout = request.param
        page.wait_for_function("window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected()")
        page.wait_for_selector("button#inside.shiny-bound-input")
        yield page
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(10)
            except subprocess.TimeoutExpired:
                proc.kill()
        shutil.rmtree(tmp, ignore_errors=True)


def test_the_script_loads_once_and_a_click_opens_one_dialog(layout_app: Page):
    page = layout_app
    scripts = page.evaluate("() => document.querySelectorAll('script[src*=\"shinyFiles.js\"]').length")
    # The hand-linked copy is the app's own; the buttons must not add another.
    assert scripts == (2 if page.url_layout == "linked_by_hand" else 1), f"shinyFiles.js is loaded {scripts} times"
    for button in ("outside", "inside"):
        page.click(f"#{button}")
        expect(page.locator(".sF-modalContainer")).to_have_count(1)
        page.locator(".sF-modalContainer #sF-cancelButton").click()
        expect(page.locator(".sF-modalContainer")).to_have_count(0)
