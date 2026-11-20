# End-to-end tests for the example apps in inst/examples: each is run as
# shipped and checked to do what its page says.

library(shinytest2)

exampleDir <- function(name) {
  dir <- system.file("examples", name, package = "shinyFiles")
  skip_if(!nzchar(dir), paste("example", name, "not found"))
  dir
}

# The examples call library(shinyFiles), or load the checkout they sit in.
# Copy one into a temp folder with a line that loads this copy of shinyFiles,
# so the test exercises the code under test.
localExample <- function(name, roots = NULL) {
  src <- exampleDir(name)
  dir <- tempfile(paste0("sf-example-", name))
  dir.create(dir)
  file.copy(list.files(src, full.names = TRUE, all.files = FALSE), dir, recursive = TRUE)
  for (f in list.files(dir, pattern = "\\.R$", full.names = TRUE)) {
    code <- readLines(f)
    code <- sub("^library\\(shinyFiles\\)$", shinyFilesLoadLine(), code)
    code <- sub('^if \\(dir.exists\\("../../../R"\\) && file.exists\\("../../../DESCRIPTION"\\)\\) \\{$', "if (FALSE) {", code)
    code <- sub("^  library\\(shinyFiles\\)$", paste0("  ", shinyFilesLoadLine()), code)
    if (!is.null(roots)) {
      code <- sub("^  volumes <- c\\(Home = fs::path_home\\(\\), \"R Installation\" = R.home\\(\\), getVolumes\\(\\)\\(\\)\\)$",
                  paste0("  volumes <- ", roots), code)
    }
    writeLines(code, f)
  }
  normalizePath(dir)
}

topModal <- "$('.sF-modalContainer:visible').last()"

# --- showcase ---------------------------------------------------------------

showcaseTree <- local({
  base <- tempfile("sf-showcase")
  dir.create(file.path(base, "docs", "reports"), recursive = TRUE)
  writeLines("x", file.path(base, "docs", "notes.txt"))
  writeLines("x", file.path(base, "readme.txt"))
  normalizePath(base, winslash = "/")
})
withr::local_envvar(c(SF_SHOWCASE_ROOT = showcaseTree), .local_envir = teardown_env())

test_that("the showcase opens all three dialogs with the roots it describes", {
  skipUnlessBrowser()
  # As shipped: the home folder, the R installation and the other volumes.
  app <- newApp(localExample("showcase"), "example-showcase-roots")
  on.exit(app$stop(), add = TRUE)
  for (id in c("file", "directory", "save")) {
    openDialogFor(app, id)
    roots <- unlist(app$get_js(sprintf("%s.find('select.sF-breadcrumps option').map(function(){ return $(this).text().trim(); }).toArray()", topModal)))
    expect_true(any(grepl("Home", roots)), label = paste(id, "offers Home"))
    expect_true(any(grepl("R Installation", roots)), label = paste(id, "offers R Installation"))
    app$run_js(sprintf("%s.find('#sF-cancelButton').click();", topModal))
    app$wait_for_idle()
  }
  # The outputs say nothing has been chosen yet.
  expect_match(app$get_value(output = "filepaths"), "No files have been selected")
  expect_match(app$get_value(output = "directorypath"), "No directory has been selected")
  expect_match(app$get_value(output = "savefile"), "No file-save path has been set")
  expectNoAppErrors(app)
})

test_that("the showcase hides the base package's folder, as it says", {
  skipUnlessBrowser()
  app <- newApp(localExample("showcase"), "example-showcase-restrict")
  on.exit(app$stop(), add = TRUE)
  openDialogFor(app, "directory")
  rootIndex <- app$get_js(sprintf(
    "%s.find('select.sF-breadcrumps option').filter(function(){ return $(this).text().trim().indexOf('R Installation') !== -1; }).val()",
    topModal
  ))
  app$run_js(sprintf("%s.find('select.sF-breadcrumps').val(%s).trigger('change');", topModal, jsonlite::toJSON(rootIndex, auto_unbox = TRUE)))
  app$wait_for_idle()
  base <- system.file(package = "base")
  rel <- sub(paste0("^", normalizePath(R.home(), winslash = "/"), "/?"), "", normalizePath(base, winslash = "/"))
  parts <- strsplit(rel, "/")[[1]]
  skip_if(length(parts) < 2, "base is not under R.home() here")
  # Open the folder holding base (e.g. library/) and check base isn't listed.
  for (p in parts[-length(parts)]) {
    app$run_js(sprintf(
      "%s.find('.sF-dirList .sF-directory').filter(function(){ return $(this).children('.sF-file-name').text() === %s; }).last().children('.sF-expander').children('span').click();",
      topModal, jsonlite::toJSON(p, auto_unbox = TRUE)
    ))
    app$wait_for_idle()
  }
  shown <- unlist(app$get_js(sprintf("%s.find('.sF-dirList .sF-file-name').map(function(){ return $(this).text(); }).toArray()", topModal)))
  expect_true(any(shown == parts[length(parts) - 1]) || length(parts) == 1)
  expect_false("base" %in% shown)
  expect_true("stats" %in% shown || "utils" %in% shown, label = "other packages are listed")
  expectNoAppErrors(app)
})

