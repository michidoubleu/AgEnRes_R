# =============================================================================
# OpenPROM -> common GLOBIOM-style reporting format
#
# Run from anywhere inside the repository (project root is found via
# AgEnRes_R.Rproj), e.g. from the repository root:
#   Rscript scripts/OpenPROM_to_template.R
#
# Source : every .xlsx in inputs/OpenPROM/ (currently
#          OPEN_PROM_output_template.xlsx). The data sheet is detected by its
#          header row "Scenario | Region | Variable | Unit | <years...>".
# Output : outputs/OpenPROM/OpenPROM_GLOBIOM_comprehensive.csv
#          outputs/OpenPROM/proposed_glossary_additions.csv
#          outputs/OpenPROM/mapping_log.csv
#          outputs/OpenPROM/README.md
#
# The current source file is a layout template whose values are all 1
# (placeholders). The converter is written for that layout so that a file with
# real values can be converted by simply rerunning this script.
#
# OpenPROM has no crop detail: Item is always AGR (agriculture), with
# sub-classes AGR|<carrier> / AGR|<service>. Values are not converted; all
# regions and years are kept as reported (project lead, 2026-10-21).
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

MODEL       <- "OpenPROM"
SRC_DIR_REL <- file.path("inputs", "OpenPROM")
OUT_DIR_REL <- file.path("outputs", "OpenPROM")
OUT_CSV     <- "OpenPROM_GLOBIOM_comprehensive.csv"
HEADER_KEYS <- c("Scenario", "Region", "Variable", "Unit")

# -----------------------------------------------------------------------------
# 1. Mapping tables
# -----------------------------------------------------------------------------

# Translation rules, matched in order against the OpenPROM Variable (first
# match wins). `item` may use the regex group \\1 (sub-class from the variable
# name). output_unit NA = source unit kept as is.
SEC <- "Agriculture, Fishing, Forestry"
rules <- rbindlist(list(
  list("^Final Energy[|]Agriculture, Fishing, Forestry[|].*[|][*]$", NA, NA, NA, "Excluded",
       "Placeholder row: '|*' means 'all corresponding fuels' (sheet notes). A file with real results has one row per fuel, which is translated by the next rule (ENUS, Item AGR|<service>|<fuel>)."),
  list("^Final Energy[|]Agriculture, Fishing, Forestry$", "ENUS", "AGR", NA, "Normalised",
       "Total final energy use of agriculture, fishing and forestry -> ENUS (energy use), Item AGR."),
  list("^Final Energy[|]Agriculture, Fishing, Forestry[|](.+)$", "ENUS", "AGR|\\1", NA, "Normalised",
       "Final energy use by carrier (or by service and carrier) -> ENUS, Item AGR|<carrier>."),
  list("^Price[|]Final Energy[|]Agriculture, Fishing, Forestry[|](.+)$", "PRIC", "AGR|\\1", NA, "Normalised",
       "Final energy price for agriculture by carrier -> PRIC (price), Item AGR|<carrier>."),
  list("^Price[|]Carbon$", "CTAX", "AGR", NA, "Normalised",
       "Carbon price -> glossary CTAX (carbon tax / price), Item AGR. GLOBIOM reports CTAX per emission source; OpenPROM has one price."),
  list("^Energy Service[|]Agriculture, Fishing, Forestry[|](Crops)$", "Area", "AGR|\\1", NA, "Normalised",
       "Crop area served by agricultural energy use -> glossary Area, Item AGR|Crops (1000 ha, as in GLOBIOM)."),
  list("^Energy Service[|]Agriculture, Fishing, Forestry[|](Irrigation & Water management)$", "ARIR", "AGR|\\1", "1000 ha", "Normalised",
       "Irrigated area -> glossary ARIR (irrigated area), Item AGR|Irrigation & Water management. Source label '1000 ha (irrigated)' is the same unit as GLOBIOM's '1000 ha'."),
  list("^Energy Service[|]Agriculture, Fishing, Forestry[|](Livestock operations)$", "Anim", "AGR|\\1", NA, "Normalised",
       "Livestock served by agricultural energy use -> glossary Anim (animal numbers), Item AGR|Livestock operations. Unit 1000 LU kept: GLOBIOM's Anim is in 1000 TLU (different weighting, not convertible without species detail)."),
  list("^Energy Service[|]Agriculture, Fishing, Forestry[|](.+)$", "ENSV", "AGR|\\1", NA, "Normalised",
       "Other energy-service activity (greenhouses, post-harvest, forestry, fishing) -> new variable ENSV, Item AGR|<service>."),
  list("^Price[|]Primary Energy[|]", NA, NA, NA, "Excluded",
       "Economy-wide primary energy price (not agriculture-specific, so Item AGR would be wrong). OPEN QUESTION for the project lead: report as PRIC with another Item, or leave out?")
))
setnames(rules, c("pattern", "Variable", "item", "output_unit", "status", "note"))

