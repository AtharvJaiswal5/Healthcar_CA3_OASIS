# Cognitive status classification from the supplied OASIS cross-sectional table
# Run from this project directory with Rscript analysis.R

set.seed(20261010)
dir.create("outputs/plots", recursive = TRUE, showWarnings = FALSE)
raw <- read.csv("data/oasis_cross-sectional.csv", na.strings = c("", "N/A"), check.names = FALSE)
stopifnot(all(c("ID", "M/F", "Age", "Educ", "SES", "MMSE", "CDR", "eTIV", "nWBV", "ASF", "Delay") %in% names(raw)))

raw$CDR_num <- suppressWarnings(as.numeric(as.character(raw$CDR)))
raw$participant <- sub("_MR[0-9]+$", "", raw$ID)
raw$target <- ifelse(is.na(raw$CDR_num), NA_integer_, as.integer(raw$CDR_num > 0))
eligible <- raw[!is.na(raw$target), ]
if (anyDuplicated(eligible$participant)) stop("Known-target records include repeated participants; revise split before modeling.")

# Split within each class. Each known-target participant appears once, so this
# stratified split also keeps participants disjoint across train/validation/test.
split <- setNames(rep(NA_character_, nrow(eligible)), eligible$ID)
for (cls in c(0L, 1L)) {
  idx <- which(eligible$target == cls)
  idx <- sample(idx)
  n_test <- floor(length(idx) * .20)
  n_valid <- floor(length(idx) * .20)
  split[eligible$ID[idx[seq_len(n_test)]]] <- "test"
  split[eligible$ID[idx[n_test + seq_len(n_valid)]]] <- "validation"
  split[eligible$ID[idx[-seq_len(n_test + n_valid)]]] <- "train"
}
eligible$partition <- unname(split[eligible$ID])
write.csv(data.frame(ID = eligible$ID, Participant = eligible$participant, Target = eligible$target, Partition = eligible$partition), "outputs/split_assignment.csv", row.names = FALSE)

raw_counts <- data.frame(
  Measure = c("Source rows", "Unique participants in workbook", "Rows with known CDR", "Rows with missing CDR", "Exact duplicate rows", "Known CDR equals zero", "Known CDR above zero", "Known-target rows with missing SES", "Known-target rows with missing MMSE", "Known-target rows with missing Delay"),
  Count = c(nrow(raw), length(unique(raw$participant)), sum(!is.na(raw$CDR_num)), sum(is.na(raw$CDR_num)), sum(duplicated(raw)), sum(eligible$target == 0), sum(eligible$target == 1), sum(is.na(eligible$SES)), sum(is.na(eligible$MMSE)), sum(is.na(eligible$Delay)))
)
write.csv(raw_counts, "outputs/data_audit.csv", row.names = FALSE)
write.csv(as.data.frame(table(CDR = ifelse(is.na(raw$CDR_num), "Missing", as.character(raw$CDR_num)))), "outputs/cdr_distribution.csv", row.names = FALSE)
attr_names <- c("ID", "M/F", "Hand", "Age", "Educ", "SES", "MMSE", "CDR", "eTIV", "nWBV", "ASF", "Delay")
attr_desc <- c("MRI session identifier", "Recorded sex category", "Handedness", "Age in years", "Years of education", "Socioeconomic status code", "Mini-Mental State Examination score", "Clinical Dementia Rating global score", "Estimated total intracranial volume", "Normalized whole-brain volume", "Atlas scaling factor", "MRI scan interval field")
attribute_table <- data.frame(Attribute = attr_names, Description = attr_desc, Missing_in_workbook = vapply(attr_names, function(v) sum(is.na(raw[[v]]) | as.character(raw[[v]]) == "N/A"), integer(1)))
write.csv(attribute_table, "outputs/attribute_dictionary.csv", row.names = FALSE)
write.csv(data.frame(Tool = c("R", "rpart", "Python", "openpyxl"), Version = c(as.character(getRversion()), as.character(utils::packageVersion("rpart")), "3.12.14", "3.1.5")), "outputs/tool_versions.csv", row.names = FALSE)

