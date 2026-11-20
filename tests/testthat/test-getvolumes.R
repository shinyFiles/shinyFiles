# Unit tests for getVolumes(). Each OS branch is reached by mocking the calls it
# makes, so all of them run on any machine.

# getVolumes() looks up Sys.info(), system() and friends from base, so they are
# mocked in the package namespace, where its lookups start.
localOS <- function(sysname, ..., env = parent.frame()) {
  local_mocked_bindings(
    Sys.info = function() c(sysname = sysname),
    ...,
    .package = "base", .env = env
  )
}

test_that("macOS lists the folders in /Volumes", {
  localOS("Darwin")
  local_mocked_bindings(
    dir_ls = function(path, ...) {
      expect_equal(path, "/Volumes")
      fs::as_fs_path(c("/Volumes/Macintosh HD", "/Volumes/USB"))
    },
    .package = "shinyFiles"
  )
  v <- getVolumes()()
  expect_equal(unname(as.character(v)), c("/Volumes/Macintosh HD", "/Volumes/USB"))
  expect_equal(names(v), c("Macintosh HD", "USB"))
})

test_that("Linux returns the root, plus /media mounts when present", {
  localOS("Linux")
  local_mocked_bindings(dir_exists = function(path) FALSE, .package = "shinyFiles")
  expect_equal(getVolumes()(), c(Computer = "/"))

  local_mocked_bindings(
    dir_exists = function(path) c("/media" = TRUE),
    dir_ls = function(path, ...) fs::as_fs_path("/media/stick"),
    .package = "shinyFiles"
  )
  v <- getVolumes()()
  expect_equal(names(v), c("Computer", "stick"))
  expect_equal(unname(as.character(v)), c("/", "/media/stick"))
})

test_that("Windows reads drive letters and labels from WMIC when PowerShell can't", {
  localOS("Windows", file.exists = function(...) TRUE,
          system2 = function(...) stop("powershell not found"),
          system = function(command, ...) {
            if (grepl("VolumeName", command)) c("VolumeName  \r", "System  \r", "  \r", "")
            else c("Caption  \r", "C:  \r", "D:  \r", "")
          })
  v <- getVolumes()()
  expect_equal(unname(v), c("C:/", "D:/"))
  expect_equal(names(v), c("System (C:)", "(D:)"))
})

test_that("Windows reads drive letters and labels from PowerShell", {
  localOS("Windows", file.exists = function(...) FALSE,
          system2 = function(command, args, ...) {
            expect_equal(command, "powershell")
            c("C:\\|OS\r", "E:\\|", "")
          })
  v <- getVolumes()()
  expect_equal(unname(v), c("C:/", "E:/"))
  # A drive with no label is named after its letter alone, as with WMIC.
  expect_equal(names(v), c("OS (C:)", "(E:)"))
})

test_that("a drive without a label doesn't shift the labels after it (#171, #200)", {
  # A disconnected network drive has no label; the old output listed all the
  # names and then only the labels that existed, so later labels moved up.
  localOS("Windows", file.exists = function(...) FALSE,
          system2 = function(...) c("C:\\|System", "D:\\|Data", "H:\\|", "Z:\\|USBDRIVE"))
  v <- getVolumes()()
  expect_equal(unname(v), c("C:/", "D:/", "H:/", "Z:/"))
  expect_equal(names(v), c("System (C:)", "Data (D:)", "(H:)", "USBDRIVE (Z:)"))
})

test_that("PowerShell is used even where WMIC exists, so WMIC is never waited on (#199)", {
  # WMIC can take tens of seconds with a disconnected network drive, and is
  # removed from current Windows; PowerShell is asked first.
  localOS("Windows", file.exists = function(...) TRUE,
          system = function(command, ...) stop("WMIC should not be run"),
          system2 = function(...) "C:\\|OS")
  expect_equal(getVolumes()(), c("OS (C:)" = "C:/"))
})

test_that("Windows falls back to WMIC when PowerShell finds nothing", {
  localOS("Windows", file.exists = function(...) TRUE,
          system2 = function(...) character(0),
          system = function(command, ...) {
            if (grepl("VolumeName", command)) c("VolumeName  \r", "OS  \r", "")
            else c("Caption  \r", "C:  \r", "")
          })
  expect_equal(getVolumes()(), c("OS (C:)" = "C:/"))
})

test_that("a WMIC that fails is no worse than no WMIC (#193)", {
  localOS("Windows", file.exists = function(...) TRUE,
          system2 = function(...) character(0),
          system = function(command, ...) structure(character(0), status = 4110L))
  expect_null(getVolumes()())
})

test_that("Windows falls back to WMIC when PowerShell lists nothing usable", {
  localOS("Windows", file.exists = function(...) TRUE,
          system2 = function(...) c("garbage without a separator", ""),
          system = function(command, ...) {
            if (grepl("VolumeName", command)) c("VolumeName  \r", "  \r", "")
            else c("Caption  \r", "D:  \r", "")
          })
  expect_equal(getVolumes()(), c("(D:)" = "D:/"))
})

test_that("Windows returns NULL when PowerShell finds no drives", {
  localOS("Windows", file.exists = function(...) FALSE,
          system2 = function(...) character(0))
  expect_null(getVolumes()())
})

test_that("Windows returns NULL when PowerShell can't be run", {
  localOS("Windows", file.exists = function(...) FALSE,
          system2 = function(...) stop("powershell not found"))
  expect_null(getVolumes()())
})

test_that("on a real Windows machine the system drive is listed", {
  skip_on_cran()
  skip_if_not(.Platform$OS.type == "windows")
  v <- getVolumes()()
  expect_true(toupper(paste0(Sys.getenv("SystemDrive"), "/")) %in% toupper(v))
  expect_true(all(grepl("\\([A-Za-z]:\\)$", names(v))))
  expect_true(all(grepl("^[A-Za-z]:/$", v)))
})

test_that("on a real Windows machine PowerShell lists the system drive", {
  skip_on_cran()
  skip_if_not(.Platform$OS.type == "windows")
  v <- windowsVolumesPowershell()
  expect_true(toupper(paste0(Sys.getenv("SystemDrive"), "/")) %in% toupper(v))
})

test_that("an unknown OS is an error", {
  localOS("Plan9")
  expect_error(getVolumes()(), "unsupported OS")
})

test_that("exclude drops volumes by name", {
  localOS("Linux")
  local_mocked_bindings(
    dir_exists = function(path) c("/media" = TRUE),
    dir_ls = function(path, ...) fs::as_fs_path(c("/media/a", "/media/b")),
    .package = "shinyFiles"
  )
  expect_equal(names(getVolumes(exclude = c("Computer", "b"))()), "a")
})