# Region definitions from the source sheet 'regions'; codes are kept as
# reported. Codes identical to GLOBIOM's are used as GLOBIOM codes - note that
# OAS and SSA are aggregates in both models whose composition may differ.
REGION_SHEET <- "regions"

# Source scenario -> Scenario. The baseline is spelled BASE as in GLOBIOM (project lead, 2026-10-22).
scenario_map <- data.table(
  source_scenario = "BASELINE",
  Scenario        = "BASE"
)

# New-code definitions (only codes actually used and not already GLOBIOM codes
# end up in proposed_glossary_additions.csv).
UNIT_DEFS <- c("Mtoe" = "Million tonnes of oil equivalent",
               "k$2015/toe" = "Thousand US dollars (2015) per tonne of oil equivalent",
               "$2015/tn CO2" = "US dollars (2015) per tonne CO2",
               "1000 LU" = "Thousand livestock units (European LU)",
               "1000 t" = "Thousand tonnes")

# -----------------------------------------------------------------------------
# 2. Source discovery and parsing
# -----------------------------------------------------------------------------

log_msg("== %s converter ==", MODEL)
vocab <- load_template_vocab(ROOT)

src_files <- sort(list.files(file.path(ROOT, SRC_DIR_REL), pattern = "\\.xlsx$", full.names = TRUE))
src_files <- src_files[!grepl("^~\\$", basename(src_files))]   # skip Excel lock files
if (!length(src_files)) stop("No .xlsx file found in ", SRC_DIR_REL)

# Finds the sheet and header row with Scenario | Region | Variable | Unit and
# returns the data in long format.
read_openprom <- function(path) {
  rel <- file.path(SRC_DIR_REL, basename(path))
  for (sh in excel_sheets(path)) {
    m <- read_sheet_matrix(path, sh)
    hit <- which(apply(m, 1, function(r) all(HEADER_KEYS %in% r)))
    if (!length(hit)) next
    h <- hit[1]
    pos <- match(HEADER_KEYS, m[h, ])
    year_cols <- which(grepl("^[0-9]{4}$", m[h, ]))
    if (!length(year_cols)) stop(rel, " sheet '", sh, "': header found but no year columns.")
    rows <- (h + 1):nrow(m)
    rows <- rows[m[rows, pos[3]] != ""]
    log_msg("  data sheet '%s': header row %d, %d data rows, years %s-%s", sh, h, length(rows),
            m[h, min(year_cols)], m[h, max(year_cols)])
    wide <- data.table(source_file = rel, source_sheet = sh, source_row = rows,
                       source_scenario = m[rows, pos[1]], source_region = m[rows, pos[2]],
                       source_variable = m[rows, pos[3]], source_unit = m[rows, pos[4]])
    vals <- m[rows, year_cols, drop = FALSE]
    colnames(vals) <- m[h, year_cols]
    long <- cbind(wide[rep(seq_len(nrow(wide)), times = length(year_cols))],
                  data.table(year = rep(colnames(vals), each = nrow(wide)), raw = as.vector(vals)))
    long[, value := parse_number(raw, "OpenPROM value")]
    return(long)
  }
  stop(rel, ": no sheet with header ", paste(HEADER_KEYS, collapse = " | "))
}

read_region_defs <- function(path) {
  if (!REGION_SHEET %in% excel_sheets(path)) return(data.table(code = character(), definition = character()))
  m <- read_sheet_matrix(path, REGION_SHEET)
  h <- which(m[, 1] == "REGION-CODE")[1]
  if (is.na(h)) return(data.table(code = character(), definition = character()))
  d <- data.table(code = m[(h + 1):nrow(m), 1], definition = trimws(paste(m[(h + 1):nrow(m), 2], m[(h + 1):nrow(m), 3])))
  d[code != ""]
}

