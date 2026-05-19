source("analysis_r/00_config.R")
load_packages(c("data.table", "stringr", "lubridate"))

raw <- file.path(DIR_RAW, "mimiciv", "2.2")

patients <- safe_fread(file.path(raw, "hosp", "patients.csv.gz"))
admissions <- safe_fread(file.path(raw, "hosp", "admissions.csv.gz"))
dx <- safe_fread(file.path(raw, "hosp", "diagnoses_icd.csv.gz"))
d_labitems <- safe_fread(file.path(raw, "hosp", "d_labitems.csv.gz"))
icu <- safe_fread(file.path(raw, "icu", "icustays.csv.gz"))

patients[, anchor_age := as.numeric(anchor_age)]
admissions[, admittime := as.POSIXct(admittime, tz = "UTC")]
admissions[, dischtime := as.POSIXct(dischtime, tz = "UTC")]
icu[, intime := as.POSIXct(intime, tz = "UTC")]
icu[, outtime := as.POSIXct(outtime, tz = "UTC")]
dx[, icd_clean := clean_code(icd_code)]

label_one <- function(codes) {
  codes <- unique(clean_code(codes))
  cardiogenic <- any(grepl("^(I50|I110|I130|I132|J81)", codes))
  renal <- any(grepl("^(N04|N05|N17|N18|N19|R80)", codes))
  hepatic <- any(grepl("^(K70|K72|K74|K76|R18)", codes))
  nutritional <- any(grepl("^(E40|E41|E42|E43|E44|E45|E46|R64)", codes))
  other <- any(grepl("^(R60|E03|I89|I87|T46|T50)", codes))
  if (cardiogenic) return("cardiogenic")
  if (renal) return("renal")
  if (hepatic) return("hepatic")
  if (nutritional) return("nutritional")
  if (other) return("other")
  return(NA_character_)
}

labels <- dx[, .(edema_etiology = label_one(icd_clean)), by = .(subject_id, hadm_id)]
labels <- labels[!is.na(edema_etiology)]

cohort <- merge(icu, labels, by = c("subject_id", "hadm_id"), allow.cartesian = FALSE)
cohort <- merge(cohort, patients[, .(subject_id, anchor_age, gender)], by = "subject_id", all.x = TRUE)
cohort <- cohort[anchor_age >= 18]
cohort[, stay_id := stay_id]
cohort[, source_database := "MIMIC-IV v2.2"]

# Lab feature extraction, first 24h from ICU admission.
lab_patterns <- data.table::data.table(
  feature = c("albumin", "creatinine", "bilirubin_total", "alt", "sodium", "potassium", "hemoglobin", "wbc", "bnp"),
  pattern = c("albumin", "creatinine", "bilirubin.*total|total.*bilirubin", "alanine|alt", "sodium", "potassium", "hemoglobin", "white blood|wbc", "bnp|brain natriuretic|nt-probnp")
)
d_labitems[, label_lower := tolower(label)]
lab_map <- rbindlist(lapply(seq_len(nrow(lab_patterns)), function(i) {
  d_labitems[grepl(lab_patterns$pattern[i], label_lower), .(itemid, feature = lab_patterns$feature[i])]
}), fill = TRUE)
lab_map <- unique(lab_map)

labevents <- safe_fread(file.path(raw, "hosp", "labevents.csv.gz"),
                        select = c("subject_id", "hadm_id", "itemid", "charttime", "valuenum"))
labevents <- labevents[itemid %in% lab_map$itemid & !is.na(valuenum)]
labevents[, charttime := as.POSIXct(charttime, tz = "UTC")]
labevents <- merge(labevents, lab_map, by = "itemid", allow.cartesian = TRUE)
lab_join <- merge(labevents, cohort[, .(subject_id, hadm_id, stay_id, intime)], by = c("subject_id", "hadm_id"))
lab_join <- lab_join[charttime >= intime - lubridate::hours(6) & charttime <= intime + lubridate::hours(24)]
lab_wide <- dcast(lab_join[, .(value = median(valuenum, na.rm = TRUE)), by = .(stay_id, feature)], stay_id ~ feature, value.var = "value")

# Vital feature extraction from chartevents. This is large and may take time.
d_items <- safe_fread(file.path(raw, "icu", "d_items.csv.gz"))
d_items[, label_lower := tolower(label)]
vital_patterns <- data.table::data.table(
  feature = c("heart_rate", "sbp", "dbp", "resp_rate", "temperature", "spo2"),
  pattern = c("heart rate", "arterial blood pressure systolic|non invasive blood pressure systolic", "arterial blood pressure diastolic|non invasive blood pressure diastolic", "respiratory rate", "temperature", "spo2|oxygen saturation")
)
vital_map <- rbindlist(lapply(seq_len(nrow(vital_patterns)), function(i) {
  d_items[grepl(vital_patterns$pattern[i], label_lower), .(itemid, feature = vital_patterns$feature[i])]
}), fill = TRUE)
vital_map <- unique(vital_map)

chartevents_path <- file.path(raw, "icu", "chartevents.csv.gz")
chartevents <- safe_fread(chartevents_path, select = c("subject_id", "hadm_id", "stay_id", "itemid", "charttime", "valuenum"))
chartevents <- chartevents[itemid %in% vital_map$itemid & !is.na(valuenum)]
chartevents[, charttime := as.POSIXct(charttime, tz = "UTC")]
chartevents <- merge(chartevents, vital_map, by = "itemid", allow.cartesian = TRUE)
vital_join <- merge(chartevents, cohort[, .(stay_id, intime)], by = "stay_id")
vital_join <- vital_join[charttime >= intime & charttime <= intime + lubridate::hours(24)]
vital_wide <- dcast(vital_join[, .(value = median(valuenum, na.rm = TRUE)), by = .(stay_id, feature)], stay_id ~ feature, value.var = "value")

model_dt <- Reduce(function(x, y) merge(x, y, by = "stay_id", all.x = TRUE), list(
  cohort[, .(stay_id, subject_id, hadm_id, anchor_age, gender, intime, source_database, edema_etiology)],
  lab_wide,
  vital_wide
))

write_csv_gz(model_dt, file.path(DIR_PROCESSED, "mimic_model_dataset.csv.gz"))
fwrite(model_dt[, .N, by = edema_etiology][order(-N)], file.path(DIR_TABLES, "mimic_label_distribution.csv"))
message("MIMIC cohort complete: ", nrow(model_dt), " ICU stays")
