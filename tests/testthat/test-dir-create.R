# Creating folders from the folder and save dialogs. A new folder must end up
# directly inside the folder the dialog is showing, within its root; anything
# else is refused without touching the filesystem.

local({
  base <- tempfile("sf-mkdir")
  fs::dir_create(fs::path(base, "root", "sub"))
  fs::file_create(fs::path(base, "root", "afile.txt"))
  mkBase <<- as.character(fs::path_real(base))
})
mkRoot <- file.path(mkBase, "root")
mk <- dirCreator(roots = c(r = mkRoot))

test_that("a new folder is created inside the current folder", {
  expect_true(mk("made", list("", "sub"), "r"))
  expect_true(dir.exists(file.path(mkRoot, "sub", "made")))
  expect_true(mk("top", list(""), "r"))
  expect_true(dir.exists(file.path(mkRoot, "top")))
})

test_that("a name can't place the folder anywhere but the current folder", {
  for (name in c("..", ".", "../out", "a/b", "a\\b", "/abs", "", "  ")) {
    expect_false(mk(name, list(""), "r"), label = name)
  }
  expect_false(dir.exists(file.path(mkBase, "out")))
  expect_false(dir.exists(file.path(mkRoot, "a")))
})

test_that("the folder a name goes into must be inside the root", {
  expect_false(mk("x", list("", ".."), "r"))
  expect_false(mk("x", list("", "sub", "..", ".."), "r"))
  expect_false(dir.exists(file.path(mkBase, "x")))
  # Moving around inside the root is fine.
  expect_true(mk("ok", list("", "sub", "..", "sub"), "r"))
  expect_true(dir.exists(file.path(mkRoot, "sub", "ok")))
})

test_that("a symlink can't take the new folder out of the root", {
  skip_on_os("windows")
  outside <- file.path(mkBase, "outside")
  dir.create(outside)
  file.symlink(outside, file.path(mkRoot, "link"))
  expect_false(mk("x", list("", "link"), "r"))
  expect_false(dir.exists(file.path(outside, "x")))
})

test_that("an existing name, a missing folder or an unknown root is refused", {
  expect_false(mk("sub", list(""), "r"))
  expect_false(mk("afile.txt", list(""), "r"))
  expect_false(mk("x", list("", "nope"), "r"))
  expect_false(mk("x", list(""), "not-a-root"))
  expect_false(mk(NULL, list(""), "r"))
  expect_false(mk(c("a", "b"), list(""), "r"))
})

test_that("a refused request leaves the dialogs working", {
  withFileDialog(shinyFileSave, c(r = mkRoot), function(d) {
    d$open()
    expect_no_error(d$newDir("../escaped"))
    expect_false(dir.exists(file.path(mkBase, "escaped")))
    d$go("sub")
    expect_true(d$last()$exist)
  })
})

test_that("a refusal says why (#17)", {
  expect_null(attr(mk("fresh", list(""), "r"), "reason"))
  expect_equal(attr(mk("sub", list(""), "r"), "reason"), '"sub" already exists.')
  expect_equal(attr(mk("afile.txt", list(""), "r"), "reason"), '"afile.txt" already exists.')
  for (name in c("", "  ", ".", "..", "a/b", "a\\b")) {
    expect_match(attr(mk(name, list(""), "r"), "reason"), "must not be empty", label = name)
  }
  expect_equal(attr(mk("x", list("", "nope"), "r"), "reason"), "The folder could not be created there.")
  expect_equal(attr(mk("x", list(""), "not-a-root"), "reason"), "The folder could not be created there.")
})

test_that("the dialogs show the reason when a folder isn't created (#17)", {
  for (observer in list(shinyFileSave, shinyDirChoose)) {
    withFileDialog(observer, c(r = mkRoot), function(d) {
      d$open()
      d$newDir("sub", root = "r")
      notes <- d$notifications()
      expect_length(notes, 1)
      expect_match(notes[[1]]$text, '"sub" already exists.', fixed = TRUE)
      expect_equal(notes[[1]]$type, "error")

      d$newDir("../out", root = "r")
      expect_length(d$notifications(), 2)
      expect_match(d$notifications()[[2]]$text, "must not be empty")
    })
  }
})

test_that("a created folder shows no notification", {
  for (observer in list(shinyFileSave, shinyDirChoose)) {
    withFileDialog(observer, c(r = mkRoot), function(d) {
      d$open()
      # The folder dialog names its root as selectedRoot, not root, so pass it.
      d$newDir(basename(tempfile("made")), root = "r")
      expect_length(d$notifications(), 0)
    })
  }
})
