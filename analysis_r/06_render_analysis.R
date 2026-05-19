source("analysis_r/00_config.R")
load_packages(c("rmarkdown", "knitr"))

rmd <- file.path(PROJECT_ROOT, "reports", "analysis_report_template.Rmd")
if (!file.exists(rmd)) stop("Missing report template: ", rmd)
rmarkdown::render(rmd, output_file = file.path(DIR_REPORTS, "analysis_report.html"), quiet = FALSE)
