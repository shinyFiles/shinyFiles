# defaultPath and defaultRoot may be reactives or functions, re-read each time
# the dialog opens, so one dialog can start where another left off (#175).

makeTwoRoots <- function() {
  base <- tempfile("sf-defrx")
  fs::dir_create(fs::path(base, "a", c("one", "two")))
  fs::dir_create(fs::path(base, "b", "three"))
  fs::file_create(fs::path(base, "a", "one", "x.txt"))
  base <- as.character(fs::path_real(base))
  c(a = file.path(base, "a"), b = file.path(base, "b"))
}

reopen <- function(d) {
  d$session$setInputs(`f-modal` = NULL)
  d$open()
}

test_that("a reactive defaultPath is read each time the folder dialog opens", {
  start <- reactiveVal("one")
  withFileDialog(shinyDirChoose, makeTwoRoots(), function(d) {
    d$open()
    expect_equal(unlist(d$last()$contentPath), c("", "one"))
    start("two")
    reopen(d)
    expect_equal(unlist(d$last()$contentPath), c("", "two"))
  }, defaultRoot = "a", defaultPath = start)
})

test_that("a reactive defaultRoot is read each time too", {
  root <- reactiveVal("a")
  withFileDialog(shinyDirChoose, makeTwoRoots(), function(d) {
    d$open()
    expect_equal(d$last()$selectedRoot, "a")
    root("b")
    reopen(d)
    expect_equal(d$last()$selectedRoot, "b")
    expect_equal(unlist(d$last()$contentPath), c("", "three"))
  }, defaultRoot = root, defaultPath = function() if (root() == "a") "one" else "three")
})

test_that("the file and save dialogs take reactive defaults as well", {
  for (observer in list(shinyFileChoose, shinyFileSave)) {
    start <- reactiveVal("one")
    withFileDialog(observer, makeTwoRoots(), function(d) {
      d$open()
      expect_equal(crumbs(d$last()), c("", "one"))
      start("two")
      reopen(d)
      expect_equal(crumbs(d$last()), c("", "two"))
    }, defaultRoot = "a", defaultPath = start)
  }
})

test_that("a defaultPath taken from another dialog's choice opens there", {
  roots <- makeTwoRoots()
  server <- function(input, output, session) {
    shinyDirChoose(input, "src", roots = roots, session = session)
    chosen <- reactive({
      p <- input$src
      if (is.null(p) || is.integer(p)) "" else paste(unlist(p$path)[-1], collapse = "/")
    })
    shinyDirChoose(input, "dst", roots = roots, session = session, defaultRoot = "a", defaultPath = chosen)
  }
  sent <- list()
  testServer(server, {
    session$sendCustomMessage <- function(type, message) {
      if (!is.null(message$dir)) sent[[message$id]] <<- roundTrip(message$dir)
    }
    session$setInputs(src = list(root = "a", path = list("", "two")))
    session$setInputs(dst = 1)
    expect_equal(unlist(sent[[session$ns("dst")]]$contentPath), c("", "two"))
  })
})

test_that("plain values work as before", {
  withFileDialog(shinyDirChoose, makeTwoRoots(), function(d) {
    d$open()
    expect_equal(unlist(d$last()$contentPath), c("", "one"))
  }, defaultRoot = "a", defaultPath = "one")
})
