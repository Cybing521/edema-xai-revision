source("analysis_r/00_config.R")
load_packages(c("data.table", "e1071", "caret", "kernlab", "pROC"))

set.seed(20260509)
`%||%` <- function(a, b) if (!is.null(a) && length(a) == 1 && !is.na(a)) a else b

mimic <- safe_fread(file.path(DIR_PROCESSED, "mimic_model_dataset.csv.gz"))
eicu_path <- file.path(DIR_PROCESSED, "eicu_model_dataset.csv.gz")
eicu <- if (file.exists(eicu_path)) safe_fread(eicu_path) else NULL

feature_cols <- intersect(
  c("anchor_age", "gender", "albumin", "creatinine", "bilirubin_total", "alt", "sodium", "potassium", "hemoglobin", "wbc", "bnp", "heart_rate", "sbp", "dbp", "resp_rate", "temperature", "spo2"),
  names(mimic)
)

prepare_xy <- function(dt, levels_y = NULL, train_medians = NULL, train_gender_levels = NULL) {
  dt <- data.table::copy(dt)
  missing_features <- setdiff(feature_cols, names(dt))
  for (nm in missing_features) dt[[nm]] <- NA
  y <- factor(dt$edema_etiology, levels = levels_y)
  if (is.null(levels_y)) y <- factor(dt$edema_etiology)
  x <- as.data.frame(dt[, ..feature_cols])
  if ("gender" %in% names(x)) {
    if (is.null(train_gender_levels)) train_gender_levels <- sort(unique(as.character(x$gender)))
    x$gender <- factor(as.character(x$gender), levels = train_gender_levels)
    x <- model.matrix(~ . - 1, data = x)
    x <- as.data.frame(x)
  }
  for (nm in names(x)) x[[nm]] <- as.numeric(x[[nm]])
  if (is.null(train_medians)) {
    train_medians <- vapply(x, function(z) median(z, na.rm = TRUE), numeric(1))
    train_medians[is.na(train_medians)] <- 0
  }
  for (nm in names(x)) {
    x[[nm]][is.na(x[[nm]])] <- train_medians[[nm]]
  }
  list(x = x, y = y, medians = train_medians, gender_levels = train_gender_levels)
}

idx <- caret::createDataPartition(factor(mimic$edema_etiology), p = 0.8, list = FALSE)
train_dt <- mimic[idx]
test_dt <- mimic[-idx]

prep_train <- prepare_xy(train_dt)
prep_test <- prepare_xy(test_dt, levels_y = levels(prep_train$y), train_medians = prep_train$medians, train_gender_levels = prep_train$gender_levels)

# Standardize using train parameters.
center <- vapply(prep_train$x, mean, numeric(1))
scalev <- vapply(prep_train$x, sd, numeric(1)); scalev[scalev == 0 | is.na(scalev)] <- 1
align_to_train <- function(x, template_cols, medians) {
  for (nm in setdiff(template_cols, names(x))) x[[nm]] <- medians[[nm]] %||% 0
  x <- x[, template_cols, drop = FALSE]
  x
}
scale_df <- function(x) as.data.frame(scale(x, center = center[colnames(x)], scale = scalev[colnames(x)]))
x_train <- prep_train$x
x_test <- align_to_train(prep_test$x, colnames(x_train), prep_train$medians)
x_train <- scale_df(x_train)
x_test <- scale_df(x_test)

# Conservative grid to avoid runaway runtime on large server jobs.
grid <- expand.grid(cost = c(0.5, 1, 2, 4), gamma = c(0.001, 0.005, 0.01, 0.05))
cv_ctrl <- caret::trainControl(method = "cv", number = 5, classProbs = TRUE, savePredictions = "final")
svm_fit <- caret::train(
  x = x_train,
  y = prep_train$y,
  method = "svmRadial",
  trControl = cv_ctrl,
  tuneGrid = data.frame(C = grid$cost, sigma = grid$gamma),
  metric = "Accuracy"
)

predict_probs <- function(model, x) {
  as.data.frame(predict(model, newdata = x, type = "prob"))
}

prob_test <- predict_probs(svm_fit, x_test)
pred_test <- colnames(prob_test)[max.col(prob_test, ties.method = "first")]
result_test <- data.table(test_dt[, .(stay_id, source_database, edema_etiology)], predicted = pred_test, prob_test)
fwrite(result_test, file.path(DIR_TABLES, "predictions_mimic_internal_test.csv"))

metric_by_class <- function(y_true, prob, pred) {
  classes <- levels(factor(y_true))
  rows <- lapply(classes, function(cl) {
    truth_bin <- as.integer(y_true == cl)
    auc_val <- tryCatch(as.numeric(pROC::auc(pROC::roc(truth_bin, prob[[cl]], quiet = TRUE))), error = function(e) NA_real_)
    tp <- sum(y_true == cl & pred == cl, na.rm = TRUE)
    fp <- sum(y_true != cl & pred == cl, na.rm = TRUE)
    fn <- sum(y_true == cl & pred != cl, na.rm = TRUE)
    precision <- ifelse(tp + fp == 0, NA, tp / (tp + fp))
    recall <- ifelse(tp + fn == 0, NA, tp / (tp + fn))
    f1 <- ifelse(is.na(precision + recall) || precision + recall == 0, NA, 2 * precision * recall / (precision + recall))
    data.table(edema_etiology = cl, AUC = auc_val, Precision = precision, Recall = recall, F1 = f1)
  })
  rbindlist(rows)
}

metrics_test <- metric_by_class(prep_test$y, prob_test, pred_test)
metrics_test <- rbind(metrics_test, data.table(
  edema_etiology = "Macro-average",
  AUC = mean(metrics_test$AUC, na.rm = TRUE),
  Precision = mean(metrics_test$Precision, na.rm = TRUE),
  Recall = mean(metrics_test$Recall, na.rm = TRUE),
  F1 = mean(metrics_test$F1, na.rm = TRUE)
))
fwrite(metrics_test, file.path(DIR_TABLES, "table3_model_performance_mimic_internal_test.csv"))

conf_test <- as.data.table(table(actual = prep_test$y, predicted = pred_test))
fwrite(conf_test, file.path(DIR_TABLES, "figure1_confusion_matrix_source.csv"))

if (!is.null(eicu)) {
  prep_eicu <- prepare_xy(eicu, levels_y = levels(prep_train$y), train_medians = prep_train$medians, train_gender_levels = prep_train$gender_levels)
  x_eicu_raw <- align_to_train(prep_eicu$x, colnames(x_train), prep_train$medians)
  x_eicu <- scale_df(x_eicu_raw)
  prob_eicu <- predict_probs(svm_fit, x_eicu)
  pred_eicu <- colnames(prob_eicu)[max.col(prob_eicu, ties.method = "first")]
  result_eicu <- data.table(eicu[, .(source_database, edema_etiology)], predicted = pred_eicu, prob_eicu)
  fwrite(result_eicu, file.path(DIR_TABLES, "predictions_eicu_external_validation.csv"))
  metrics_eicu <- metric_by_class(prep_eicu$y, prob_eicu, pred_eicu)
  fwrite(metrics_eicu, file.path(DIR_TABLES, "model_performance_eicu_external_validation.csv"))
}

saveRDS(list(model = svm_fit, feature_cols = feature_cols, center = center, scale = scalev, medians = prep_train$medians, gender_levels = prep_train$gender_levels), file.path(DIR_MODELS, "svm_radial_edema_model.rds"))
fwrite(as.data.table(svm_fit$bestTune), file.path(DIR_TABLES, "svm_best_hyperparameters.csv"))
message("Modeling complete.")
