# Unit tests for parseFilePaths(), parseDirPath() and parseSavePath(), which turn
# the value a dialog sends back into paths. An integer value is the click count
# Shiny's action button sends before anything has been chosen.

roots <- local({
  base <- tempfile("sf-parse")
  fs::dir_create(fs::path(base, "a", "sub"))
  fs::dir_create(fs::path(base, "b"))
  base <- fs::path_real(base)
  writeLines("hello", fs::path(base, "a", "one.txt"))
  writeLines(strrep("x", 100), fs::path(base, "a", "sub", "two.csv"))
  c(first = as.character(fs::path(base, "a")), second = as.character(fs::path(base, "b")))
})

emptyFiles <- tibble::tibble(
  name = character(0), size = numeric(0), type = character(0), datapath = character(0)
)
emptySave <- tibble::tibble(name = character(0), type = character(0), datapath = character(0))

test_that("the parsers return exactly the fileInput() columns", {
  expect_named(parseFilePaths(roots, NULL), c("name", "size", "type", "datapath"))
  expect_named(parseSavePath(roots, NULL), c("name", "type", "datapath"))
  expect_named(parseSavePath(roots, 1L), c("name", "type", "datapath"))
  expect_named(parseSavePath(roots, list(name = "x", path = list(""), root = "first")),
               c("name", "type", "datapath"))
})

test_that("parseFilePaths returns an empty table until a file is chosen", {
  expect_equal((parseFilePaths(roots, NULL)), emptyFiles, ignore_attr = TRUE)
  expect_equal((parseFilePaths(roots, NA)), emptyFiles, ignore_attr = TRUE)
  expect_equal((parseFilePaths(roots, 1L)), emptyFiles, ignore_attr = TRUE)
  expect_equal((parseFilePaths(roots, list(files = list(), root = "first"))), emptyFiles,
               ignore_attr = TRUE)
})

test_that("parseFilePaths resolves one and several files with their sizes", {
  one <- parseFilePaths(roots, list(files = list("0" = list("", "one.txt")), root = "first"))
  expect_equal(one$name, "one.txt")
  expect_equal(as.character(one$datapath), file.path(roots[["first"]], "one.txt"))
  expect_equal(one$size, file.size(file.path(roots[["first"]], "one.txt")))
  expect_equal(one$type, "")

  two <- parseFilePaths(roots, list(
    files = list("0" = list("", "one.txt"), "1" = list("", "sub", "two.csv")),
    root = "first"
  ))
  expect_equal(two$name, c("one.txt", "two.csv"))
  expect_equal(as.character(two$datapath),
               file.path(roots[["first"]], c("one.txt", "sub/two.csv")))
  # Compared against the file, not a fixed number: writeLines() ends lines with
  # \r\n on Windows.
  expect_equal(two$size[2], file.size(file.path(roots[["first"]], "sub", "two.csv")))
  expect_gt(two$size[2], two$size[1])
})

test_that("parseFilePaths accepts roots as a function", {
  x <- parseFilePaths(function() roots, list(files = list("0" = list("", "one.txt")), root = "first"))
  expect_equal(x$name, "one.txt")
})

test_that("parseDirPath resolves a folder in the chosen root", {
  expect_equal(parseDirPath(roots, 3L), character(0))
  expect_equal(as.character(parseDirPath(roots, list(path = list("", "sub"), root = "first"))),
               file.path(roots[["first"]], "sub"))
  expect_equal(as.character(parseDirPath(roots, list(path = list(""), root = "second"))),
               roots[["second"]])
  expect_equal(as.character(parseDirPath(function() roots, list(path = list("", "sub"), root = "first"))),
               file.path(roots[["first"]], "sub"))
})

test_that("parseDirPath and parseSavePath reject unnamed roots", {
  expect_error(parseDirPath(unname(roots), list(path = list(""), root = "first")), "named vector")
  expect_error(parseSavePath(unname(roots), list(name = "x", path = list(""), root = "first")),
               "named vector")
})

test_that("parseSavePath returns an empty table until a file is saved", {
  expect_equal((parseSavePath(roots, NULL)), emptySave, ignore_attr = TRUE)
  expect_equal((parseSavePath(roots, 2L)), emptySave, ignore_attr = TRUE)
})

test_that("parseSavePath builds the path from root, folder and name", {
  x <- parseSavePath(roots, list(name = "out.txt", type = list("text"), path = list("", "sub"), root = "first"))
  expect_equal(x$name, "out.txt")
  expect_equal(x$type, "text")
  expect_equal(as.character(x$datapath), file.path(roots[["first"]], "sub", "out.txt"))

  # A save without a file type picker sends an empty type.
  y <- parseSavePath(roots, list(name = "out", type = list(), path = list(""), root = "second"))
  expect_equal(y$type, "")
  expect_equal(as.character(y$datapath), file.path(roots[["second"]], "out"))

  z <- parseSavePath(function() roots, list(name = "out", path = list(""), root = "first"))
  expect_equal(z$type, "")
})

