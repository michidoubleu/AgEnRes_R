# =============================================================================
# AgriPolis -> GLOBIOM comprehensive template
#
# Run from anywhere inside the repository (project root is found via
# AgEnRes_R.Rproj), e.g. from the repository root:
#   Rscript scripts/AgriPolis_to_template.R
#
# Source : every folder below inputs/AgriPolis/ that contains
#          farm_production.dat (currently "outputfiles_REF Oct 15-101")
# Output : outputs/AgriPolis/AgriPolis_GLOBIOM_comprehensive.csv
#          outputs/AgriPolis/mapping_log.csv
#          outputs/AgriPolis/README.md
#
# AgriPolis is an agent-based farm-level model. As agreed with the project
# lead, results are NOT aggregated: every farm becomes its own Region ID built
# from replication, farm_ID and farm_name (2026-10-19). The AgriPolis
# iteration is the model's time dimension; Year = 2020 + iteration (0 -> 2020, annual steps).
# (2026-10-21).
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

MODEL       <- "AgriPolis"
SRC_DIR_REL <- file.path("inputs", "AgriPolis")
PROD_FILE   <- "farm_production.dat"
OUT_DIR_REL <- file.path("outputs", "AgriPolis")
OUT_CSV     <- "AgriPolis_GLOBIOM_comprehensive.csv"

# -----------------------------------------------------------------------------
# 1. Mapping tables
# -----------------------------------------------------------------------------

# Region ID per farm (user-defined, not a template region code).
make_region_id <- function(replication, farm_ID, farm_name) {
  sprintf("AgriPolis_r%s_f%s_%s", replication, farm_ID, farm_name)
}
REGION_REGEX <- "^AgriPolis_r[0-9]+_f[0-9]+_.+$"

# Year = FIRST_YEAR + iteration: iteration 0 = 2020, one-year time steps (project lead,
# 2026-10-21; the calendar years are not stated in the source files).
FIRST_YEAR <- 2020L
YEAR_REGEX <- "^[0-9]{4}$"   # annual years between GLOBIOM's 10-year steps

# Source scenario -> template Scenario (the model's own scenario name).
scenario_map <- data.table(
  source_scenario = "REF Oct 15",
  Scenario        = "REF Oct 15"
)

# Columns of farm_production.dat holding land-use activity levels in ha.
# (Verified in-script: they sum to the farm's 'ha' column.)
LAND_USE_COLS <- c("BARLEY", "WINTER_WHEAT", "RAPE_SEED", "SUGAR_BEETS", "PROTEIN_PLANTS",
                   "MAIZE_SILAGE", "LEY", "POTATOES", "RYE", "RYE_BIOGAS", "GPS",
                   "GRASSILAGE_INT", "GRASSILAGE_EXT", "PORTIONSWEIDE", "UMTRIEBSWEIDE",
                   "STANDWEIDE", "SET_ASIDE", "IDLE_ARABLE", "IDLE_GRASS")

# Land-use column -> crop code in Item: glossary code where one exists,
# otherwise a new code from NEW_CROP_CODES (shared with FarmDyn).
crop_map <- rbindlist(list(
  list("BARLEY",         "Barl", "Barley -> glossary Barl."),
  list("WINTER_WHEAT",   "Whea", "Winter wheat -> glossary Whea."),
  list("RAPE_SEED",      "Rape", "Rapeseed -> glossary Rape."),
  list("POTATOES",       "Pota", "Potatoes -> glossary Pota."),
  list("SUGAR_BEETS",    "SugB", "Sugar beet -> new code SugB (glossary SugC is sugar cane)."),
  list("RYE",            "RyeG", "Rye -> new code RyeG (no rye in the glossary)."),
  list("RYE_BIOGAS",     "RyeB", "Rye for biogas -> new code RyeB."),
  list("PROTEIN_PLANTS", "Prot", "Protein crops (not specified) -> new code Prot."),
  list("MAIZE_SILAGE",   "CorS", "Silage maize -> new code CorS (glossary Corn is grain maize)."),
  list("GPS",            "WCSi", "Whole-crop silage (Ganzpflanzensilage) -> new code WCSi."),
  list("LEY",            "LeyG", "Ley / temporary grass -> new code LeyG."),
  list("GRASSILAGE_INT", "GrSI", "Grass silage, intensive -> new code GrSI."),
  list("GRASSILAGE_EXT", "GrSE", "Grass silage, extensive -> new code GrSE."),
  list("PORTIONSWEIDE",  "PasS", "Strip-grazing pasture -> new code PasS."),
  list("UMTRIEBSWEIDE",  "PasR", "Rotational-grazing pasture -> new code PasR."),
  list("STANDWEIDE",     "PasC", "Continuous-grazing pasture -> new code PasC."),
  list("SET_ASIDE",      "SetA", "Set-aside -> new code SetA."),
  list("IDLE_ARABLE",    "IdlA", "Idle arable land -> new code IdlA."),
  list("IDLE_GRASS",     "IdlG", "Idle grassland -> new code IdlG.")
))
setnames(crop_map, c("source_variable", "item", "note"))
crop_map[, status := fifelse(item %in% NEW_CROP_CODES$code, "New code", "Normalised")]