src <- rbindlist(lapply(src_files, read_openprom))
region_defs <- unique(rbindlist(lapply(src_files, read_region_defs)), by = "code")
log_msg("Source records (variable x region x scenario x year): %d", nrow(src))

dups <- src[, .N, by = .(source_scenario, source_region, source_variable, year)][N > 1]
if (nrow(dups)) stop(nrow(dups), " duplicate Scenario/Region/Variable/year combinations in the source.")

vals <- src[!is.na(value), value]
PLACEHOLDER <- length(vals) > 0 && all(vals == 1)
if (PLACEHOLDER) log_msg("WARNING: every source value equals 1 - the file looks like an unfilled template (placeholders).")

unknown_scen <- setdiff(unique(src$source_scenario), scenario_map$source_scenario)
if (length(unknown_scen)) stop("Source scenario(s) not in scenario_map: ", paste(unknown_scen, collapse = ", "),
                               ". Add them to scenario_map in section 1.")

# -----------------------------------------------------------------------------
# 3. Conversion
# -----------------------------------------------------------------------------

vars <- unique(src[, .(source_variable, source_unit)])
classify <- function(v) {
  for (k in seq_len(nrow(rules))) {
    if (grepl(rules$pattern[k], v)) {
      r <- rules[k]
      return(list(rule = k, Variable = r$Variable, Item = if (is.na(r$item)) NA_character_ else sub(r$pattern, r$item, v),
                  status = r$status, note = r$note))
    }
  }
  list(rule = NA_integer_, Variable = NA_character_, Item = NA_character_, status = "Not reviewed",
       note = "Variable not covered by the rules in section 1")
}
vars <- cbind(vars, rbindlist(lapply(vars$source_variable, classify)))
vars[, Unit := fifelse(is.na(rules$output_unit[rule]) | is.na(rule), source_unit, rules$output_unit[rule])]
if (any(vars$status == "Not reviewed")) {
  log_msg("WARNING: variables not reviewed (not translated): %s",
          paste(vars[status == "Not reviewed", source_variable], collapse = "; "))
}

inc <- vars[!is.na(Variable)]
x <- src[!is.na(value)][inc, on = c("source_variable", "source_unit"), nomatch = 0L]
x <- x[scenario_map, on = "source_scenario", nomatch = 0L]
x[, `:=`(Model = MODEL, Region = source_region, Year = year, Value = value)]
out <- if (nrow(x)) x[, vocab$columns, with = FALSE] else
  setnames(data.table(matrix(character(), 0, length(vocab$columns))), vocab$columns)[, Value := numeric()][]
log_msg("Rows: %d (%s)", nrow(out), paste(out[, .N, by = Variable][, sprintf("%s=%d", Variable, N)], collapse = ", "))

# Proposed additions: new variables, the sub-class parts of Item, units and
# region codes, with their original OpenPROM terms.
sub_parts <- unique(inc[grepl("[|]", Item), .(part = split_item(sub("^AGR[|]", "", Item))), by = .(source_variable, Variable)])
sub_parts[, definition := fifelse(Variable %in% c("ENUS", "PRIC") & !grepl("^Energy Service", source_variable) &
                                    !part %in% sub("^Energy Service[|]Agriculture, Fishing, Forestry[|]", "",
                                                   vars[grepl("^Energy Service", source_variable), source_variable]),
                                  sprintf("Energy carrier '%s' (OpenPROM)", part),
                                  sprintf("Agricultural energy service '%s' (OpenPROM; sector %s)", part, SEC))]
additions <- rbindlist(list(
  additions_table("Variable", NEW_VARIABLES$code, NEW_VARIABLES$definition, "", MODEL),
  if (nrow(sub_parts)) additions_table("Item", sub_parts$part, sub_parts$definition, sub_parts$source_variable, MODEL),
  additions_table("Unit", names(UNIT_DEFS), unname(UNIT_DEFS), names(UNIT_DEFS), MODEL),
  if (nrow(region_defs)) additions_table("Region", region_defs$code, region_defs$definition, region_defs$code, MODEL)
))