# A selection names a location inside a root. One that resolves outside it is
# treated as nothing chosen, so an app never gets a path it didn't offer.
test_that("a selection outside its root counts as nothing chosen", {
  fs::dir_create(fs::path(dirname(roots[["first"]]), "beside"))
  out <- list("", "..", "beside")
  expect_equal(nrow(parseFilePaths(roots, list(files = list("0" = c(out, "f.txt")), root = "first"))), 0)
  expect_equal(parseDirPath(roots, list(path = out, root = "first")), character(0))
  expect_equal(nrow(parseSavePath(roots, list(name = "f.txt", path = out, root = "first"))), 0)
  # A name can't step out either.
  expect_equal(nrow(parseSavePath(roots, list(name = "../f.txt", path = list(""), root = "first"))), 0)
  # An unknown root is nothing chosen, not a path under NA.
  expect_equal(parseDirPath(roots, list(path = list(""), root = "nope")), character(0))
  expect_equal(nrow(parseFilePaths(roots, list(files = list("0" = list("", "one.txt")), root = "nope"))), 0)
})

test_that("only the files inside the root are kept from a mixed selection", {
  x <- parseFilePaths(roots, list(
    files = list("0" = list("", "one.txt"), "1" = list("", "..", "b", "x.txt")),
    root = "first"
  ))
  expect_equal(x$name, "one.txt")
})

test_that("a selection may move around inside the root", {
  x <- parseDirPath(roots, list(path = list("", "sub", "..", "sub"), root = "first"))
  expect_equal(as.character(x), file.path(roots[["first"]], "sub"))
  y <- parseSavePath(roots, list(name = "new.txt", path = list("", "sub", ".."), root = "first"))
  expect_equal(as.character(y$datapath), file.path(roots[["first"]], "new.txt"))
})

test_that("order = 'selection' returns files in the order they were picked (#178)", {
  base <- tempfile("sf-order")
  dir.create(base)
  file.create(file.path(base, c("a.txt", "b.txt", "c.txt")))
  roots <- c(r = base)
  sel <- list(root = "r", files = list(list("", "a.txt"), list("", "b.txt"), list("", "c.txt")),
              picked = list(3, 1, 2))
  expect_equal(parseFilePaths(roots, sel)$name, c("a.txt", "b.txt", "c.txt"))
  expect_equal(parseFilePaths(roots, sel, order = "selection")$name, c("b.txt", "c.txt", "a.txt"))
  # The listing order stays the default.
  expect_equal(parseFilePaths(roots, sel, order = "listing")$name, c("a.txt", "b.txt", "c.txt"))
  expect_error(parseFilePaths(roots, sel, order = "clicks"), "should be one of")
})

test_that("order = 'selection' falls back to the listing order without timings", {
  base <- tempfile("sf-order2")
  dir.create(base)
  file.create(file.path(base, c("a.txt", "b.txt")))
  roots <- c(r = base)
  sel <- list(root = "r", files = list(list("", "a.txt"), list("", "b.txt")))
  # An input recorded before 1.0.0, or by a page with an older script.
  expect_equal(parseFilePaths(roots, sel, order = "selection")$name, c("a.txt", "b.txt"))
  sel$picked <- list(2)
  expect_equal(parseFilePaths(roots, sel, order = "selection")$name, c("a.txt", "b.txt"))
  # Files outside the root are still dropped, whatever the order.
  sel <- list(root = "r", files = list(list("", "..", "x"), list("", "b.txt")), picked = list(1, 2))
  expect_equal(parseFilePaths(roots, sel, order = "selection")$name, "b.txt")
})

test_that("datapath is a plain character vector, as from fileInput()", {
  # 0.9.4 returned character here, and packages compare it with identical().
  base <- tempfile("sf-chr")
  dir.create(base)
  file.create(file.path(base, c("a.txt", "b.txt")))
  roots <- c(r = base)
  sel <- list(root = "r", files = list(list("", "a.txt"), list("", "b.txt")))
  p <- parseFilePaths(roots, sel)
  expect_identical(class(p$datapath), "character")
  expect_identical(p$datapath, file.path(normalizePath(base, winslash = "/"), c("a.txt", "b.txt")))
  expect_identical(class(parseFilePaths(roots, sel, order = "selection")$datapath), "character")
  expect_identical(class(parseFilePaths(roots, list(root = "r", files = list()))$datapath), "character")
})