# Proposed glossary additions declared by this converter.
additions <- rbindlist(list(
  additions_table("Item", NEW_CROP_CODES$code, NEW_CROP_CODES$definition,
                  crop_map[match(NEW_CROP_CODES$code, item), fifelse(is.na(source_variable), "", source_variable)], MODEL)
))

AREA <- list(Variable = "Area", output_unit = "1000 ha", source_unit = "ha", factor = 1 / 1000)

# Remaining farm_production.dat columns, classified for the mapping log.
other_col_rules <- rbindlist(list(
  list("^(scenario|replication|iteration|farm_ID|farm_name)$", "Identifier", "Used to build Scenario, Region ID and Year."),
  list("^ha$", "Identifier", "Farm size (ha); used for the unit cross-check of the land-use columns."),
  list("^(SOWS|FATTENING_PIGS|BULL_|SUCKLER_COW|DAIRY_COW|HEIFER_)", "Excluded",
       "Livestock activity (head/places) - outside the agreed scope (soft-link variables only; GLOBIOM Anim would be in 1000 TLU)."),
  list("^(DAIRY_CALF|SUCKLER_CALF)_", "Excluded", "Calf trade (head) - outside the agreed scope."),
  list("^BIOGAS", "Excluded", "Biogas plant activities - outside the agreed scope."),
  list("^MANURE_", "Excluded", "Manure trade - outside the agreed scope."),
  list("(QUOTA|PREM|Premium|TRANCH|HECTARE$|modulation)", "Excluded", "Policy premiums / quota - outside the agreed scope."),
  list("^(ST_BORROW_CAP|EC_INTEREST|V_HIRED_LABOUR|V_OFF_FARM_LAB|AGRI_SERVICES)$", "Excluded", "Finance / labour activities - outside the agreed scope."),
  list("^EXCESS_LU$", "Excluded", "Excess livestock units - outside the agreed scope.")
))
setnames(other_col_rules, c("pattern", "status", "reason"))

# Other files in each run folder (not used for the output).
other_files <- rbindlist(list(
  list("farm_standard_indicators.dat", "rent_Arable_Land / rent_Grazing_Land",
       "Land rent - outside the agreed scope. (Values are identical across farms and non-zero for farms without rented land, so the definition is unclear.) The file's header has 61 names but 62 data fields (trailing tab) - read_dat_table() handles this."),
  list("farm_standard_indicators.dat", "other farm indicators",
       "Farm-level economic / structural indicators (revenue, profit, overheads, assets, labour ...) - outside the agreed scope; no crop dimension."),
  list("farm_investment.dat", "investment counts",
       "Number of investments by type (stables, machinery, biogas) - outside the agreed scope."),
  list("sec_prices.dat / sec_exprices.dat", "sector prices per activity",
       "Prices per activity (e.g. BARLEY 1107) - would fit PRIC with the crop in Item, but the unit (per ha or per t, currency) is not documented in the files. OPEN QUESTION for the AgriPolis team."),
  list("sector.dat", "sector aggregates per period",
       "Region-level aggregates computed by AgriPolis; excluded because the agreed output is farm-level only (no aggregation).")
))
setnames(other_files, c("file", "variable", "reason"))

# -----------------------------------------------------------------------------
# 2. Source discovery and parsing
# -----------------------------------------------------------------------------

log_msg("== %s converter ==", MODEL)
vocab <- load_template_vocab(ROOT)

