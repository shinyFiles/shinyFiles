#' Adds the content of www to sF/
#'
#' @importFrom shiny addResourcePath
#'
#' @noRd
#'
.onLoad <- function(...) {
  shiny::addResourcePath("sF", system.file("www", package = "shinyFiles"))
}

#' The script and stylesheets the buttons need
#'
#' Attached as an HTML dependency so the page loads them once, however the
#' buttons reach it (renderUI, bslib accordions, shinyjs::hidden() and so on).
#'
#' @importFrom htmltools htmlDependency
#' @importFrom utils packageVersion
#'
#' @noRd
#'
shinyFilesDependency <- function() {
  htmlDependency(
    "shinyFiles", as.character(packageVersion("shinyFiles")),
    src = "www", package = "shinyFiles",
    script = "shinyFiles.js", stylesheet = c("styles.css", "fileIcons.css")
  )
}

#' Drive letters and labels from WMIC
#'
#' Only used when PowerShell gives nothing. WMIC is missing on newer Windows and
#' fails on some machines (status 4110 in #193); either way this returns NULL.
#'
#' @noRd
#'
windowsVolumesWmic <- function() {
  wmic <- paste0(Sys.getenv("SystemRoot"), "\\System32\\Wbem\\WMIC.exe")
  if (!file.exists(wmic)) return(NULL)
  run <- function(args) {
    out <- suppressWarnings(system(paste(wmic, args), intern = TRUE, ignore.stderr = TRUE))
    if (!is.null(attr(out, "status"))) return(NULL)
    sub(" *\\r$", "", out)
  }
  volumes <- run("logicaldisk get Caption")
  volNames <- run("/FAILFAST:1000 logicaldisk get VolumeName")
  if (is.null(volumes) || is.null(volNames) || length(volumes) != length(volNames)) return(NULL)
  keep <- !tolower(volumes) %in% c("caption", "")
  volumes <- volumes[keep]
  if (length(volumes) == 0) return(NULL)
  volNames <- volNames[keep]
  volNames <- paste0(volNames, ifelse(volNames == "", "", " "), "(", volumes, ")")
  volumes <- gsub(":$", ":/", volumes)
  names(volumes) <- volNames
  volumes
}

#' Drive letters and labels from PowerShell
#'
#' One "name|label" line per drive, so a drive without a label (a disconnected
#' network drive, say) can't shift the labels of the drives after it (#171,
#' #200). Labels can't contain "|". A drive that isn't ready is still listed,
#' as WMIC does, but its label isn't read.
#'
#' @noRd
#'
windowsVolumesPowershell <- function() {
  command <- paste(
    "[System.IO.DriveInfo]::GetDrives() | ForEach-Object {",
    "$_.Name + '|' + $(if ($_.IsReady) { $_.VolumeLabel } else { '' }) }"
  )
  out <- suppressWarnings(tryCatch(
    system2("powershell", c("-NoProfile", "-Command", shQuote(command, type = "cmd")), stdout = TRUE),
    error = function(e) character(0)
  ))
  parsePowershellDrives(out)
}

#' Turn "name|label" lines from PowerShell into getVolumes() output
#'
#' @noRd
#'
parsePowershellDrives <- function(out) {
  out <- grep("|", sub("\\r$", "", out), fixed = TRUE, value = TRUE)
  if (length(out) == 0) return(NULL)
  drive <- sub("\\|.*$", "", out)
  label <- sub("^[^|]*\\|", "", out)
  volumes <- gsub("[\\\\/]$", "/", drive)
  names(volumes) <- paste0(ifelse(label == "", "", paste0(label, " ")), "(", sub("/$", "", volumes), ")")
  volumes
}

#' The value of an argument that may be given as a function or reactive
#'
#' `defaultPath` and `defaultRoot` can be plain values or functions (a
#' `reactive()` is one), read each time a dialog opens.
#'
#' @noRd
#'
currentValue <- function(x) if (is.function(x)) x() else x

