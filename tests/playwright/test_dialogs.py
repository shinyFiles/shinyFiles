"""Dialog behaviour that needs more than one catalogue action: sizes and
history, the loading overlay, recent folders across reloads, and what the
browser shows for each file."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from playwright.sync_api import Page, expect

from helpers import Dialog


def test_file_sizes_are_shown_in_si_units(app: Page, fixture_dir: Path):
    big = fixture_dir / "data" / "big.bin"
    big.write_bytes(b"x" * 1_500_000)
    try:
        d = Dialog(app, "file").open()
        d.after_listing(lambda: d.find("#sF-btn-refresh").click())
        size = d.find(".sF-fileList .sF-file").filter(has_text="big.bin").locator(".sF-file-size")
        expect(size).to_have_text("1.5 MB")
        expect(d.find(".sF-fileList .sF-file").filter(has_text="b.csv").locator(".sF-file-size")).to_have_text(
            re.compile(r"^\d+ B$")
        )
    finally:
        big.unlink()


def test_folders_have_no_size(app: Page):
    d = Dialog(app, "file").open()
    expect(d.find(".sF-fileList .sF-directory").filter(has_text="folder").locator(".sF-file-size")).to_have_text("")


def test_history_survives_closing_and_reopening(app: Page):
    d = Dialog(app, "file").open()
    d.after_listing(lambda: d.dblclick_row("folder"))
    d.after_listing(lambda: d.find("#sF-btn-up").click())
    d.find("#sF-cancelButton").click()
    d.expect_closed()
    d.open()
    expect(d.find("#sF-btn-back")).to_be_enabled()
    d.after_listing(lambda: d.find("#sF-btn-back").click())
    assert d.location() == ["", "folder"]


def test_view_and_sort_survive_closing_and_reopening(app: Page):
    d = Dialog(app, "file").open()
    d.find("#sF-btn-list").click()
    d.find("#sF-btn-sort").click()
    d.find(".sF-sort li.sortAttr").filter(has_text="Size").click()
    d.find("#sF-cancelButton").click()
    d.expect_closed()
    d.open()
    expect(d.find(".sF-fileList")).to_have_class(re.compile("sF-list"))
    expect(d.find(".sF-sort li.sortAttr.selected")).to_have_text("Size")


def test_a_navigation_clears_forward_history(app: Page):
    d = Dialog(app, "file").open()
    d.after_listing(lambda: d.dblclick_row("folder"))
    d.after_listing(lambda: d.find("#sF-btn-back").click())
    expect(d.find("#sF-btn-forward")).to_be_enabled()
    d.after_listing(lambda: d.dblclick_row("empty"))
    expect(d.find("#sF-btn-forward")).to_be_disabled()


def test_selection_is_remembered_as_a_recent_folder(app: Page):
    d = Dialog(app, "file").open()
    d.after_listing(lambda: d.dblclick_row("folder"))
    d.click_row("f01.txt")
    d.find("#sF-selectButton").click()
    d.expect_closed()
    stored = app.evaluate("() => JSON.parse(localStorage.getItem('shinyFiles-recent:' + location.pathname))")
    assert stored == [{"root": "data", "path": ["folder"]}]
    # Survives a reload, and shows in a different dialog with the same roots.
    app.reload()
    app.wait_for_selector("button#save.shiny-bound-input")
    s = Dialog(app, "save").open()
    expect(s.find("select.sF-breadcrumps optgroup.sF-recent option")).to_have_text(["data/folder"])


def test_corrupt_recent_storage_is_ignored(app: Page):
    app.evaluate("() => localStorage.setItem('shinyFiles-recent:' + location.pathname, '{not json')")
    d = Dialog(app, "file").open()
    expect(d.find("select.sF-breadcrumps optgroup.sF-recent")).to_have_count(0)
    d.click_row("a.txt")
    d.find("#sF-selectButton").click()
    d.expect_closed()
    stored = app.evaluate("() => JSON.parse(localStorage.getItem('shinyFiles-recent:' + location.pathname))")
    assert stored == [{"root": "data", "path": []}]


def test_a_fast_listing_never_flashes_the_overlay(app: Page):
    Dialog(app, "file").open()
    result = app.evaluate("""() => new Promise(function(resolve) {
      var m = $('#file').data('modal');
      var shown = false;
      var timer = setInterval(function(){
        if (m.find('.sF-loading').length) shown = true;
      }, 20);
      // Navigating starts the overlay timer; a local listing lands well
      // under its 250 ms delay, so the overlay must never appear.
      m.find('.sF-fileList .sF-directory').filter(function(){
        return $(this).text().indexOf('folder') !== -1; }).trigger('dblclick');
      setTimeout(function(){ clearInterval(timer); resolve({shown: shown,
        gone: m.find('.sF-loading').length === 0}); }, 1000);
    })""")
    assert result["gone"]
    assert not result["shown"]


def test_every_file_row_carries_its_metadata(app: Page):
    d = Dialog(app, "file").open()
    info = d.js("""return m.find('.sF-fileList > .sF-file').map(function(){
        var f = $(this).data('sF-file');
        return {name: f.name, ext: f.extension, isDir: f.isDir, hasTimes: !!(f.mTime && f.cTime)};
      }).toArray();""")
    by_name = {x["name"]: x for x in info}
    assert by_name["a.txt"]["ext"] == "txt"
    assert by_name["c.R"]["ext"] == "r"
    assert all(x["hasTimes"] and not x["isDir"] for x in info)


def test_only_the_save_dialog_warns_about_a_read_only_folder(app: Page):
    d = Dialog(app, "file").open()
    d.after_listing(lambda: d.dblclick_row("locked"))
    expect(d.find(".sF-warning")).to_have_count(0)
    d.find("#sF-cancelButton").click()
    d.expect_closed()
    t = Dialog(app, "dir").open()
    t.highlight("locked")
    expect(t.find(".sF-warning")).to_have_count(0)
    expect(t.find("#sF-btn-newDir")).to_be_disabled()
    expect(t.find("#sF-selectButton")).to_be_enabled()


def test_a_missing_folder_wins_over_the_permission_warning(app: Page):
    d = Dialog(app, "save").open()
    d.find("#sF-btn-textChoice").click()
    box = d.find(".sF-textChoice input")
    box.fill("/no/such/place")
    d.after_listing(lambda: box.press("Enter"))
    expect(d.find(".sF-warning")).to_have_count(1)
    expect(d.find(".sF-warning")).to_contain_text("does not exist")


def test_the_chosen_sort_order_is_kept_when_navigating(app: Page):
    d = Dialog(app, "file").open()
    d.find("#sF-btn-sort").click()
    d.find(".sF-sort li.sortAttr").filter(has_text="Size").click()
    by_size = d.row_names(".sF-fileList > .sF-file")
    assert by_size == ["b.csv", "c.R", "a.txt"]
    d.after_listing(lambda: d.dblclick_row("folder"))
    d.after_listing(lambda: d.find("#sF-btn-up").click())
    expect(d.find(".sF-sort li.sortAttr.selected")).to_have_text("Size")
    assert d.row_names(".sF-fileList > .sF-file") == by_size


def test_the_chosen_sort_order_is_kept_when_reopening(app: Page):
    d = Dialog(app, "save").open()
    d.find("#sF-btn-sort").click()
    d.find(".sF-sort li.sortDir a").click()
    assert d.row_names(".sF-fileList > .sF-file") == ["c.R", "b.csv", "a.txt"]
    d.find("#sF-cancelButton").click()
    d.expect_closed()
    d.open()
    expect(d.find(".sF-sort li.sortDir a")).to_have_class(re.compile("descending"))
    assert d.row_names(".sF-fileList > .sF-file") == ["c.R", "b.csv", "a.txt"]


def test_the_folder_dialog_keeps_its_sort_order_when_highlighting(app: Page):
    d = Dialog(app, "dir").open()
    d.highlight_root()
    d.find("#sF-btn-sort").click()
    d.find(".sF-sort li.sortDir a").click()
    names = lambda: d.js("return m.find('.sF-dirContent > div').map(function(){ return $(this).find('.sF-file-name').text().trim(); }).toArray();")
    first = names()
    d.highlight("folder")
    d.highlight_root()
    assert names() == first


@pytest.mark.parametrize("attr", ["Name", "Type", "Size", "Created", "Modified"])
def test_the_column_header_stays_on_top_in_every_sort_order(app: Page, attr):
    d = Dialog(app, "file").open()
    for direction in ("ascending", "descending"):
        d.find("#sF-btn-sort").click()
        d.find(".sF-sort li.sortAttr").filter(has_text=attr).click()
        current = d.js("return m.find('.sF-sort li.sortDir a').attr('class');")
        if current != direction:
            d.find("#sF-btn-sort").click()
            d.find(".sF-sort li.sortDir a").click()
        first = d.js("return m.find('.sF-fileList').children().first().attr('class');")
        assert first == "sF-file-header", f"{attr} {direction}: header is not the first row"


def test_new_folder_is_grayed_out_when_creating_folders_is_disabled(app: Page):
    d = Dialog(app, "dirNoCreate").open()
    d.highlight_root()
    expect(d.find("#sF-btn-newDir")).to_be_disabled()
    # It stays disabled after the next listing, too.
    d.highlight("folder")
    expect(d.find("#sF-btn-newDir")).to_be_disabled()


def test_new_folder_is_available_by_default(app: Page):
    d = Dialog(app, "dir").open()
    d.highlight_root()
    expect(d.find("#sF-btn-newDir")).to_be_enabled()
    s = Dialog(app, "save")
    d.find("#sF-cancelButton").click()
    d.expect_closed()
    s.open()
    expect(s.find("#sF-btn-newDir")).to_be_enabled()


def test_clicking_save_is_not_cancelled_by_relabelling_the_button(app: Page):
    # Moving focus from the filename box to Save re-evaluates the filename on
    # mousedown. If that replaces the button's text node, WebKit (Safari) drops
    # the click. The label may only be rewritten when it actually changes.
    d = Dialog(app, "save").open()
    d.find("input.sF-filename").fill("newname")
    replaced = app.evaluate("""() => new Promise(function(resolve) {
      var btn = $('#save').data('modal').find('#sF-selectButton')[0];
      var changed = false;
      new MutationObserver(function(){ changed = true; }).observe(btn, {childList: true, characterData: true, subtree: true});
      // What a mousedown on Save does first: the filename box loses focus.
      btn.dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
      $('#save').data('modal').find('.sF-filename').trigger('blur');
      $('#save').data('modal').trigger('change');
      setTimeout(function(){ resolve(changed); }, 50);
    })""")
    assert not replaced, "the Save button's label was rewritten without changing"
    d.find("#sF-selectButton").click()
    d.expect_closed()


@pytest.mark.parametrize("name", ["a/b", "../escape", ".."])
def test_a_refused_new_folder_keeps_the_save_dialog_usable(app: Page, fixture_dir: Path, name):
    # The save dialog used to open a folder named after whatever was typed, so a
    # refused name left it showing an empty, missing folder with the
    # new-folder button grayed out. It now stays put and says why.
    d = Dialog(app, "save").open()
    d.find("#sF-btn-newDir").click()
    # Typed, not filled: the + button is enabled on keyup.
    d.find(".sF-newDir input").press_sequentially(name)
    d.find(".sF-newDir ul button").click()
    expect(app.locator(".shiny-notification-error")).to_be_visible()
    assert d.location() == [""]
    expect(d.find(".sF-fileList")).to_contain_text("folder")
    expect(d.find("#sF-btn-newDir")).to_be_enabled()
    assert not (fixture_dir / "escape").exists()


def test_an_existing_folder_name_opens_that_folder_and_says_it_exists(app: Page):
    d = Dialog(app, "save").open()
    d.find("#sF-btn-newDir").click()
    d.find(".sF-newDir input").press_sequentially("folder")
    d.after_listing(lambda: d.find(".sF-newDir ul button").click())
    expect(app.locator(".shiny-notification-error")).to_contain_text('"folder" already exists.')
    assert d.location() == ["", "folder"]



def _pick(app: Page, steps):
    d = Dialog(app, "file").open()
    # The outputs keep the last choice, so wait for these to change.
    before = app.evaluate("() => [$('#fileOut').text(), $('#filePicked').text()]")
    for name, mods in steps:
        d.click_row(name, mods)
    d.find("#sF-selectButton").click()
    d.expect_closed()
    # The outputs are redrawn by the server after the dialog closes.
    app.wait_for_function(
        "b => { var o = $('#fileOut').text(), p = $('#filePicked').text();"
        " return o !== '' && p !== '' && (o !== b[0] || p !== b[1]) && !$('html').hasClass('shiny-busy'); }",
        arg=before,
    )
    listing = [p.rsplit("/", 1)[-1] for p in app.locator("#fileOut").inner_text().split("|")]
    picked = app.locator("#filePicked").inner_text().split("|")
    return listing, picked


def test_files_come_back_in_the_order_they_were_picked_when_asked(app: Page):
    # Listed a.txt, b.csv, c.R; picked c.R, then a.txt, then b.csv (#178).
    listing, picked = _pick(app, [("c.R", None), ("a.txt", ["ControlOrMeta"]), ("b.csv", ["ControlOrMeta"])])
    assert listing == ["a.txt", "b.csv", "c.R"]
    assert picked == ["c.R", "a.txt", "b.csv"]


def test_a_shift_range_counts_from_where_it_started(app: Page):
    # From c.R up to a.txt: picked c.R, b.csv, a.txt.
    _, up = _pick(app, [("c.R", None), ("a.txt", ["Shift"])])
    assert up == ["c.R", "b.csv", "a.txt"]
    _, down = _pick(app, [("a.txt", None), ("c.R", ["Shift"])])
    assert down == ["a.txt", "b.csv", "c.R"]


def test_deselecting_and_reselecting_moves_a_file_to_the_end(app: Page):
    _, picked = _pick(app, [("a.txt", None), ("b.csv", ["ControlOrMeta"]), ("a.txt", ["ControlOrMeta"]),
                            ("c.R", ["ControlOrMeta"]), ("a.txt", ["ControlOrMeta"])])
    assert picked == ["b.csv", "c.R", "a.txt"]



def test_an_unknown_creation_time_is_left_blank(app: Page):
    # Some filesystems (NFS among them) record no creation time; fs reports it
    # as 0, which used to be shown as Dec 31, 1969 or Jan 1, 1970. Where the
    # filesystem does record it, it must still be shown.
    d = Dialog(app, "file").open()
    rows = d.js("""return m.find('.sF-fileList .sF-file').map(function () {
      return [[$(this).data('sF-file').cTime.getTime(), $(this).find('.sF-file-cTime').text(),
               $(this).find('.sF-file-mTime').text()]]; }).toArray();""")
    assert rows, rows
    for when, created, modified in rows:
        assert modified != ""
        if when == 0:
            assert created == "", (when, created)
        else:
            assert created != "" and "1969" not in created and "1970" not in created, (when, created)