# -----------------------------------------------------------------------------
# 4. Validate and write
# -----------------------------------------------------------------------------

out_dir <- file.path(ROOT, OUT_DIR_REL)
res <- validate_and_write(out, vocab, file.path(out_dir, OUT_CSV), additions = additions,
                          allowed_year_regex = "^[0-9]{4}$")
remove_legacy_output(out_dir, MODEL)
if (PLACEHOLDER) res$warnings <- c(res$warnings, "Source values are all 1 (placeholder template); the output is NOT real model results.")

# -----------------------------------------------------------------------------
# 5. Mapping log
# -----------------------------------------------------------------------------

src_files_txt <- paste(unique(src$source_file), collapse = "; ")
var_rows <- src[, .(source_table_or_range = sprintf("sheet rows %s (Variable column)", paste(range(source_row), collapse = "-"))),
                by = .(source_file, source_sheet, source_variable, source_unit)]
cnt <- if (nrow(x)) x[, .N, by = source_variable] else data.table(source_variable = character(), N = integer())
var_log <- cnt[vars[var_rows, on = c("source_variable", "source_unit")], on = "source_variable"]
var_log[, `:=`(
  source_label_or_definition = sprintf("Variable '%s' (%s)", source_variable, source_unit),
  template_entry = fifelse(is.na(Variable), NA_character_, paste(Variable, Item, sep = " | ")),
  template_column_or_field = fifelse(is.na(Variable), NA_character_, "Variable, Item, Unit, Value; Region and Year as reported"),
  transformation = fifelse(is.na(Variable), NA_character_,
                           fifelse(Unit == source_unit, "value unchanged; wide years -> long",
                                   sprintf("value unchanged; unit label '%s' -> '%s' (same unit); wide years -> long", source_unit, Unit))),
  output_unit = fifelse(is.na(Variable), NA_character_, Unit),
  mapping_status = status, n_output_rows = fifelse(is.na(N), 0L, N),
  notes = fifelse(is.na(Variable), NA_character_, note),
  exclusion_reason = fifelse(is.na(Variable), note, NA_character_))]

reg_log <- data.table(source_file = src_files_txt, source_variable = "(Region)",
                      source_label_or_definition = sprintf("Region '%s'", unique(src$source_region)),
                      template_entry = unique(src$source_region), template_column_or_field = "Region",
                      mapping_status = fifelse(unique(src$source_region) %in% vocab$regions, "Direct", "New code"),
                      notes = "Kept as reported (project lead, 2026-10-21).")
other_log <- data.table(
  source_file = src_files_txt,
  source_variable = c("(Year)", "(Scenario)", "(sheet notes / regions)"),
  source_label_or_definition = c(sprintf("Year columns %s-%s", min(src$year), max(src$year)),
                                 sprintf("Scenario '%s'", scenario_map$source_scenario),
                                 "Sheets 'regions' (region list) and 'notes' (fuel aggregation rules)"),
  template_entry = c("all years", scenario_map$Scenario, NA),
  template_column_or_field = c("Year", "Scenario", NA),
  transformation = c("All annual years kept as reported.", "Model scenario name kept as is.", NA),
  mapping_status = c("Direct", "Direct", "Not data"),
  notes = c(NA, NA, "Region names used as definitions of new region codes; notes explain the '|*' notation and fuel totals.")
)
map_log <- rbindlist(list(var_log, reg_log, other_log), fill = TRUE)
write_mapping_log(map_log, file.path(out_dir, "mapping_log.csv"))

# -----------------------------------------------------------------------------
# 6. README
# -----------------------------------------------------------------------------

rule_tab <- rules[, .(`OpenPROM variable (pattern)` = gsub("[\\^$]|\\[|\\]", "", pattern),
                      Variable = fifelse(is.na(Variable), "- (not translated)", Variable),
                      Item = fifelse(is.na(item), "-", gsub("\\\\1", "<sub-class>", item)),
                      Unit = fifelse(is.na(Variable), "-", fifelse(is.na(output_unit), "as reported", output_unit)),
                      Note = note)]
var_cnt <- vars[, .(n = .N), by = .(Status = status, Variable = fifelse(is.na(Variable), "-", Variable))]
reg_new <- setdiff(unique(src$source_region), vocab$regions)