src_root <- file.path(ROOT, SRC_DIR_REL)
prod_files <- sort(list.files(src_root, pattern = paste0("^", PROD_FILE, "$"), recursive = TRUE, full.names = TRUE))
if (!length(prod_files)) stop("No ", PROD_FILE, " found below ", src_root)
log_msg("Run folders found: %d", length(prod_files))

ID_COLS <- c("scenario", "replication", "iteration", "farm_ID", "farm_name", "ha")

read_run <- function(path) {
  d <- read_dat_table(path)
  miss <- setdiff(c(ID_COLS, LAND_USE_COLS), names(d))
  if (length(miss)) stop(basename(path), ": missing columns ", paste(miss, collapse = ", "))
  rel <- substring(normalizePath(path, winslash = "/"), nchar(normalizePath(ROOT, winslash = "/")) + 2)
  d[, source_file := rel]
  d[, source_row := .I + 1L]   # +1 for the header line
  d
}
prod <- rbindlist(lapply(prod_files, read_run), fill = TRUE)

# Identifier checks
for (cl in c("replication", "iteration", "farm_ID")) {
  if (any(!grepl("^[0-9]+$", prod[[cl]]))) stop("Non-integer values in ", cl)
}
dups <- prod[, .N, by = .(scenario, replication, iteration, farm_ID)][N > 1]
if (nrow(dups)) stop(nrow(dups), " duplicate scenario/replication/iteration/farm_ID records in ", PROD_FILE)
names_per_id <- prod[, uniqueN(farm_name), by = .(scenario, replication, farm_ID)][V1 > 1]
if (nrow(names_per_id)) log_msg("NOTE: %d farm IDs change farm_name across iterations - they get one Region ID per name.", nrow(names_per_id))
unknown_scen <- setdiff(unique(prod$scenario), scenario_map$source_scenario)
if (length(unknown_scen)) stop("Source scenario(s) not in scenario_map: ", paste(unknown_scen, collapse = ", "),
                               ". Add them to scenario_map in section 1.")
log_msg("Farm records: %d (scenarios: %s; replications: %s; iterations: %s)", nrow(prod),
        paste(unique(prod$scenario), collapse = ", "), paste(sort(unique(prod$replication)), collapse = ","),
        paste(sort(as.integer(unique(prod$iteration))), collapse = ","))

# Unit cross-check: land-use columns are hectares if they add up to 'ha'
lu <- prod[, lapply(.SD, parse_number), .SDcols = LAND_USE_COLS]
lu_sum <- rowSums(lu, na.rm = TRUE)
farm_ha <- parse_number(prod$ha)
dev <- abs(lu_sum - farm_ha)
if (any(dev > 0.01)) {
  stop(sum(dev > 0.01), " farm records where land-use columns do not sum to 'ha' (max deviation ",
       signif(max(dev), 4), ") - hectare unit assumption does not hold.")
}
log_msg("Cross-check passed: land-use columns sum to farm 'ha' for all records (max deviation %.4f ha).", max(dev))

# -----------------------------------------------------------------------------
# 3. Conversion
# -----------------------------------------------------------------------------

inc <- crop_map[!is.na(item)]
long <- melt(prod, id.vars = c(ID_COLS, "source_file", "source_row"), measure.vars = inc$source_variable,
             variable.name = "source_variable", value.name = "raw", variable.factor = FALSE)
long[, value := parse_number(raw, "farm_production value")]
n_blank <- sum(is.na(long$value))
if (n_blank) log_msg("Blank source cells skipped (not treated as zero): %d", n_blank)
long <- long[!is.na(value)]
long <- long[inc, on = "source_variable", nomatch = 0L]
long <- long[scenario_map, on = c(scenario = "source_scenario"), nomatch = 0L]
long[, `:=`(Region = make_region_id(replication, farm_ID, farm_name), Year = as.character(FIRST_YEAR + as.integer(iteration)))]

# Land uses sharing a crop code would be summed (currently all codes are 1:1).
out <- long[, .(Value = sum(value) * AREA$factor),
            by = .(Scenario, Region, Item = item, Year)]
out[, `:=`(Model = MODEL, Variable = AREA$Variable, Unit = AREA$output_unit)]
out <- out[, vocab$columns, with = FALSE]
log_msg("Mapped rows: %d (%d farm records x %d Items; %d with value 0)", nrow(out), nrow(prod),
        uniqueN(inc$item), sum(out$Value == 0))

# -----------------------------------------------------------------------------
# 4. Validate and write
# -----------------------------------------------------------------------------

