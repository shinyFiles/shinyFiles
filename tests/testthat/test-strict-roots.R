# strictRoots = TRUE makes a root a hard boundary: a symlink inside it that
# leads out is left out of listings and can't be opened or chosen. The default
# keeps following symlinks wherever they lead.

skip_on_os("windows") # symlinks

local({
  base <- tempfile("sf-strict")
  fs::dir_create(fs::path(base, "root", "inside", "deep"))
  fs::file_create(fs::path(base, "root", "inside", "a.txt"))
  fs::dir_create(fs::path(base, "outside", "secret"))
  fs::file_create(fs::path(base, "outside", "secret.txt"))
  root <- fs::path(base, "root")
  fs::link_create(fs::path(base, "outside"), fs::path(root, "outLink"))
  fs::link_create(fs::path(base, "outside", "secret.txt"), fs::path(root, "outFile"))
  fs::link_create(fs::path(root, "inside"), fs::path(root, "inLink"))
  fs::link_create(fs::path(root, "inside", "a.txt"), fs::path(root, "inFile"))
  fs::link_create(fs::path(base, "gone"), fs::path(root, "broken"))
  # deep/ holds nothing but a way out.
  fs::link_create(fs::path(base, "outside"), fs::path(root, "inside", "deep", "escape"))
  strictBase <<- as.character(fs::path_real(base))
})
strictRoot <- file.path(strictBase, "root")
roots <- c(r = strictRoot)

names_in <- function(listing) sort(listing$files$filename)
tree_names <- function(x) sort(vapply(x$tree$children, `[[`, "", "name"))

test_that("by default symlinks out of the root are listed and followed", {
  g <- fileGetter(roots = roots)
  expect_true(all(c("outLink", "outFile", "inLink", "inFile") %in% names_in(g("", "r"))))
  expect_equal(names_in(g("outLink", "r")), c("secret", "secret.txt"))
  expect_true("outLink" %in% tree_names(dirGetter(roots = roots)(list(name = "", expanded = TRUE), "r")))
})

test_that("strictRoots leaves links out of the root out of the file listing", {
  g <- fileGetter(roots = roots, strictRoots = TRUE)
  listed <- names_in(g("", "r"))
  expect_false(any(c("outLink", "outFile") %in% listed))
  # Links that stay inside, and broken ones, are still shown.
  expect_true(all(c("inLink", "inFile", "inside", "broken") %in% listed))
})

test_that("strictRoots won't open a folder reached through an escaping link", {
  g <- fileGetter(roots = roots, strictRoots = TRUE)
  x <- g("outLink", "r")
  expect_equal(x$breadcrumps, I(""))
  expect_true("inside" %in% names_in(x))
  expect_equal(names_in(g("inLink", "r")), c("a.txt", "deep"))
})

test_that("strictRoots leaves escaping links out of the folder tree", {
  d <- dirGetter(roots = roots, strictRoots = TRUE)
  expect_equal(tree_names(d(list(name = "", expanded = TRUE), "r")), c("inLink", "inside"))
  # A tree the browser sends starting at the link starts at the root instead.
  expect_equal(d(list(name = "outLink", expanded = TRUE), "r")$tree$name, "")
})

test_that("strictRoots keeps the background prober inside the root", {
  deep <- file.path(strictRoot, "inside", "deep")
  # Its only entry leads out, so it has no arrow when the root is a boundary.
  expect_true(dirProber(roots = roots, strictRoots = TRUE)$probe(deep, listingCache(), strictRoot))
  expect_false(dirProber(roots = roots)$probe(deep, listingCache(), strictRoot))
  expect_false(dirProber(roots = roots, strictRoots = TRUE)$probe(file.path(strictRoot, "inside"), listingCache(), strictRoot))
})

test_that("parse functions with strictRoots reject a choice made through an escaping link", {
  sel <- list(root = "r", files = list(list("", "outLink", "secret.txt")))
  expect_equal(nrow(parseFilePaths(roots, sel)), 1)
  expect_equal(nrow(parseFilePaths(roots, sel, strictRoots = TRUE)), 0)
  ok <- list(root = "r", files = list(list("", "inLink", "a.txt")))
  expect_equal(nrow(parseFilePaths(roots, ok, strictRoots = TRUE)), 1)

  dsel <- list(root = "r", path = list("", "outLink", "secret"))
  expect_equal(as.character(parseDirPath(roots, dsel)), file.path(strictRoot, "outLink", "secret"))
  expect_equal(parseDirPath(roots, dsel, strictRoots = TRUE), character(0))

  ssel <- list(root = "r", path = list("", "outLink"), name = "new.csv", type = "")
  expect_equal(nrow(parseSavePath(roots, ssel)), 1)
  expect_equal(nrow(parseSavePath(roots, ssel, strictRoots = TRUE)), 0)
  # A file that doesn't exist yet, in a real folder inside the root, is fine.
  ssel$path <- list("", "inside")
  expect_equal(nrow(parseSavePath(roots, ssel, strictRoots = TRUE)), 1)
})

test_that("strictRoots passes through the dialog observers", {
  withFileDialog(shinyFileChoose, roots, function(d) {
    d$open()
    expect_false("outLink" %in% filenames(d$last()))
    d$go("outLink")
    expect_equal(crumbs(d$last()), "")
  }, strictRoots = TRUE)

  withFileDialog(shinyFileSave, roots, function(d) {
    d$open()
    expect_false("outLink" %in% filenames(d$last()))
  }, strictRoots = TRUE)

  withFileDialog(shinyDirChoose, roots, function(d) {
    d$open()
    expect_equal(tree_names(d$last()), c("inLink", "inside"))
  }, strictRoots = TRUE)
})

test_that("the observers still follow links by default", {
  withFileDialog(shinyFileChoose, roots, function(d) {
    d$open()
    d$go("outLink")
    expect_equal(crumbs(d$last()), c("", "outLink"))
  })
})