readme <- c(
  "# OpenPROM -> common GLOBIOM-style reporting format",
  "",
  "_Generated by `scripts/OpenPROM_to_template.R` - do not edit by hand; rerun the script instead._",
  "",
  if (PLACEHOLDER) c("> **The current source file contains placeholder values only (every value is 1).** The converter was built for its layout so that a file with real results can be converted by rerunning the script.", ""),
  "## 1. Source overview",
  "",
  sprintf("- File(s): %s", paste(sprintf("`%s`", unique(src$source_file)), collapse = ", ")),
  sprintf("- Data sheet: %s (detected by the header `Scenario | Region | Variable | Unit | years`). Sheets `regions` and `notes` document the layout.",
          paste(sprintf("`%s`", unique(src$source_sheet)), collapse = ", ")),
  sprintf("- Content: %d variables x %d region(s) x %d scenario(s), annual %s-%s.", uniqueN(src$source_variable),
          uniqueN(src$source_region), uniqueN(src$source_scenario), min(src$year), max(src$year)),
  "",
  "## 2. Output overview",
  "",
  sprintf("- File: `%s`", file.path(OUT_DIR_REL, OUT_CSV)),
  sprintf("- Rows: %d. Model `%s`, Scenario %s, Region(s): %s; years %s-%s (all, as reported).", nrow(out), MODEL,
          paste(sprintf("`%s`", unique(out$Scenario)), collapse = ", "), paste(sort(unique(out$Region)), collapse = ", "),
          min(out$Year), max(out$Year)),
  readme_template_note(),
  "",
  md_table(out[, .(rows = .N, items = uniqueN(Item), `example Item` = Item[1]), by = .(Variable, Unit)]),
  "",
  "## 3. Mappings",
  "",
  "OpenPROM has no crop detail, so `Item` is always `AGR` (agriculture) or `AGR|<sub-class>`, where the sub-class is the last part of the OpenPROM variable name (energy carrier or energy service), as reported.",
  "",
  md_table(rule_tab),
  "",
  "Variables per status:",
  "",
  md_table(var_cnt),
  "",
  "- Note: OpenPROM's sector is 'Agriculture, Fishing, Forestry'; fishing and forestry are included in all AGR values.",
  "- Scenario `BASELINE` -> `BASE` (GLOBIOM spelling of the baseline).",
  sprintf("- Regions are kept as reported. Codes that GLOBIOM does not use are proposed additions (%s). `OAS` and `SSA` exist in both models but are aggregates whose composition may differ; `World` is GLOBIOM's glossary code for the world (the comprehensive file uses `WLD`).",
          paste(reg_new, collapse = ", ")),
  "",
  "## 4. Transformations",
  "",
  "- Wide year columns reshaped to long format; all years kept.",
  "- **No value conversion.** Units as reported; only the label `1000 ha (irrigated)` is written as `1000 ha` (same unit).",
  "- Blank cells skipped (never set to zero).",
  "",
  "## 5. Proposed glossary additions",
  "",
  additions_md(res),
  "",
  "## 6. Not translated / open questions",
  "",
  "- `Price|Primary Energy|Biomass` and `|Oil`: economy-wide prices, not agriculture-specific - **open question** whether and how to report them.",
  "- `...|<service>|*` rows: placeholders of the template ('all corresponding fuels'); real files have one row per fuel and are translated as `ENUS` / `AGR|<service>|<fuel>`.",
  "- Per-variable decisions are in `mapping_log.csv`.",
  "",
  "## 7. Validation",
  "",
  paste(readme_validation_note(), "Annual years outside GLOBIOM's reporting years are allowed for this model."),
  "",
  validation_md(res),
  "",
  "## 8. Reproduction",
  "",
  "```",
  "Rscript scripts/OpenPROM_to_template.R",
  "```",
  "",
  "- Run from anywhere inside the repository (root found via `AgEnRes_R.Rproj`). R packages: `data.table`, `readxl`.",
  "- Replace or add the `.xlsx` in `inputs/OpenPROM/` (same layout) and rerun. New scenarios must be added to `scenario_map` (the run stops otherwise); new variables are translated by the rules in section 1 or reported as 'Not reviewed'."
)
write_lines_lf(readme, file.path(out_dir, "README.md"))
log_msg("== %s done ==", MODEL)
