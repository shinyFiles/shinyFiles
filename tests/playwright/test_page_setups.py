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
    # A Bootstrap 5 theme, which pads and pushes modals down further.
    "bslib_bs5": """
        ui <- bslib::page_fluid(theme = bslib::bs_theme(version = 5),
          shinyDirButton("outside", "Outside", "Pick"),
          shinySaveButton("inside", "Inside", "Save", filetype = list(text = "txt")))
        extra <- function(input, output, session) shinyFileSave(input, "inside", roots = roots)
    """,
    # A file name far wider than the folder dialog's content pane (#188).
    "long_names": """
        writeLines("x", file.path(roots[["r"]], paste0(strrep("a_long_file_name_", 6), ".txt")))
        ui <- fluidPage(shinyDirButton("outside", "Outside", "Pick"), shinyDirButton("inside", "Inside", "Pick"))
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
        skip <- if ({name!r} == "bslib_bs5") "inside" else character(0)
    """) + body + textwrap.dedent("""
        server <- function(input, output, session) {
          for (id in setdiff(c("outside", "inside", "hiddenbtn"), skip)) shinyDirChoose(input, id, roots = roots)
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
    pkg = {"bslib_accordion": "bslib", "bslib_bs5": "bslib", "shinyjs_hidden": "shinyjs"}.get(request.param)
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


@pytest.mark.parametrize("height", [720, 480])
def test_the_dialog_fits_the_window_whatever_loads_first(layout_app: Page, height):
    # The stylesheet comes as a dependency, so it may load before Bootstrap's.
    # Its toolbar must stay on one row, with the root drop-down in it, and
    # Cancel must stay on screen, Bootstrap 3 or 5, on a short window too.
    page = layout_app
    page.set_viewport_size({"width": 1280, "height": height})
    for button in ("outside", "inside"):
        page.click(f"#{button}")
        modal = page.locator(".sF-modalContainer").last
        expect(modal.locator("#sF-cancelButton")).to_be_visible()
        # Measured once the dialog has stopped sliding in and its listing is drawn.
        page.wait_for_function("""() => {
          const d = $('.sF-modalContainer:visible').last().find('.modal-dialog')[0];
          const y = d && d.getBoundingClientRect().top;
          const settled = window.__sfLastY === y;
          window.__sfLastY = y;
          return settled && $('.sF-modalContainer:visible').last().find('select.sF-breadcrumps option').length > 0;
        }""", polling=200)
        cancel = modal.locator("#sF-cancelButton").bounding_box()
        assert cancel["y"] + cancel["height"] <= height, f"{button}: Cancel is below the window"
        roots = modal.locator("select.sF-breadcrumps").bounding_box()
        refresh = modal.locator("#sF-btn-refresh").bounding_box()
        assert abs(roots["y"] - refresh["y"]) < refresh["height"], f"{button}: the root drop-down is not on the toolbar row"
        modal.locator("#sF-cancelButton").click()
        expect(page.locator(".sF-modalContainer")).to_have_count(0)


def test_a_long_file_name_is_shown_in_full_and_the_pane_scrolls(layout_app: Page):
    # #188: the folder dialog's content pane cut long names off with "...".
    page = layout_app
    if page.url_layout != "long_names":
        pytest.skip("only for the long-names layout")
    page.click("#inside")
    modal = page.locator(".sF-modalContainer").last
    modal.locator(".sF-dirList .sF-directory.root > .sF-file-name").first.click()
    page.wait_for_function(
        "() => $('.sF-modalContainer:visible').last().find('.sF-dirContent > div').length > 1")
    m = page.evaluate("""() => {
      const c = $('.sF-modalContainer:visible').last().find('.sF-dirContent');
      const pane = c.parent()[0];
      const name = c.find('> div > div:nth-child(2) > div').filter(function () {
        return /a_long_file_name_/.test($(this).text()); })[0];
      return { clipped: name.scrollWidth > name.clientWidth + 1,
               scrolls: pane.scrollWidth > pane.clientWidth,
               rowHeight: Math.round(name.closest('.sF-dirContent > div').getBoundingClientRect().height) };
    }""")
    assert not m["clipped"], m
    assert m["scrolls"], m
    assert m["rowHeight"] < 30, m