feature_sets <- list(
  "Logistic: demographics" = c("Age", "M/F", "Educ", "SES"),
  "Logistic: demographics + MRI" = c("Age", "M/F", "Educ", "SES", "eTIV", "nWBV"),
  "Logistic: demographics + MRI + MMSE" = c("Age", "M/F", "Educ", "SES", "eTIV", "nWBV", "MMSE")
)
numeric_vars <- c("Age", "Educ", "SES", "eTIV", "nWBV", "MMSE")
prep_block <- function(train, other, features) {
  tr <- train[, features, drop = FALSE]
  ot <- other[, features, drop = FALSE]
  for (v in features) {
    if (v == "M/F") {
      tr[[v]] <- factor(tr[[v]], levels = c("F", "M"))
      ot[[v]] <- factor(ot[[v]], levels = c("F", "M"))
    } else {
      med <- median(tr[[v]], na.rm = TRUE)
      if (!is.finite(med)) stop(paste("No observed training value for", v))
      tr[[v]][is.na(tr[[v]])] <- med
      ot[[v]][is.na(ot[[v]])] <- med
      mu <- mean(tr[[v]])
      sig <- sd(tr[[v]])
      if (!is.finite(sig) || sig == 0) sig <- 1
      tr[[v]] <- (tr[[v]] - mu) / sig
      ot[[v]] <- (ot[[v]] - mu) / sig
    }
  }
  xtr <- model.matrix(~ ., data = tr)[, -1, drop = FALSE]
  xot <- model.matrix(~ ., data = ot)[, -1, drop = FALSE]
  keep <- apply(xtr, 2, sd) > 0
  xtr <- xtr[, keep, drop = FALSE]
  xot <- xot[, keep, drop = FALSE]
  means <- colMeans(xtr)
  sds <- apply(xtr, 2, sd)
  sds[!is.finite(sds) | sds == 0] <- 1
  list(train = scale(xtr, center = means, scale = sds), other = scale(xot, center = means, scale = sds), names = colnames(xtr))
}
fit_logit <- function(train, other, features) {
  pp <- prep_block(train, other, features)
  fit <- glm.fit(x = cbind(`(Intercept)` = 1, pp$train), y = train$target, family = binomial())
  beta <- fit$coefficients
  beta[!is.finite(beta)] <- 0
  pred <- plogis(cbind(1, pp$other) %*% beta)
  list(prob = as.numeric(pred), fit = fit, coef = beta, features = pp$names)
}

train <- eligible[eligible$partition == "train", ]
valid <- eligible[eligible$partition == "validation", ]
test <- eligible[eligible$partition == "test", ]
pred_valid <- list()
pred_test <- list()
fits <- list()
for (nm in names(feature_sets)) {
  f <- fit_logit(train, valid, feature_sets[[nm]])
  g <- fit_logit(train, test, feature_sets[[nm]])
  pred_valid[[nm]] <- f$prob
  pred_test[[nm]] <- g$prob
  fits[[nm]] <- g
}

# Full multimodal data frame for a shallow tree and distance-based KNN.
full_features <- feature_sets[[3]]
tr_full <- train[, c(full_features, "target"), drop = FALSE]
va_full <- valid[, full_features, drop = FALSE]
te_full <- test[, full_features, drop = FALSE]
for (v in full_features) {
  if (v == "M/F") {
    tr_full[[v]] <- factor(tr_full[[v]], levels = c("F", "M"))
    va_full[[v]] <- factor(va_full[[v]], levels = c("F", "M"))
    te_full[[v]] <- factor(te_full[[v]], levels = c("F", "M"))
  } else {
    med <- median(tr_full[[v]], na.rm = TRUE)
    tr_full[[v]][is.na(tr_full[[v]])] <- med
    va_full[[v]][is.na(va_full[[v]])] <- med
    te_full[[v]][is.na(te_full[[v]])] <- med
  }
}
tr_tree <- tr_full[, full_features, drop = FALSE]
tr_tree$status <- factor(tr_full$target, levels = c(0, 1))
tree <- rpart::rpart(status ~ ., data = tr_tree, method = "class", control = rpart::rpart.control(cp = .01, minsplit = 18, maxdepth = 3))
pred_valid[["Decision tree: full features"]] <- predict(tree, newdata = va_full, type = "prob")[, "1"]
pred_test[["Decision tree: full features"]] <- predict(tree, newdata = te_full, type = "prob")[, "1"]

pp <- prep_block(train, valid, full_features)
pp_test <- prep_block(train, test, full_features)
knn_prob <- function(x_train, y_train, x_new, k = 9L) {
  apply(x_new, 1, function(z) {
    delta <- sweep(x_train, 2, z, "-")
    ds <- sqrt(rowSums(delta^2))
    mean(y_train[order(ds)[seq_len(min(k, length(ds)))]] == 1)
  })
}
pred_valid[["K nearest neighbours: full features"]] <- knn_prob(pp$train, train$target, pp$other, k = 9L)
pred_test[["K nearest neighbours: full features"]] <- knn_prob(pp_test$train, train$target, pp_test$other, k = 9L)

pred_valid[["Soft voting ensemble"]] <- rowMeans(cbind(
  pred_valid[["Logistic: demographics + MRI + MMSE"]],
  pred_valid[["Decision tree: full features"]],
  pred_valid[["K nearest neighbours: full features"]]
))
pred_test[["Soft voting ensemble"]] <- rowMeans(cbind(
  pred_test[["Logistic: demographics + MRI + MMSE"]],
  pred_test[["Decision tree: full features"]],
  pred_test[["K nearest neighbours: full features"]]
))
pred_valid[["Majority class baseline"]] <- rep(mean(train$target), nrow(valid))
pred_test[["Majority class baseline"]] <- rep(mean(train$target), nrow(test))

