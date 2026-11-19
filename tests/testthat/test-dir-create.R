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

test_that("the folder tree can't start above its root", {
  g <- dirGetter(roots = c(r = mkRoot))
  for (name in c("..", "../..", "sub/../..", "/")) {
    x <- g(list(name = name, expanded = TRUE), "r")
    expect_equal(x$tree$name, if (name == "/") "/" else "", label = name)
    expect_true("sub" %in% vapply(x$tree$children, `[[`, "", "name"), label = name)
  }
  expect_equal(g(list(name = "sub", expanded = TRUE), "r")$tree$name, "sub")
})

# #169: an app that sets the dialog up inside a reactive registers it again
# every time the reactive re-runs, so each request reaches several copies.
twiceServer <- function(observer, roots) {
  function(input, output, session) {
    sent <- reactiveVal(0)
    observeEvent(input$`f-newDir`, sent(sent() + 1), ignoreInit = TRUE)
    observe({
      sent()
      observer(input, "f", roots = roots, session = session)
    })
  }
}

test_that("a dialog set up twice handles each new-folder request once (#169)", {
  for (observer in list(shinyDirChoose, shinyFileSave)) {
    base <- tempfile("sf-twice")
    dir.create(file.path(base, "r"), recursive = TRUE)
    roots <- c(r = file.path(base, "r"))
    notes <- list()
    local_mocked_bindings(
      showNotification = function(ui, ..., type = "default") {
        notes[[length(notes) + 1]] <<- as.character(ui)
        invisible(NULL)
      },
      .package = "shiny"
    )
    testServer(twiceServer(observer, roots), {
      session$setInputs(f = 1)
      for (name in c("first", "second")) {
        session$setInputs(`f-newDir` = list(name = name, path = list(""), root = "r", id = runif(1)))
        session$flushReact()
      }
    })
    expect_true(dir.exists(file.path(base, "r", "first")))
    expect_true(dir.exists(file.path(base, "r", "second")))
    expect_length(notes, 0)
  }
})

test_that("a repeated request id is still ignored, and a new one handled", {
  base <- tempfile("sf-repeat")
  dir.create(file.path(base, "r"), recursive = TRUE)
  withFileDialog(shinyDirChoose, c(r = file.path(base, "r")), function(d) {
    d$open()
    req <- list(name = "again", path = list(""), root = "r", id = 42)
    d$session$setInputs(`f-newDir` = req)
    unlink(file.path(base, "r", "again"), recursive = TRUE)
    # Any later request re-runs the observer with the same newDir input.
    d$refresh()
    expect_false(dir.exists(file.path(base, "r", "again")))
    d$session$setInputs(`f-newDir` = modifyList(req, list(id = 43)))
    expect_true(dir.exists(file.path(base, "r", "again")))
    expect_length(d$notifications(), 0)
  })
})
