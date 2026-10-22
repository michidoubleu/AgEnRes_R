# =============================================================================
# GLOBIOM (OUTPUT_AG_REG.csv) -> common GLOBIOM-style reporting format
#
# Run from anywhere inside the repository (project root is found via
# AgEnRes_R.Rproj), e.g. from the repository root:
#   Rscript scripts/GLOBIOM_to_template.R
#
# Source : inputs/template/OUTPUT_AG_REG.csv
#          (Indicator,Unit,Region,Item,CostScenario,Year,Value)
# Output : outputs/GLOBIOM/GLOBIOM_GLOBIOM_comprehensive.csv
#          outputs/GLOBIOM/mapping_log.csv
#          outputs/GLOBIOM/README.md
#
# GLOBIOM already reports in the glossary vocabulary, so the translation is a
# column rename / reorder plus Model = GLOBIOM. Codes and values are kept as
# reported. Defaults of claude_GLOBIOM_AG_REG_conversion_instructions.md
# section 9 (confirmed "keep it for now" by the project lead, 2026-10-22):
#   A all indicators; B COST keeps the management part (crop|HI|Seeds);
#   C GAMS 'Eps' (zero but present) written as 0; D FRTN kept in both units.
# =============================================================================

find_root <- function(d = normalizePath(getwd(), winslash = "/")) {
  while (!file.exists(file.path(d, "AgEnRes_R.Rproj"))) {
    p <- dirname(d)
    if (p == d) stop("Project root (AgEnRes_R.Rproj) not found above ", getwd())
    d <- p
  }
  d
}
ROOT <- find_root()
source(file.path(ROOT, "scripts", "shared_conversion_helpers.R"))

MODEL       <- "GLOBIOM"
SRC_REL     <- file.path("inputs", "template", "OUTPUT_AG_REG.csv")
OUT_DIR_REL <- file.path("outputs", "GLOBIOM")
OUT_CSV     <- "GLOBIOM_GLOBIOM_comprehensive.csv"

# -----------------------------------------------------------------------------
# 1. Mapping tables
# -----------------------------------------------------------------------------

# Source column -> template column (Model is added as a constant).
col_map <- data.table(
  source_column   = c("CostScenario", "Region", "Item", "Indicator", "Year", "Unit", "Value"),
  template_column = c("Scenario",     "Region", "Item", "Variable",  "Year", "Unit", "Value")
)

# Variables in scope (decision A: all). Set to a vector of codes to restrict.
SCOPE <- NULL

# Non-numeric source values that are translated; anything else stops the run.
# 'Eps' is GAMS's marker for a zero that is present in the solution.
SPECIAL_VALUES <- c("Eps" = 0)

# -----------------------------------------------------------------------------
# 2. Read
# -----------------------------------------------------------------------------

log_msg("== %s converter ==", MODEL)
vocab <- load_template_vocab(ROOT)

src_path <- file.path(ROOT, SRC_REL)
if (!file.exists(src_path)) stop("Source not found: ", SRC_REL)
t0 <- Sys.time()
src <- fread(src_path, colClasses = "character", na.strings = NULL, showProgress = FALSE)
log_msg("Source: %s - %d rows (%.1fs)", SRC_REL, nrow(src), as.numeric(difftime(Sys.time(), t0, units = "secs")))

miss <- setdiff(col_map$source_column, names(src))
if (length(miss)) stop("Source columns missing: ", paste(miss, collapse = ", "))
extra <- setdiff(names(src), col_map$source_column)
if (length(extra)) stop("Unmapped source columns: ", paste(extra, collapse = ", "), ". Add them to col_map.")

# -----------------------------------------------------------------------------
# 3. Conversion
# -----------------------------------------------------------------------------

src[, value := suppressWarnings(as.numeric(Value))]
src[, special := is.na(value) & Value %in% names(SPECIAL_VALUES)]
src[special == TRUE, value := SPECIAL_VALUES[Value]]
bad <- src[is.na(value) | !is.finite(value), unique(Value)]
if (length(bad)) stop("Non-numeric values not covered by SPECIAL_VALUES: ", paste(head(bad, 10), collapse = ", "))
n_special <- src[special == TRUE, .N, by = .(Indicator, Unit, Value)]
log_msg("Special values translated: %d (%s)", sum(n_special$N), paste(names(SPECIAL_VALUES), "->", SPECIAL_VALUES, collapse = ", "))

src[, in_scope := is.null(SCOPE) | Indicator %in% SCOPE]
x <- src[in_scope == TRUE]
out <- x[, .(Model = MODEL, Scenario = CostScenario, Region, Item, Variable = Indicator,
             Year, Unit, Value = value)]
setcolorder(out, vocab$columns)
log_msg("Rows: %d of %d source rows", nrow(out), nrow(src))

# -----------------------------------------------------------------------------
# 4. Validate and write (no additions: everything is GLOBIOM vocabulary)
# -----------------------------------------------------------------------------

