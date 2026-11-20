"""Type to jump (#99): typing letters in a dialog selects the first entry whose
name starts with them, like File Explorer and Finder. Letters typed within a
moment of each other build one prefix; typing the same letter again moves to
the next entry that starts with it."""

from __future__ import annotations

from playwright.sync_api import Page, expect

from helpers import Dialog


def typed(d: Dialog, text: str, pause: int = 0) -> None:
    for ch in text:
        d.page.keyboard.press(ch)
        if pause:
            d.page.wait_for_timeout(pause)


def test_typing_selects_the_first_entry_with_that_start(app: Page):
    # data holds a.txt, b.csv, c.R, empty/, folder/, locked/.
    d = Dialog(app, "file").open()
    typed(d, "f")
    assert d.selected_rows() == ["folder"]
    # Selecting a file enables Select, as clicking it does.
    typed(d, "a")
    app.wait_for_timeout(1200)
    typed(d, "a")
    assert d.selected_rows() == ["a.txt"]
    expect(d.find("#sF-selectButton")).to_be_enabled()


def test_letters_typed_together_build_one_prefix(app: Page):
    d = Dialog(app, "file").open()
    typed(d, "lo")
    assert d.selected_rows() == ["locked"]


def test_matching_ignores_case(app: Page):
    d = Dialog(app, "file").open()
    typed(d, "C")
    assert d.selected_rows() == ["c.R"]


def test_the_same_letter_again_moves_to_the_next_match(app: Page):
    d = Dialog(app, "file").open()
    typed(d, "e")
    assert d.selected_rows() == ["empty"]
    typed(d, "f")
    app.wait_for_timeout(1200)
    # A pause starts a new search.
    typed(d, "c")
    assert d.selected_rows() == ["c.R"]


def test_repeating_a_letter_cycles_through_its_matches(app: Page):
    d = Dialog(app, "file").open()
    d.after_listing(lambda: d.dblclick_row("folder"))
    # folder/ holds sub/ and f01.txt ... f12.txt.
    typed(d, "f")
    first = d.selected_rows()
    typed(d, "f")
    second = d.selected_rows()
    assert first != second and all(r[0].startswith("f") for r in [first, second])


def test_no_match_keeps_the_selection(app: Page):
    d = Dialog(app, "file").open()
    typed(d, "b")
    typed(d, "z")
    assert d.selected_rows() == ["b.csv"]


def test_enter_after_typing_opens_the_folder(app: Page):
    d = Dialog(app, "file").open()
    typed(d, "fo")
    d.after_listing(lambda: app.keyboard.press("Enter"))
    assert d.location() == ["", "folder"]


def test_typing_in_the_save_dialog_filename_box_is_not_hijacked(app: Page):
    d = Dialog(app, "save").open()
    box = d.find("input.sF-filename")
    box.fill("")
    box.press_sequentially("folder")
    expect(box).to_have_value("folder")
    assert d.selected_rows() == []


def test_typing_in_the_path_box_is_not_hijacked(app: Page):
    d = Dialog(app, "file").open()
    d.find("#sF-btn-textChoice").click()
    box = d.find(".sF-textChoice input")
    box.press_sequentially("/x")
    assert box.input_value().endswith("/x")
    assert d.selected_rows() == []


def test_typing_in_the_folder_dialog_selects_in_the_tree(app: Page):
    d = Dialog(app, "dir").open()
    d.highlight_root()
    d.after_listing(lambda: typed(d, "fo"))
    expect(d.find(".sF-dirList .selected > .sF-file-name")).to_have_text("folder")
    # The selection is sent to the server like a click, so its content shows.
    expect(d.find(".sF-dirContent")).to_contain_text("sub")


def test_shortcut_keys_still_reach_the_page(app: Page):
    # Ctrl/Cmd combinations aren't treated as typing.
    d = Dialog(app, "file").open()
    d.click_row("b.csv")
    app.keyboard.press("ControlOrMeta+a")
    assert d.selected_rows() == ["b.csv"]


def test_typing_selects_only_one_entry_in_a_multiple_dialog(app: Page):
    d = Dialog(app, "file").open()
    d.click_row("a.txt")
    typed(d, "c")
    assert d.selected_rows() == ["c.R"]
