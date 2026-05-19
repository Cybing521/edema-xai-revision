# Edema XAI revision analysis - shared configuration
# Run from project root: Rscript analysis_r/run_all.R

options(stringsAsFactors = FALSE)

PROJECT_ROOT <- normalizePath(Sys.getenv("PROJECT_ROOT", getwd()), mustWork = TRUE)
DIR_RAW <- file.path(PROJECT_ROOT, "data", "raw")
DIR_PROCESSED <- file.path(PROJECT_ROOT, "data", "processed")
DIR_TABLES <- file.path(PROJECT_ROOT, "output", "tables")
DIR_FIGURES <- file.path(PROJECT_ROOT, "output", "figures")
DIR_MODELS <- file.path(PROJECT_ROOT, "output", "models")
DIR_REPORTS <- file.path(PROJECT_ROOT, "reports")

for (d in c(DIR_RAW, DIR_PROCESSED, DIR_TABLES, DIR_FIGURES, DIR_MODELS, DIR_REPORTS)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

required_packages <- c(
  "data.table", "stringr", "lubridate", "ggplot2", "scales", "pROC",
  "e1071", "caret", "kernlab", "fastshap", "rmarkdown", "knitr"
)

install_missing_packages <- function(pkgs = required_packages) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
  if (length(miss) > 0) {
    install.packages(miss, repos = "https://cloud.r-project.org")
  }
}

load_packages <- function(pkgs = required_packages) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
  if (length(miss) > 0) {
    stop("Missing R packages: ", paste(miss, collapse = ", "),
         "\nRun: Rscript -e 'source(\"analysis_r/00_config.R\"); install_missing_packages()'")
  }
  invisible(lapply(pkgs, library, character.only = TRUE))
}

clean_code <- function(x) toupper(gsub("[^A-Za-z0-9]", "", as.character(x)))

safe_fread <- function(path, ...) {
  if (!file.exists(path)) stop("Missing file: ", path)
  data.table::fread(path, showProgress = TRUE, ...)
}

write_csv_gz <- function(dt, path) {
  data.table::fwrite(dt, path)
  invisible(path)
}