#' check for NULL or NA
#'
#' @noRd
#'
.is_not <- function(x) length(x) == 0 || (length(x) == 1 && is.na(x))

#' Run an example app using the shinyFiles functionality
#'
#' Starts one of the example apps that come with shinyFiles.
#'
#' * `"showcase"` (the default) has a file, folder and save button side by
#'   side, with what each sends back to the server shown next to it, after
#'   parsing with [parseFilePaths()], [parseDirPath()] and [parseSavePath()].
#'   The buttons open the home directory, the R installation and the other
#'   volumes; to show the `restrictions` argument, the base package's folder
#'   is hidden. It runs in showcase mode, so its code is shown below it.
#' * `"long-names"` builds a deep tree of folders and files with long names in
#'   a temporary folder, and lists what to check in the folder dialog.
#'
#' The examples are in `system.file("examples", package = "shinyFiles")`.
#'
#' @param example Which example to run: `"showcase"` or `"long-names"`.
#'
#' @family shinyFiles
#'
#' @importFrom shiny runApp
#'
#' @export
#'
shinyFilesExample <- function(example = c("showcase", "long-names")) {
  example <- match.arg(example)
  dir <- system.file("examples", example, package = "shinyFiles", mustWork = TRUE)
  if (example == "showcase") {
    shiny::runApp(dir, display.mode = "showcase")
  } else {
    shiny::runApp(dir)
  }
}
#' Get a list of available volumes
#'
#' This function is intended as an input to the roots parameter in
#' [fileGetter()] and [shinyFileChoose()]. It returns a
#' function that returns a named vector of available volumes on the system. This
#' construction makes it dynamic so that a shinyFiles instance reflects new
#' volumes as they get added (e.g. usb drives). The function takes a single
#' argument giving names of volumes the developer wants removed from the return
#' value.
#'
#' @details
#' The function is OS specific and looks for volumes/drives in different places
#' depending on the system on which shiny is running.
#' \describe{
#'  \item{Windows}{Returns all drives mapped to a letter}
#'  \item{Mac OSX}{Looks in /Volumes/ and lists the directories therein}
#'  \item{Linux}{Returns the system root}
#' }
#' If the function does not recognize the system under which it is running it
#' will throw an error
#'
#' @param exclude A vector of volume names to be excluded from the return value
#'
#' @return A function returning a named vector of available volumes
#' 
#' @importFrom fs dir_exists dir_ls 
#'
#' @export
#'
getVolumes <- function(exclude) {
  if (missing(exclude)) exclude <- NULL

  function() {
    osSystem <- Sys.info()["sysname"]
    if (osSystem == "Darwin") {
      volumes <- dir_ls("/Volumes")
      names(volumes) <- basename(volumes)
    } else if (osSystem == "Linux") {
      volumes <- c("Computer" = "/")
      if (isTRUE(dir_exists("/media"))) {
        media <- dir_ls("/media")
        names(media) <- basename(media)
        volumes <- c(volumes, media)
      }
    } else if (osSystem == "Windows") {
      # PowerShell first: WMIC is removed from current Windows, and where it
      # remains it can wait tens of seconds on a disconnected network drive
      # (#199). It stays as a fallback for machines without PowerShell.
      volumes <- windowsVolumesPowershell()
      if (is.null(volumes)) volumes <- windowsVolumesWmic()
      if (is.null(volumes)) return(NULL)
    } else {
      stop("unsupported OS")
    }
    if (!is.null(exclude)) {
      volumes <- volumes[!names(volumes) %in% exclude]
    }
    volumes
  }
}

getSession <- function() {
  session <- shiny::getDefaultReactiveDomain()

  if (is.null(session)) {
    stop(paste(
      "could not find the Shiny session object. This usually happens when a",
      "shinyjs function is called from a context that wasn't set up by a Shiny session."
    ))
  }

  session
}
