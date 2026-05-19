#!/usr/bin/env bash
set -euo pipefail
cd /root/edema_xai_revision
Rscript -e 'source("analysis_r/00_config.R"); install_missing_packages()'
Rscript analysis_r/run_all.R
