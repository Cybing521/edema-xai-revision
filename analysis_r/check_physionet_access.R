# Quick PhysioNet credential check (run on server after setup_physionet_netrc.sh)
source("analysis_r/00_config.R")

check_url <- function(url, label) {
  dest <- tempfile()
  cmd <- c("-sI", "-L", "--netrc", "--fail", "-o", "/dev/null", "-w", "%{http_code}", shQuote(url))
  code <- tryCatch(system2("curl", cmd, stdout = TRUE), error = function(e) "error")
  code <- as.character(code)[1]
  ok <- code == "200"
  message(sprintf("[%s] %s -> HTTP %s", ifelse(ok, "OK", "FAIL"), label, code))
  invisible(ok)
}

netrc <- path.expand("~/.netrc")
if (!file.exists(netrc)) stop("~/.netrc missing")
check_url("https://physionet.org/files/mimiciv/2.2/hosp/patients.csv.gz", "MIMIC-IV patients")
check_url("https://physionet.org/files/eicu-crd/2.0/patient.csv.gz", "eICU patient")
