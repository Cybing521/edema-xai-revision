# Explainable AI for Edema Etiology (MIMIC-IV + eICU-CRD)

Reproducible R pipeline for the manuscript *Explainable Artificial Intelligence for Prediction and Stratified Management of Edema Etiology in Hospitalized Medical Patients*.

## Data access

You must have **credentialed** PhysioNet access and signed DUAs for:

| Database | Version | URL | DOI |
|----------|---------|-----|-----|
| MIMIC-IV | 2.2 | https://physionet.org/content/mimiciv/2.2/ | 10.13026/6mm1-ek67 |
| eICU-CRD | 2.0 | https://physionet.org/content/eicu-crd/2.0/ | 10.13026/C2WM1R |

Raw data are **not** included in this repository.

## Quick start

```bash
git clone https://github.com/Cybing521/edema-xai-revision.git
cd edema-xai-revision

# Configure PhysioNet credentials (local machine or server)
bash setup_physionet_netrc.sh

# Install R packages and run full pipeline from project root
Rscript -e 'source("analysis_r/00_config.R"); install_missing_packages()'
Rscript analysis_r/run_all.R
```

Outputs:

| Path | Description |
|------|-------------|
| `data/processed/mimic_model_dataset.csv.gz` | MIMIC modeling cohort |
| `data/processed/eicu_model_dataset.csv.gz` | eICU external validation cohort |
| `output/tables/table3_model_performance_mimic_internal_test.csv` | Internal test metrics (Table 3 source) |
| `output/figures/figure1_confusion_matrix.png` | 5×5 confusion matrix |
| `output/figures/figure2_roc.png` | One-vs-rest ROC (AUC matches Table 3) |
| `output/figures/figure3_shap_global_importance.png` | SHAP global importance |
| `reports/analysis_report.html` | HTML report |

## Pipeline

| Script | Step |
|--------|------|
| `analysis_r/01_download_physionet.R` | Download required tables |
| `analysis_r/02_build_mimic_cohort.R` | MIMIC ICU cohort + features + ICD labels |
| `analysis_r/03_build_eicu_cohort.R` | eICU external cohort |
| `analysis_r/04_modeling.R` | Radial SVM (caret), metrics, predictions |
| `analysis_r/05_figures_and_tables.R` | Figures 1–3 and CSV sources |
| `analysis_r/06_render_analysis.R` | R Markdown HTML report |

## Labeling (reproducible rules)

**MIMIC-IV:** ICD-10 prefixes per etiology (cardiogenic, renal, hepatic, nutritional, other) on hospital diagnoses linked to ICU stays; adults (≥18).

**eICU-CRD:** Keyword rules on `diagnosisstring` with the same five etiology classes.

See script comments in `02_build_mimic_cohort.R` and `03_build_eicu_cohort.R` for exact patterns.

## Model

- **Algorithm:** Support vector machine with radial basis kernel (`caret::train`, method `svmRadial`)
- **Tuning:** `C ∈ {0.5, 1, 2, 4}`, `sigma ∈ {0.001, 0.005, 0.01, 0.05}`, 5-fold CV on MIMIC training split (80/20)
- **SHAP:** `fastshap` on scaled features (default sample `SHAP_SAMPLE_N=500`, `SHAP_NSIM=30`)

## Environment

- R ≥ 4.2
- Packages: `data.table`, `caret`, `e1071`, `kernlab`, `pROC`, `ggplot2`, `fastshap`, `rmarkdown`, … (auto-installed via `00_config.R`)

## Citation

If you use this code, cite the corresponding manuscript and the MIMIC-IV / eICU-CRD publications per PhysioNet requirements.

## License

MIT License — see [LICENSE](LICENSE). Database contents remain under PhysioNet DUA terms.
