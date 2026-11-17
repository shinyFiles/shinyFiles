#' Adds the content of www to sF/
#'
#' @importFrom shiny addResourcePath
#'
#' @noRd
#'
.onLoad <- function(...) {
  shiny::addResourcePath("sF", system.file("www", package = "shinyFiles"))
}

#' Drive letters and labels from WMIC
#'
#' WMIC is missing on newer Windows and fails on some machines (status 4110 in
#' #193); either way this returns NULL so PowerShell can be tried instead.
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
  out <- grep("|", sub("\\r$", "", out), fixed = TRUE, value = TRUE)
  if (length(out) == 0) return(NULL)
  drive <- sub("\\|.*$", "", out)
  label <- sub("^[^|]*\\|", "", out)
  volumes <- gsub("[\\\\/]$", "/", drive)
  names(volumes) <- paste0(ifelse(label == "", "", paste0(label, " ")), "(", sub("/$", "", volumes), ")")
  volumes
}

#' check for NULL or NA
#'
#' @noRd
#'
.is_not <- function(x) length(x) == 0 || (length(x) == 1 && is.na(x))

#' Run a simple example app using the shinyFiles functionality
#'
#' When the function is invoked a shiny app is started showing a very simple
#' setup using shinyFiles. A button summons the dialog box allowing the user to
#' navigate the R installation directory. To showcase the restrictions parameter
#' the base package location has been hidden, and is thus inaccessible. A panel
#' besides the button shows how the user selection is made accessible to the
#' server after parsing with [parseFilePaths()].
#'
#' @family shinyFiles
#'
#' @importFrom shiny runApp
#'
#' @export
#'
shinyFilesExample <- function() {
  shiny::runApp(system.file("example", package = "shinyFiles", mustWork = T), display.mode = "showcase")
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
      volumes <- windowsVolumesWmic()
      if (is.null(volumes)) volumes <- windowsVolumesPowershell()
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
