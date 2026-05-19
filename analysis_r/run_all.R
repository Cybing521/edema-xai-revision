# Run from project root on mimo server.
source("analysis_r/00_config.R")
load_packages()
source("analysis_r/01_download_physionet.R")
source("analysis_r/02_build_mimic_cohort.R")
source("analysis_r/03_build_eicu_cohort.R")
source("analysis_r/04_modeling.R")
source("analysis_r/05_figures_and_tables.R")
source("analysis_r/06_render_analysis.R")
