# Where a folder chooser opens when defaultRoot and defaultPath are set (#110).
# The dialog opens with the tree expanded down to defaultPath and it selected,
# so a folder picked there is reported under it.

makeDefaultTree <- function() {
  base <- tempfile("sf-dirdefault")
  fs::dir_create(fs::path(base, "a", "b", "c"))
  fs::dir_create(fs::path(base, "other"))
  as.character(fs::path_real(base))
}

test_that("defaultPath opens expanded and selected", {
  withFileDialog(shinyDirChoose, c(x = tempdir(), r = makeDefaultTree()), function(d) {
    d$open()
    l <- d$last()
    expect_equal(l$selectedRoot, "r")
    expect_equal(unlist(l$contentPath), c("", "a", "b"))
    expect_equal(filenames(list(files = l$content)), "c")
    a <- l$tree$children[[which(vapply(l$tree$children, `[[`, "", "name") == "a")]]
    expect_true(a$expanded)
    expect_equal(a$children[[1]]$name, "b")
  }, defaultRoot = "r", defaultPath = "a/b")
})

test_that("defaultPath may use backslashes or a leading slash", {
  for (p in c("a\\b", "/a/b/", "./a/b")) {
    withFileDialog(shinyDirChoose, c(r = makeDefaultTree()), function(d) {
      d$open()
      expect_equal(unlist(d$last()$contentPath), c("", "a", "b"), label = p)
    }, defaultRoot = "r", defaultPath = p)
  }
})

test_that("defaultPath without defaultRoot is taken from the first root", {
  withFileDialog(shinyDirChoose, c(r = makeDefaultTree()), function(d) {
    d$open()
    expect_equal(d$last()$selectedRoot, "r")
    expect_equal(unlist(d$last()$contentPath), c("", "a"))
  }, defaultPath = "a")
})

test_that("a missing or escaping defaultPath opens at the root with nothing selected", {
  for (p in c("nope", "a/nope", "../a", "a/../../x")) {
    withFileDialog(shinyDirChoose, c(r = makeDefaultTree()), function(d) {
      d$open()
      expect_equal(d$last()$selectedRoot, "r", label = p)
      expect_null(d$last()$contentPath, label = p)
    }, defaultRoot = "r", defaultPath = p)
  }
})

test_that("no defaultPath opens at the root with nothing selected, as before", {
  withFileDialog(shinyDirChoose, c(r = makeDefaultTree()), function(d) {
    d$open()
    expect_null(d$last()$contentPath)
    expect_equal(sort(vapply(d$last()$tree$children, `[[`, "", "name")), c("a", "other"))
  })
})

test_that("an unknown defaultRoot opens the first root", {
  withFileDialog(shinyDirChoose, c(r = makeDefaultTree()), function(d) {
    d$open()
    expect_equal(d$last()$selectedRoot, "r")
    expect_null(d$last()$contentPath)
  }, defaultRoot = "missing", defaultPath = "a")
})

test_that("a selection made at defaultPath parses under it", {
  base <- makeDefaultTree()
  roots <- c(r = base)
  withFileDialog(shinyDirChoose, roots, function(d) {
    d$open()
    expect_equal(as.character(parseDirPath(roots, list(root = "r", path = d$last()$contentPath))),
                 file.path(base, "a", "b"))
  }, defaultRoot = "r", defaultPath = "a/b")
})