out_dir <- file.path(ROOT, OUT_DIR_REL)
res <- validate_and_write(out, vocab, file.path(out_dir, OUT_CSV),
                          additions = additions, allowed_region_regex = REGION_REGEX, allowed_year_regex = YEAR_REGEX)
remove_legacy_output(out_dir, MODEL)

# -----------------------------------------------------------------------------
# 5. Mapping log
# -----------------------------------------------------------------------------

src_files_txt <- paste(unique(prod$source_file), collapse = "; ")
counts <- long[, .N, by = source_variable]

crop_log <- copy(crop_map)
crop_log <- counts[crop_log, on = "source_variable"]
crop_log[, `:=`(
  source_file = src_files_txt, source_sheet = NA,
  source_table_or_range = sprintf("column '%s', all data rows", source_variable),
  source_label_or_definition = sprintf("land-use activity level of '%s' per farm record", source_variable),
  source_unit = "ha",
  template_entry = sprintf("Area | %s", item),
  template_column_or_field = "Variable, Item, Unit, Value; Region = farm ID; Year = 2020 + iteration",
  transformation = "value / 1000 (ha -> 1000 ha, GLOBIOM's area unit); wide -> long",
  output_unit = "1000 ha", confidence = "high",
  mapping_status = status, n_output_rows = fifelse(is.na(N), 0L, N), notes = note)]

prod_cols <- setdiff(names(prod), c("source_file", "source_row", LAND_USE_COLS))
col_class <- rbindlist(lapply(prod_cols, function(cl) {
  hit <- other_col_rules[vapply(pattern, grepl, logical(1), x = cl)][1]
  data.table(source_variable = cl,
             mapping_status = if (is.na(hit$status)) "Not reviewed" else hit$status,
             reason = if (is.na(hit$reason)) "Column not classified in other_col_rules" else hit$reason)
}))
col_log <- col_class[, .(source_file = src_files_txt, source_table_or_range = sprintf("column '%s'", source_variable),
                         source_variable, mapping_status, n_output_rows = 0L,
                         notes = fifelse(mapping_status == "Identifier", reason, NA_character_),
                         exclusion_reason = fifelse(mapping_status == "Identifier", NA_character_, reason))]
if (any(col_class$mapping_status == "Not reviewed")) {
  log_msg("WARNING: columns not reviewed: %s", paste(col_class[mapping_status == "Not reviewed", source_variable], collapse = ", "))
}

file_log <- other_files[, .(source_file = file, source_variable = variable, mapping_status = "Excluded",
                            n_output_rows = 0L, exclusion_reason = reason)]

map_log <- rbindlist(list(crop_log, col_log, file_log), fill = TRUE)
write_mapping_log(map_log, file.path(out_dir, "mapping_log.csv"))

# -----------------------------------------------------------------------------
# 6. README
# -----------------------------------------------------------------------------

ex_rows <- head(out[Value > 0][order(Region, Year, Item)], 4)
summ <- out[, .(rows = .N, zero_values = sum(Value == 0), farms = uniqueN(Region),
                years = paste(range(as.integer(Year)), collapse = "-")), by = .(Variable, Unit, Item)]
crop_tab <- crop_map[, .(`AgriPolis column` = source_variable, `Crop code` = item,
                         Status = status, Note = note)]