test_that("the showcase's dialogs report what was chosen", {
  skipUnlessBrowser()
  roots <- 'c(Sample = Sys.getenv("SF_SHOWCASE_ROOT"))'
  app <- newApp(localExample("showcase", roots = roots), "example-showcase-choose")
  on.exit(app$stop(), add = TRUE)

  # File: pick readme.txt.
  openDialogFor(app, "file")
  app$run_js(sprintf("%s.find('.sF-fileList .sF-file').filter(function(){ return $(this).find('.sF-file-name').text() === 'readme.txt'; })[0].dispatchEvent(new MouseEvent('click', {bubbles: true}));", topModal))
  app$run_js(sprintf("%s.find('#sF-selectButton').click();", topModal))
  app$wait_for_idle()
  expect_match(app$get_value(output = "filepaths"), "readme.txt")

  # Folder: pick docs.
  openDialogFor(app, "directory")
  app$run_js(sprintf("%s.find('.sF-dirList .sF-file-name').filter(function(){ return $(this).text() === 'docs'; }).trigger('click');", topModal))
  app$wait_for_idle()
  app$run_js(sprintf("%s.find('#sF-selectButton').click();", topModal))
  app$wait_for_idle()
  expect_match(app$get_value(output = "directorypath"), "docs")

  # Save: name a new file, of type "text".
  openDialogFor(app, "save")
  app$run_js(sprintf("%s.find('input.sF-filename').val('out').trigger('keyup').trigger('change');", topModal))
  app$run_js(sprintf("%s.find('#sF-selectButton').click();", topModal))
  app$wait_for_idle()
  saved <- app$get_value(output = "savefile")
  expect_match(saved, "out")
  expect_match(saved, "text")
  expectNoAppErrors(app)
})

# --- long-names -------------------------------------------------------------

test_that("the long-names example builds its tree and reaches the deepest folder", {
  skipUnlessBrowser()
  app <- newApp(localExample("long-names"), "example-long-names")
  on.exit(app$stop(), add = TRUE)
  openDialogFor(app, "dir")
  for (i in 1:15) {
    app$run_js(sprintf("%s.find('.sF-dirList .sF-directory.closed').filter(function(){ return /^level_/.test($(this).children('.sF-file-name').text()); }).last().children('.sF-expander').children('span').click();", topModal))
    app$wait_for_idle()
  }
  app$run_js(sprintf("%s.find('.sF-dirList .sF-file-name').filter(function(){ return /^level_15_/.test($(this).text()); }).trigger('click');", topModal))
  app$wait_for_idle()

  # What the page asks you to check.
  m <- app$get_js(sprintf("(function(){
    var m = %s, tree = m.find('.sF-dirList').parent()[0], content = m.find('.sF-dirContent').parent()[0];
    var name = m.find('.sF-dirContent > div > div:nth-child(2) > div').filter(function(){ return /^file_at_level_15/.test($(this).text()); })[0];
    var rows = m.find('.sF-dirList .sF-directory > .sF-file-name').toArray().map(function(e){ return Math.round(e.getBoundingClientRect().height); });
    return { treeScrolls: tree.scrollWidth > tree.clientWidth, contentScrolls: content.scrollWidth > content.clientWidth,
             nameClipped: !!name && name.scrollWidth > name.clientWidth + 1, tallest: Math.max.apply(null, rows) };
  })()", topModal))
  expect_true(m$treeScrolls, label = "1. the tree scrolls sideways")
  expect_true(m$contentScrolls, label = "2. the content pane scrolls sideways")
  expect_false(m$nameClipped, label = "2. the long file name is shown in full")
  expect_lt(m$tallest, 30, label = "3. rows keep their height")

  app$run_js(sprintf("%s.find('#sF-selectButton').click();", topModal))
  app$wait_for_idle()
  expect_match(app$get_value(output = "picked"), "level_15_", label = "4. the deepest folder is reported")
  expect_match(app$get_value(output = "summary"), "Deepest folder picked: yes")
  expectNoAppErrors(app)
})