out_dir <- file.path(ROOT, OUT_DIR_REL)
res <- validate_and_write(out, vocab, file.path(out_dir, OUT_CSV))

# -----------------------------------------------------------------------------
# 5. Mapping log: one row per source Indicator x Unit, plus column renames
# -----------------------------------------------------------------------------

lbl <- vocab$variable_labels
ind <- src[, .(n_src = .N, n_out = sum(in_scope), n_eps = sum(special)), by = .(Indicator, Unit)]
setorder(ind, Indicator, Unit)
var_log <- ind[, .(
  source_file = SRC_REL, source_table_or_range = "column Indicator",
  source_variable = Indicator,
  source_label_or_definition = fifelse(is.na(lbl[Indicator]), NA_character_, unname(lbl[Indicator])),
  source_unit = Unit, template_entry = Indicator, template_column_or_field = "Variable",
  transformation = fifelse(n_eps > 0, sprintf("value unchanged; %d 'Eps' written as 0", n_eps), "value unchanged"),
  output_unit = Unit,
  mapping_status = fifelse(n_out > 0, "Direct", "Excluded"), confidence = "high",
  n_output_rows = n_out,
  notes = fifelse(Indicator == "COST", "Item crop|management|category kept as reported (decision B).",
          fifelse(Indicator == "FRTN", "Reported in 1000 t and 1000 t dm; both kept (decision D).", NA_character_)),
  exclusion_reason = fifelse(n_out > 0, NA_character_, "Outside SCOPE"))]
col_log <- col_map[, .(source_file = SRC_REL, source_table_or_range = "header",
                       source_variable = sprintf("(column %s)", source_column),
                       template_entry = template_column, template_column_or_field = template_column,
                       transformation = fifelse(source_column == template_column, "kept", "renamed"),
                       mapping_status = "Direct", confidence = "high")]
col_log <- rbind(col_log, data.table(source_file = SRC_REL, source_variable = "(column Model)",
                                     template_entry = MODEL, template_column_or_field = "Model",
                                     transformation = "constant", mapping_status = "Direct",
                                     confidence = "high"), fill = TRUE)
write_mapping_log(rbindlist(list(col_log, var_log), fill = TRUE), file.path(out_dir, "mapping_log.csv"))

# -----------------------------------------------------------------------------
# 6. README
# -----------------------------------------------------------------------------

readme <- c(
  "# GLOBIOM -> common GLOBIOM-style reporting format",
  "",
  "_Generated by `scripts/GLOBIOM_to_template.R` - do not edit by hand; rerun the script instead._",
  "",
  "## 1. Source overview",
  "",
  sprintf("- File: `%s` (%d rows), columns `%s`.", SRC_REL, nrow(src), paste(names(src)[!names(src) %in% c("value", "special", "in_scope")], collapse = ", ")),
  sprintf("- %d indicators, %d regions, scenarios %s, years %s.", uniqueN(src$Indicator), uniqueN(src$Region),
          paste(sprintf("`%s`", unique(src$CostScenario)), collapse = ", "), paste(sort(unique(src$Year)), collapse = ", ")),
  "",
  "## 2. Output overview",
  "",
  sprintf("- File: `%s`", file.path(OUT_DIR_REL, OUT_CSV)),
  sprintf("- Rows: %d (all source rows in scope).", nrow(out)),
  readme_template_note(),
  "",
  "## 3. Mappings",
  "",
  md_table(col_map[, .(`Source column` = source_column, `Template column` = template_column)]),
  "",
  sprintf("- `Model` = `%s` (constant).", MODEL),
  "- All Variable, Item, Unit and Region codes are already GLOBIOM vocabulary; they are kept verbatim. No new codes.",
  "- `COST` keeps the management part of Item (`<crop>|<HI/IR/LI/SS>|<category>`), as reported. Partner models have no management part; comparison is done via a crosswalk, not by rewriting Items.",
  "- `FRTN` is reported in `1000 t` and `1000 t dm`; both are kept (Unit is part of the key).",
  "- `CTAX` is reported per emission source with the same price for each source; when comparing with a single carbon price take one source, do not sum.",
  "",
  "## 4. Transformations",
  "",
  "- **No value conversion.**",
  sprintf("- %d values `Eps` (GAMS: zero but present) written as `0`.", sum(n_special$N)),
  "",
  if (nrow(n_special)) md_table(n_special[, .(Variable = Indicator, Unit, rows = N)]),
  "",
  "## 5. Validation",
  "",
  readme_validation_note(),
  "",
  validation_md(res),
  "",
  "## 6. Reproduction",
  "",
  "```",
  "Rscript scripts/GLOBIOM_to_template.R",
  "```",
  "",
  "- R package: `data.table` (and `readxl` for the glossary). Replace `inputs/template/OUTPUT_AG_REG.csv` and rerun; non-numeric values other than `Eps` stop the run."
)
write_lines_lf(readme, file.path(out_dir, "README.md"))
log_msg("== %s done ==", MODEL)