readme <- c(
  "# AgriPolis -> GLOBIOM comprehensive template",
  "",
  "_Generated by `scripts/AgriPolis_to_template.R` - do not edit by hand; rerun the script instead._",
  "",
  "## 1. Source overview",
  "",
  sprintf("- Run folder(s): %s", paste(sprintf("`%s`", dirname(unique(prod$source_file))), collapse = ", ")),
  sprintf("- File used: `%s` (tab-separated, one row per farm x iteration).", PROD_FILE),
  "- Files inspected but not used: `farm_standard_indicators.dat`, `farm_investment.dat`, `sec_prices.dat`, `sec_exprices.dat`, `sector.dat` (reasons in section 5).",
  sprintf("- Content: scenario `%s`, replication(s) %s, iterations %s, %d farm records (%d distinct farm IDs).",
          paste(unique(prod$scenario), collapse = ", "), paste(sort(unique(prod$replication)), collapse = ", "),
          paste(range(as.integer(prod$iteration)), collapse = "-"), nrow(prod), uniqueN(prod$farm_ID)),
  "- The modelled region is not stated in the files (presumably a German sub-region).",
  "",
  "## 2. Output overview",
  "",
  sprintf("- File: `%s`", file.path(OUT_DIR_REL, OUT_CSV)),
  sprintf("- Rows: %d; columns (template order): %s", nrow(out), paste(vocab$columns, collapse = ", ")),
  readme_template_note(),
  "",
  md_table(summ),
  "",
  "Example rows:",
  "",
  md_table(ex_rows),
  "",
  "## 3. Mappings",
  "",
  "- **Area** (1000 ha) per crop / land use, farm and iteration, from all 19 land-use activity columns of `farm_production.dat`. Glossary crop codes where they exist, otherwise new codes (shared with FarmDyn; see section 5).",
  "- **COST / ENUS / FRTN / PRIC:** the delivered files contain no per-crop costs, fuel use or N use. Sector prices per activity exist (`sec_prices.dat`) but their unit is not documented - open question for the AgriPolis team. Once reported, they follow FarmDyn's structure (`COST` Item `crop|category`, `ENUS` Item `crop|Diesel`, `FRTN` Item `crop`, `PRIC` Item `crop`).",
  "",
  md_table(crop_tab),
  "",
  "- **Region** = `AgriPolis_r<replication>_f<farm_ID>_<farm_name>` (e.g. `AgriPolis_r0_f0_CROP-FIF1`). User-authorised farm-level ID, not a template region code; the validator accepts it only for this model and reports it as a warning. Aggregation to a real region is left to the AgriPolis team.",
  sprintf("- **Year** = %d + AgriPolis `iteration` (iteration 0 = %d, one-year time steps, so iterations %s map to %s), as set by the project lead; the source files give no calendar years. Years between GLOBIOM's 10-year steps are accepted for this model and reported as a warning.", FIRST_YEAR, FIRST_YEAR, paste(range(as.integer(prod$iteration)), collapse = "-"), paste(FIRST_YEAR + range(as.integer(prod$iteration)), collapse = "-")),
  sprintf("- **Model** `%s`; **Scenario**: %s (the model's own scenario name; `REF` = reference run).", MODEL,
          paste(scenario_map[, sprintf("`%s` -> `%s`", source_scenario, Scenario)], collapse = "; ")),
  "",
  "## 4. Transformations",
  "",
  "- Wide farm x activity table reshaped to long format (one row per farm x iteration x Item).",
  "- Only conversion: ha -> 1000 ha (/1000), GLOBIOM's area unit. Unit verified: the 19 land-use columns sum to the farm's `ha` for every record (the script stops otherwise).",
  "- No aggregation across farms or iterations, no filtering or imputation. Explicit zeros (crop not grown) are kept as reported; blank cells would be skipped, not set to zero.",
  "",
  "## 5. Proposed glossary additions",
  "",
  additions_md(res),
  "",
  "## 6. Not translated",
  "",
  if (nrow(summ[zero_values == rows])) sprintf("- %s: zero in every farm record of this run (crop not grown); kept as reported.",
                                               paste(sprintf("`%s`", summ[zero_values == rows, Item]), collapse = ", ")),
  "- Livestock (sows, pigs, cattle), farm economics, investments and land rent are outside the agreed scope (soft-link variables only).",
  "- Sector prices (`sec_prices.dat`): unit not documented - not translated until the AgriPolis team confirms it.",
  "- `sector.dat` holds AgriPolis' own regional aggregates; excluded because only farm-level output was requested.",
  "- All column-level decisions are in `mapping_log.csv`.",
  "",
  "## 7. Validation",
  "",
  paste(readme_validation_note(), "Farm-ID Regions and iteration Years are allowed for this model only."),
  "",
  validation_md(res),
  "",
  "## 8. Reproduction",
  "",
  "```",
  "Rscript scripts/AgriPolis_to_template.R",
  "```",
  "",
  "- Run from anywhere inside the repository (root found via `AgEnRes_R.Rproj`).",
  "- R packages: `data.table`, `readxl` (the latter for the template glossary).",
  "- Every folder below `inputs/AgriPolis/` containing `farm_production.dat` is converted; new scenarios must be added to `scenario_map` (the run stops otherwise). Rerunning overwrites the outputs deterministically."
)
write_lines_lf(readme, file.path(out_dir, "README.md"))
log_msg("== %s done ==", MODEL)
