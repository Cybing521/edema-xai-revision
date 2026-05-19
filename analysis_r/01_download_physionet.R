source("analysis_r/00_config.R")

# This script downloads only the tables needed for reproducible edema analysis.
# It requires a credentialed PhysioNet account with signed DUAs for MIMIC-IV and eICU-CRD.
# Do not put passwords in this repository. Configure ~/.netrc on the server:
# machine physionet.org
#   login YOUR_PHYSIONET_USERNAME
#   password YOUR_PHYSIONET_PASSWORD
# Then run: chmod 600 ~/.netrc

check_netrc <- function() {
  netrc <- path.expand("~/.netrc")
  if (!file.exists(netrc)) {
    stop("~/.netrc not found. Configure PhysioNet credentials on the server first. Do not store credentials in project files.")
  }
  invisible(TRUE)
}

download_one <- function(url, dest) {
  if (file.exists(dest) && file.info(dest)$size > 1024) {
    message("Exists: ", dest)
    return(invisible(dest))
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  cmd <- c("-L", "-C", "-", "--netrc", "--fail", "--retry", "5", "--retry-delay", "10", "-o", shQuote(dest), shQuote(url))
  status <- system2("curl", cmd)
  if (!identical(status, 0L)) stop("Download failed: ", url)
  if (file.info(dest)$size < 1024) stop("Downloaded file is too small, likely an auth error: ", dest)
  invisible(dest)
}

check_netrc()

mimic_files <- c(
  "hosp/patients.csv.gz",
  "hosp/admissions.csv.gz",
  "hosp/diagnoses_icd.csv.gz",
  "hosp/d_icd_diagnoses.csv.gz",
  "hosp/labevents.csv.gz",
  "hosp/d_labitems.csv.gz",
  "icu/icustays.csv.gz",
  "icu/d_items.csv.gz",
  "icu/chartevents.csv.gz"
)

eicu_files <- c(
  "patient.csv.gz",
  "diagnosis.csv.gz",
  "lab.csv.gz",
  "vitalPeriodic.csv.gz",
  "vitalAperiodic.csv.gz",
  "apachePatientResult.csv.gz",
  "apacheApsVar.csv.gz"
)

for (f in mimic_files) {
  download_one(
    paste0("https://physionet.org/files/mimiciv/2.2/", f),
    file.path(DIR_RAW, "mimiciv", "2.2", f)
  )
}

for (f in eicu_files) {
  download_one(
    paste0("https://physionet.org/files/eicu-crd/2.0/", f),
    file.path(DIR_RAW, "eicu-crd", "2.0", f)
  )
}

message("Download complete.")
