# End-to-end tests for a folder chooser opened at defaultPath (#110).
#
# The tree is drawn from the root down to defaultPath, and picking a folder
# there must report it under defaultPath, not straight under the root.

library(shinytest2)

appDir <- local({
  dir <- fs::path(tempfile("sf-dirdefault-e2e"))
  fs::dir_create(fs::path(dir, "data", "tmp", "pick", "inner"))
  fs::dir_create(fs::path(dir, "data", "tmp", "other"))
  fs::dir_create(fs::path(dir, "data", "pick"))

  writeLines(
    c(
      'library(shiny)',
      shinyFilesLoadLine(),
      'base <- Sys.getenv("SF_DIRDEFAULT_E2E_BASE")',
      'roots <- c(first = file.path(base, "data", "pick"), data = file.path(base, "data"))',
      'ui <- fluidPage(',
      '  shinyDirButton("dir", "Pick dir", "Pick a directory"),',
      '  verbatimTextOutput("dirpath")',
      ')',
      'server <- function(input, output, session) {',
      '  shinyDirChoose(input, "dir", roots = roots, defaultRoot = "data", defaultPath = "tmp")',
      '  output$dirpath <- renderText({',
      '    req(input$dir)',
      '    as.character(parseDirPath(roots, input$dir))',
      '  })',
      '}',
      'shinyApp(ui, server)'
    ),
    fs::path(dir, "app.R")
  )
  as.character(fs::path_real(dir))
})

base <- appDir

withr::local_envvar(c(SF_DIRDEFAULT_E2E_BASE = base), .local_envir = teardown_env())

topModal <- "$('.sF-modalContainer:visible').last()"

# Clicks a folder in the tree by its chain of names below the root. "pick"
# exists both at the root and inside "tmp", so a bare name would be ambiguous.
clickTreeFolder <- function(app, chain) {
  find <- paste0(sprintf(
    ".children('.sF-content').children('.sF-directory').filter(function(){ return $(this).children('.sF-file-name').text() === '%s'; })",
    chain
  ), collapse = "")
  app$run_js(sprintf(
    "%s.find('.sF-dirList > .sF-directory')%s.children('.sF-file-name').trigger('click');",
    topModal, find
  ))
  app$wait_for_idle()
}

test_that("the dialog opens with defaultPath selected in the tree", {
  skipUnlessBrowser()
  app <- newApp(appDir, "dirdefault-open")
  on.exit(app$stop(), add = TRUE)

  openDialogFor(app, "dir")
  expect_equal(app$get_js(sprintf("%s.find('.sF-dirList .selected > .sF-file-name').text()", topModal)), "tmp")
  expect_true("pick" %in% unlist(app$get_js(sprintf(
    "%s.find('.sF-dirContent .sF-file-name').map(function(){ return $(this).text(); }).get()", topModal
  ))))
})

test_that("choosing a folder inside defaultPath reports it under defaultPath (#110)", {
  skipUnlessBrowser()
  app <- newApp(appDir, "dirdefault-pick")
  on.exit(app$stop(), add = TRUE)

  openDialogFor(app, "dir")
  waitForSelector(app, ".sF-modalContainer.in .sF-dirList .sF-file-name")
  clickTreeFolder(app, c("tmp", "pick"))
  app$run_js(sprintf("%s.find('#sF-selectButton').click();", topModal))
  app$wait_for_idle()

  expect_equal(app$get_value(output = "dirpath"), file.path(base, "data", "tmp", "pick"))
})

test_that("choosing defaultPath itself reports defaultPath", {
  skipUnlessBrowser()
  app <- newApp(appDir, "dirdefault-self")
  on.exit(app$stop(), add = TRUE)

  openDialogFor(app, "dir")
  app$run_js(sprintf("%s.find('#sF-selectButton').click();", topModal))
  app$wait_for_idle()

  expect_equal(app$get_value(output = "dirpath"), file.path(base, "data", "tmp"))
})
