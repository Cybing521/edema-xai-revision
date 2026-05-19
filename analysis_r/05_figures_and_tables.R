source("analysis_r/00_config.R")
load_packages(c("data.table", "ggplot2", "pROC", "fastshap", "scales"))
`%||%` <- function(a, b) if (!is.null(a) && length(a) == 1 && !is.na(a)) a else b

pred <- fread(file.path(DIR_TABLES, "predictions_mimic_internal_test.csv"))
meta_cols <- c("stay_id", "source_database", "edema_etiology", "predicted")
prob_cols <- setdiff(names(pred), meta_cols)
classes <- sort(unique(c(as.character(pred$edema_etiology), as.character(pred$predicted), prob_cols)))
pred[, edema_etiology := factor(edema_etiology, levels = classes)]
pred[, predicted := factor(predicted, levels = classes)]

# Figure 1: 5x5 confusion matrix heatmap.
cm <- as.data.table(table(actual = pred$edema_etiology, predicted = pred$predicted))
cm[, prop := N / sum(N), by = actual]
fwrite(cm, file.path(DIR_TABLES, "figure1_confusion_matrix_source.csv"))
p1 <- ggplot(cm, aes(x = predicted, y = actual, fill = prop)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = paste0(N, "\n", scales::percent(prop, accuracy = 0.1))), size = 3) +
  scale_fill_gradient(low = "#eef6fb", high = "#2b6ca3", labels = scales::percent) +
  labs(x = "Predicted etiology", y = "Actual etiology", fill = "Row %", title = "Five-class Confusion Matrix for Edema Etiology Prediction") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1), panel.grid = element_blank())
ggsave(file.path(DIR_FIGURES, "figure1_confusion_matrix.png"), p1, width = 7, height = 5.5, dpi = 300)

# Figure 2: one-vs-rest ROC curves using the same prediction table as Table 3.
roc_dt <- rbindlist(lapply(classes, function(cl) {
  roc_obj <- pROC::roc(as.integer(pred$edema_etiology == cl), pred[[cl]], quiet = TRUE)
  data.table(class = cl, specificity = roc_obj$specificities, sensitivity = roc_obj$sensitivities,
             auc = as.numeric(pROC::auc(roc_obj)))
}))
fwrite(unique(roc_dt[, .(class, auc)]), file.path(DIR_TABLES, "figure2_roc_auc_source.csv"))
p2 <- ggplot(roc_dt, aes(x = 1 - specificity, y = sensitivity, color = paste0(class, " AUC=", sprintf("%.3f", auc)))) +
  geom_line(linewidth = 1) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray60") +
  coord_equal() +
  labs(x = "1 - Specificity", y = "Sensitivity", color = "Edema etiology", title = "One-vs-Rest ROC Curves") +
  theme_minimal(base_size = 11)
ggsave(file.path(DIR_FIGURES, "figure2_roc.png"), p2, width = 7, height = 5.5, dpi = 300)

# Figure 3: SHAP global feature importance. This uses the saved model and internal-test feature space.
# If runtime is too long on the full data, set SHAP_SAMPLE_N before running.
model_obj <- readRDS(file.path(DIR_MODELS, "svm_radial_edema_model.rds"))
train_data_path <- file.path(DIR_PROCESSED, "mimic_model_dataset.csv.gz")
train_raw <- fread(train_data_path)
feature_cols <- model_obj$feature_cols
missing_features <- setdiff(feature_cols, names(train_raw))
for (nm in missing_features) train_raw[[nm]] <- NA
X <- as.data.frame(train_raw[, ..feature_cols])
if ("gender" %in% names(X)) {
  X$gender <- factor(as.character(X$gender), levels = model_obj$gender_levels)
  X <- as.data.frame(model.matrix(~ . - 1, data = X))
}
for (nm in setdiff(names(model_obj$center), names(X))) X[[nm]] <- model_obj$medians[[nm]] %||% 0
X <- X[, names(model_obj$center), drop = FALSE]
for (nm in names(X)) X[[nm]] <- as.numeric(X[[nm]])
for (nm in names(X)) X[[nm]][is.na(X[[nm]])] <- model_obj$medians[[nm]] %||% 0
X <- as.data.frame(scale(X, center = model_obj$center[colnames(X)], scale = model_obj$scale[colnames(X)]))
sample_n <- as.integer(Sys.getenv("SHAP_SAMPLE_N", "500"))
if (nrow(X) > sample_n) X <- X[sample(seq_len(nrow(X)), sample_n), , drop = FALSE]

pred_wrapper <- function(object, newdata) {
  prob <- predict(object$model, newdata = as.data.frame(newdata), type = "prob")
  apply(prob, 1, max)
}
shap <- fastshap::explain(model_obj, X = X, pred_wrapper = pred_wrapper, nsim = as.integer(Sys.getenv("SHAP_NSIM", "30")))
imp <- data.table(feature = colnames(shap), mean_abs_shap = colMeans(abs(shap), na.rm = TRUE))[order(-mean_abs_shap)]
fwrite(imp, file.path(DIR_TABLES, "figure3_shap_global_importance_source.csv"))
p3 <- ggplot(imp[1:min(.N, 15)], aes(x = reorder(feature, mean_abs_shap), y = mean_abs_shap)) +
  geom_col(fill = "#3c78a8") +
  coord_flip() +
  labs(x = "Clinical feature", y = "Mean absolute SHAP value", title = "SHAP Global Feature Importance") +
  theme_minimal(base_size = 11)
ggsave(file.path(DIR_FIGURES, "figure3_shap_global_importance.png"), p3, width = 7, height = 5.5, dpi = 300)

message("Figures complete.")
