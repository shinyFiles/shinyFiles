# Long names and deep folders in the folder dialog (#188)
#
# Run it with:
#   shinyFiles::shinyFilesExample("long-names")
# or, from a checkout of the package:
#   shiny::runApp("inst/examples/long-names")
#
# It builds a sample tree in a temporary folder: 15 levels deep, with folder and
# file names of 40 to 70 characters. Open the dialog, expand the tree to the
# bottom, and pick the deepest folder.
#
# What to check (each one is also listed in the app):
#   1. The folder tree scrolls sideways once the tree is wider than its pane,
#      and every folder name can be read in full by scrolling.
#   2. The content pane scrolls sideways for a long file name, and the name is
#      shown in full, not cut off with "...".
#   3. Rows keep their height: nothing wraps onto a second line.
#   4. Picking the deepest folder still works and reports the full path below.

library(shiny)
if (dir.exists("../../../R") && file.exists("../../../DESCRIPTION")) {
  # Run from a checkout: use that copy of shinyFiles rather than an installed one.
  pkgload::load_all("../../..", export_all = FALSE, quiet = TRUE)
} else {
  library(shinyFiles)
}

base <- file.path(tempdir(), "shinyFiles-long-names")
unlink(base, recursive = TRUE)
names_at <- function(i) {
  sprintf("level_%02d_%s", i, substr(strrep("a_rather_long_folder_name_", 3), 1, 30 + 2 * i))
}
deepest <- base
for (i in seq_len(15)) {
  deepest <- file.path(deepest, names_at(i))
  dir.create(deepest, recursive = TRUE)
  dir.create(file.path(deepest, sprintf("sibling_%02d", i)))
  writeLines("sample", file.path(deepest, sprintf(
    "file_at_level_%02d_with_an_unusually_long_name_for_the_content_pane.txt", i
  )))
}
roots <- c(sample = base)

checks <- c(
  "The folder tree scrolls sideways once it is wider than its pane, and every folder name can be read in full.",
  "The content pane scrolls sideways for the long file name, and shows it in full rather than cut off with \"...\".",
  "Rows keep their height: no name wraps onto a second line.",
  "Picking the deepest folder works, and its full path appears below."
)

ui <- fluidPage(
  titlePanel("shinyFiles: long names and deep folders"),
  p("Open the dialog, expand the tree down to level 15 with the arrows, click the deepest folder, and press Select."),
  shinyDirButton("dir", "Open the folder dialog", "Long names and deep folders"),
  h4("Check each of these"),
  tags$ol(lapply(seq_along(checks), function(i) {
    tags$li(checks[[i]], " ", radioButtons(paste0("check", i), NULL, c("Not yet" = "", "Works" = "works", "Broken" = "broken"), inline = TRUE))
  })),
  h4("Folder you picked"),
  verbatimTextOutput("picked"),
  h4("Summary to send back"),
  verbatimTextOutput("summary")
)

server <- function(input, output, session) {
  shinyDirChoose(input, "dir", roots = roots)
  picked <- reactive(parseDirPath(roots, input$dir))
  output$picked <- renderText(if (length(picked()) == 0) "(nothing yet)" else picked())
  output$summary <- renderText({
    answers <- vapply(seq_along(checks), function(i) {
      a <- input[[paste0("check", i)]]
      sprintf("%-7s %d. %s", if (is.null(a) || a == "") "-" else toupper(a), i, checks[[i]])
    }, "")
    reachedBottom <- length(picked()) == 1 && grepl(names_at(15), picked(), fixed = TRUE)
    paste(c(
      sprintf("shinyFiles %s, %s", utils::packageVersion("shinyFiles"), R.version.string),
      sprintf("Deepest folder picked: %s", if (reachedBottom) "yes" else "no"),
      "",
      answers
    ), collapse = "\n")
  })
}

shinyApp(ui, server)