f2_score <- function(y, p) {
  tp <- sum(y == 1 & p == 1); fp <- sum(y == 0 & p == 1); fn <- sum(y == 1 & p == 0)
  precision <- if (tp + fp == 0) 0 else tp / (tp + fp)
  recall <- if (tp + fn == 0) 0 else tp / (tp + fn)
  if (4 * precision + recall == 0) 0 else 5 * precision * recall / (4 * precision + recall)
}
choose_threshold <- function(y, prob) {
  grid <- seq(.05, .95, by = .01)
  f2 <- vapply(grid, function(t) f2_score(y, as.integer(prob >= t)), numeric(1))
  candidates <- which(f2 == max(f2))
  # When F2 ties, retain the higher threshold to reduce false positive flags.
  grid[max(candidates)]
}
auc_rank <- function(y, prob) {
  n1 <- sum(y == 1); n0 <- sum(y == 0)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  r <- rank(prob, ties.method = "average")
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
score_one <- function(y, prob, threshold) {
  hat <- as.integer(prob >= threshold)
  tn <- sum(y == 0 & hat == 0); fp <- sum(y == 0 & hat == 1)
  fn <- sum(y == 1 & hat == 0); tp <- sum(y == 1 & hat == 1)
  precision <- if (tp + fp == 0) 0 else tp / (tp + fp)
  recall <- if (tp + fn == 0) 0 else tp / (tp + fn)
  specificity <- if (tn + fp == 0) 0 else tn / (tn + fp)
  f1 <- if (precision + recall == 0) 0 else 2 * precision * recall / (precision + recall)
  f2 <- if (4 * precision + recall == 0) 0 else 5 * precision * recall / (4 * precision + recall)
  c(Threshold = threshold, AUC = auc_rank(y, prob), Accuracy = mean(y == hat), Precision = precision, Recall = recall, Specificity = specificity, F1 = f1, F2 = f2, TN = tn, FP = fp, FN = fn, TP = tp)
}

model_names <- names(pred_test)
thresholds <- sapply(model_names, function(nm) {
  if (nm == "Majority class baseline") .5 else choose_threshold(valid$target, pred_valid[[nm]])
})
metrics <- do.call(rbind, lapply(model_names, function(nm) score_one(test$target, pred_test[[nm]], thresholds[[nm]])))
metrics <- data.frame(Model = model_names, metrics, row.names = NULL, check.names = FALSE)
write.csv(metrics, "outputs/model_comparison_test.csv", row.names = FALSE)

ensemble_name <- "Soft voting ensemble"
ensemble_hat <- as.integer(pred_test[[ensemble_name]] >= thresholds[[ensemble_name]])
cm <- table(factor(test$target, levels = c(0, 1), labels = c("Actual_0", "Actual_1")), factor(ensemble_hat, levels = c(0, 1), labels = c("Predicted_0", "Predicted_1")))
write.csv(as.data.frame.matrix(cm), "outputs/ensemble_confusion_matrix.csv")
pred_out <- data.frame(ID = test$ID, Target = test$target, lapply(model_names, function(nm) pred_test[[nm]]), check.names = FALSE)
names(pred_out) <- c("ID", "Target", make.names(model_names, unique = TRUE))
write.csv(pred_out, "outputs/test_predictions.csv", row.names = FALSE)

coef_fit <- fits[["Logistic: demographics + MRI + MMSE"]]
coef_out <- data.frame(Feature = names(coef_fit$coef), Coefficient = as.numeric(coef_fit$coef), Odds_Ratio_per_scaled_unit = exp(as.numeric(coef_fit$coef)))
write.csv(coef_out, "outputs/logistic_coefficients.csv", row.names = FALSE)
importance <- if (is.null(tree$variable.importance)) numeric() else sort(tree$variable.importance, decreasing = TRUE)
write.csv(data.frame(Feature = names(importance), Split_Importance = as.numeric(importance)), "outputs/tree_variable_importance.csv", row.names = FALSE)

split_summary <- as.data.frame.matrix(table(Partition = eligible$partition, Target = eligible$target))
split_summary$Partition <- rownames(split_summary)
write.csv(split_summary, "outputs/split_class_counts.csv", row.names = FALSE)

# Plots
png("outputs/plots/01_target_availability.png", width = 1400, height = 850, res = 150)
par(mar = c(5, 6, 3, 1), family = "sans")
avail <- c("CDR 0" = sum(eligible$target == 0), "CDR above 0" = sum(eligible$target == 1), "CDR missing" = sum(is.na(raw$target)))
bp <- barplot(avail, col = c("#3A86FF", "#EF476F", "#AAB4C0"), border = NA, ylab = "Workbook rows", main = "Target availability and included records", ylim = c(0, 250), las = 1)
text(bp, avail + 7, labels = avail, font = 2, cex = 1.1)
dev.off()

png("outputs/plots/02_age_by_cdr.png", width = 1400, height = 850, res = 150)
par(mar = c(5, 5, 3, 1), family = "sans")
boxplot(Age ~ factor(target, levels = c(0, 1), labels = c("CDR 0", "CDR > 0")), data = eligible, col = c("#3A86FF", "#EF476F"), ylab = "Age (years)", xlab = "Recorded CDR group", main = "Age distribution in records with known CDR", outline = TRUE)
dev.off()

png("outputs/plots/03_mmse_nwbv_by_cdr.png", width = 1400, height = 850, res = 150)
par(mfrow = c(1, 2), mar = c(5, 5, 3, 1), family = "sans")
boxplot(MMSE ~ factor(target, levels = c(0, 1), labels = c("CDR 0", "CDR > 0")), data = eligible, col = c("#3A86FF", "#EF476F"), ylab = "MMSE", xlab = "Recorded CDR group", main = "MMSE by CDR group", outline = TRUE)
boxplot(nWBV ~ factor(target, levels = c(0, 1), labels = c("CDR 0", "CDR > 0")), data = eligible, col = c("#3A86FF", "#EF476F"), ylab = "Normalized whole-brain volume", xlab = "Recorded CDR group", main = "nWBV by CDR group", outline = TRUE)
dev.off()

png("outputs/plots/04_test_model_metrics.png", width = 1600, height = 1050, res = 150)
par(mfrow = c(1, 2), mar = c(5, 11, 3, 2), family = "sans")
ord_auc <- order(metrics$AUC)
barplot(metrics$AUC[ord_auc], names.arg = metrics$Model[ord_auc], horiz = TRUE, las = 1, col = "#3A86FF", border = NA, xlim = c(0, 1), xlab = "ROC-AUC", main = "Held-out test AUC")
ord_f2 <- order(metrics$F2)
barplot(metrics$F2[ord_f2], names.arg = metrics$Model[ord_f2], horiz = TRUE, las = 1, col = "#2A9D8F", border = NA, xlim = c(0, 1), xlab = "F2 score", main = "Held-out test F2")
dev.off()

png("outputs/plots/05_ensemble_confusion_matrix.png", width = 1000, height = 850, res = 150)
par(mar = c(6, 6, 4, 2), family = "sans")
image(1:2, 1:2, t(cm), col = c("#EEF4FA", "#EF476F"), axes = FALSE, xlab = "Predicted class", ylab = "Actual class", main = "Soft-voting ensemble on held-out test set")
axis(1, at = 1:2, labels = c("CDR 0", "CDR > 0")); axis(2, at = 1:2, labels = c("CDR 0", "CDR > 0"), las = 1)
text(rep(1:2, each = 2), rep(1:2, 2), labels = as.vector(t(cm)), cex = 1.5, font = 2)
dev.off()

roc_points <- function(y, p) {
  th <- c(Inf, sort(unique(p), decreasing = TRUE), -Inf)
  data.frame(FPR = vapply(th, function(t) mean(p[y == 0] >= t), numeric(1)), TPR = vapply(th, function(t) mean(p[y == 1] >= t), numeric(1)))
}
png("outputs/plots/06_roc_curves.png", width = 1200, height = 900, res = 150)
par(mar = c(5, 5, 3, 1), family = "sans")
plot(c(0, 1), c(0, 1), type = "n", xlab = "False positive rate", ylab = "True positive rate", main = "ROC curves on held-out test set", asp = 1)
abline(0, 1, lty = 2, col = "#9AA5B1")
for (nm in c("Logistic: demographics + MRI + MMSE", "Decision tree: full features", "K nearest neighbours: full features", "Soft voting ensemble")) {
  rp <- roc_points(test$target, pred_test[[nm]])
  lines(rp$FPR, rp$TPR, lwd = 2, col = if (nm == ensemble_name) "#EF476F" else "#3A86FF")
}
legend("bottomright", legend = c("Logistic full", "Decision tree", "KNN", "Soft voting ensemble"), col = c("#3A86FF", "#3A86FF", "#3A86FF", "#EF476F"), lwd = 2, bty = "n")
dev.off()

cat("Raw rows:", nrow(raw), "\nKnown CDR:", nrow(eligible), "\nTrain/validation/test:", nrow(train), nrow(valid), nrow(test), "\n")
print(metrics)
cat("Ensemble threshold selected on validation:", thresholds[[ensemble_name]], "\n")
