## Submission

This is an update of shinyFiles from 0.9.4 to 1.0.0. The version number marks
a large release: the open bug reports since the package changed maintainer
have been fixed, and several long-standing feature requests added. See NEWS.md
for the full list. Highlights:

* New-folder requests and parsed selections are kept inside the root they
  name.
* The script and stylesheets are attached as an HTML dependency, so a button
  inside a bslib accordion, `shinyjs::hidden()`, `renderUI()` or a Quarto
  document no longer opens two dialogs per click.
* The dialogs fit the window with Bootstrap 5 themes as well as Bootstrap 3.
* `getVolumes()` on Windows keeps each drive's label with its drive, and uses
  PowerShell before the deprecated WMIC.
* New options: a "Folders first" sort and a `sort` argument for the buttons,
  reactive `defaultPath`/`defaultRoot`, `parseFilePaths(order = "selection")`,
  `strictRoots` to stop symlinks leading out of a root, opening folders by
  tapping on touch screens, and typing to jump to an entry.

No exported function has been removed, and no argument has been removed from
an exported function; the new arguments are all optional, with defaults that
keep the 0.9.4 behaviour. One behaviour change is listed in NEWS.md:
`restrictions` now matches whole folders rather than any path containing the
text.

## R CMD check results

0 errors | 0 warnings | 1 note

* Days since last update: 6. 0.9.4 was the maintainer-change release. This
  update follows it closely to ship fixes for the bugs reported against the
  package, which the new maintainer worked through on taking it over.

## Test environments

* local: Red Hat Enterprise Linux 9.8, R 4.5.2 (`R CMD check --as-cran`)
* win-builder: R-release and R-devel
* GitHub Actions: ubuntu-latest (R-devel, R-release, R-oldrel-1 to -4),
  windows-latest (R-release, R 3.6), macOS-latest (R-release)

## Reverse dependencies

REVDEP_RESULTS
