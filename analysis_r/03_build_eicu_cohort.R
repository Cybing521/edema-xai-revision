source("analysis_r/00_config.R")
load_packages(c("data.table", "stringr"))

raw <- file.path(DIR_RAW, "eicu-crd", "2.0")
patient <- safe_fread(file.path(raw, "patient.csv.gz"))
diagnosis <- safe_fread(file.path(raw, "diagnosis.csv.gz"))

text_label <- function(x) {
  z <- tolower(paste(unique(na.omit(x)), collapse = " | "))
  cardiogenic <- grepl("heart failure|congestive|cardiogenic|pulmonary edema", z)
  renal <- grepl("renal failure|kidney|nephrotic|creatinine|dialysis", z)
  hepatic <- grepl("cirrhosis|hepatic|liver|ascites|portal hypertension", z)
  nutritional <- grepl("malnutrition|cachexia|hypoalbumin", z)
  other <- grepl("edema|oedema|anasarca|myxedema|lymphedema|capillary leak|drug-induced", z)
  if (cardiogenic) return("cardiogenic")
  if (renal) return("renal")
  if (hepatic) return("hepatic")
  if (nutritional) return("nutritional")
  if (other) return("other")
  return(NA_character_)
}

labels <- diagnosis[, .(edema_etiology = text_label(diagnosisstring)), by = patientunitstayid]
labels <- labels[!is.na(edema_etiology)]

cohort <- merge(patient, labels, by = "patientunitstayid")
cohort[, age_num := suppressWarnings(as.numeric(gsub(">", "", age)))]
cohort <- cohort[is.na(age_num) | age_num >= 18]
cohort[, source_database := "eICU-CRD v2.0"]

lab <- safe_fread(file.path(raw, "lab.csv.gz"), select = c("patientunitstayid", "labresultoffset", "labname", "labresult"))
lab[, labname_lower := tolower(labname)]
lab <- lab[labresultoffset >= -360 & labresultoffset <= 1440]
lab_patterns <- data.table(
  feature = c("albumin", "creatinine", "bilirubin_total", "alt", "sodium", "potassium", "hemoglobin", "wbc", "bnp"),
  pattern = c("albumin", "creatinine", "bilirubin", "alt|sgpt", "sodium", "potassium", "hemoglobin", "wbc|white", "bnp|brain natriuretic|nt-probnp")
)
lab_features <- rbindlist(lapply(seq_len(nrow(lab_patterns)), function(i) {
  lab[grepl(lab_patterns$pattern[i], labname_lower), .(patientunitstayid, feature = lab_patterns$feature[i], value = as.numeric(labresult))]
}), fill = TRUE)
lab_features <- lab_features[!is.na(value)]
lab_wide <- dcast(lab_features[, .(value = median(value, na.rm = TRUE)), by = .(patientunitstayid, feature)], patientunitstayid ~ feature, value.var = "value")

vital <- safe_fread(file.path(raw, "vitalPeriodic.csv.gz"))
keep_cols <- intersect(names(vital), c("patientunitstayid", "observationoffset", "temperature", "sao2", "heartrate", "respiration", "systemicsystolic", "systemicdiastolic"))
vital <- vital[, ..keep_cols]
vital <- vital[observationoffset >= 0 & observationoffset <= 1440]
setnames(vital,
         old = intersect(names(vital), c("heartrate", "respiration", "systemicsystolic", "systemicdiastolic", "sao2")),
         new = c("heart_rate", "resp_rate", "sbp", "dbp", "spo2")[seq_along(intersect(names(vital), c("heartrate", "respiration", "systemicsystolic", "systemicdiastolic", "sao2")))],
         skip_absent = TRUE)
num_cols <- setdiff(names(vital), c("patientunitstayid", "observationoffset"))
vital_wide <- vital[, lapply(.SD, function(x) median(as.numeric(x), na.rm = TRUE)), by = patientunitstayid, .SDcols = num_cols]

model_dt <- Reduce(function(x, y) merge(x, y, by = "patientunitstayid", all.x = TRUE), list(
  cohort[, .(patientunitstayid, age_num, gender, hospitalid, source_database, edema_etiology)],
  lab_wide,
  vital_wide
))
setnames(model_dt, "age_num", "anchor_age")
write_csv_gz(model_dt, file.path(DIR_PROCESSED, "eicu_model_dataset.csv.gz"))
fwrite(model_dt[, .N, by = edema_etiology][order(-N)], file.path(DIR_TABLES, "eicu_label_distribution.csv"))
message("eICU cohort complete: ", nrow(model_dt), " ICU stays")
