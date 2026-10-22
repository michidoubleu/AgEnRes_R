# =============================================================================
# FarmDyn -> common GLOBIOM-style reporting format
#
# Run from anywhere inside the repository (project root is found via
# AgEnRes_R.Rproj), e.g. from the repository root:
#   Rscript scripts/FarmDyn_to_template.R
#
# Source : inputs/FarmDyn/Farmdyn_template.xlsx, sheet "raw data"
# Output : outputs/FarmDyn/FarmDyn_GLOBIOM_comprehensive.csv
#          outputs/FarmDyn/proposed_glossary_additions.csv
#          outputs/FarmDyn/mapping_log.csv
#          outputs/FarmDyn/README.md
#
# Values are taken unchanged from the source; the only conversion is area
# ha -> 1000 ha (GLOBIOM's area unit). All mapping decisions are in the tables
# in section 1 - the parsing code does not need changing for new crops or
# columns.
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

MODEL       <- "FarmDyn"
SRC_REL     <- file.path("inputs", "FarmDyn", "Farmdyn_template.xlsx")
SHEET       <- "raw data"
OUT_DIR_REL <- file.path("outputs", "FarmDyn")
OUT_CSV     <- "FarmDyn_GLOBIOM_comprehensive.csv"

# -----------------------------------------------------------------------------
# 1. Mapping tables
# -----------------------------------------------------------------------------

# The farm (DEarable_k2, a German arable farm) is reported under Germany as
# agreed with the project lead (2026-10-19). It is ONE representative farm, not
# national totals.
REGION <- "DEU"

# Source scenario name -> Scenario (the model's own scenario names).
scenario_map <- data.table(
  source_scenario = c("base", "optimized combine"),
  Scenario        = c("base", "optimized_combine")
)

# FarmDyn crop -> crop code in Item: glossary code where one exists, otherwise
# a new code from NEW_CROP_CODES (shared with AgriPolis).
crop_map <- rbindlist(list(
  list("WinterWheat",  "Whea", "Winter wheat -> glossary Whea (wheat)."),
  list("WinterBarley", "Barl", "Winter barley -> glossary Barl (barley; no winter/spring split)."),
  list("WinterRape",   "Rape", "Winter oilseed rape -> glossary Rape (rapeseed)."),
  list("maizCorn",     "Corn", "Grain maize -> glossary Corn (maize)."),
  list("MaizSil",      "CorS", "Silage maize -> new code CorS (glossary Corn is grain maize)."),
  list("winterRye",    "RyeG", "Winter rye -> new code RyeG (no rye in the glossary)."),
  list("summerBeans",  "BeaF", "Summer (field) beans -> new code BeaF (glossary BeaD = dry beans; species/use not confirmed)."),
  list("sugarBeet",    "SugB", "Sugar beet -> new code SugB (glossary SugC is sugar cane)."),
  list("alfalfa",      "Alfa", "Alfalfa -> new code Alfa.")
))
setnames(crop_map, c("source_crop", "crop", "note"))

# Source columns of the per-crop cost blocks and of the hectare block.
#   item_part   : appended to the crop in Item (COST category, ENUS carrier);
#                 NA = Item is the crop only
#   output_unit : the source unit label (only Area is converted to 1000 ha)
#   factor      : 1 = value unchanged
FADN <- "Matches the FADN cost category of the glossary"
var_map <- rbindlist(list(
  list("seed",                      "Euro per ha", "COST", "Seeds",            "Euro per ha", 1, "Direct",     "high",   paste0(FADN, " 'Seeds' (ISED_V).")),
  list("Buy inputs - synt",         "Euro per ha", "COST", "Fertiliser",       "Euro per ha", 1, "Normalised", "medium", paste0("'synt' read as purchased synthetic (mineral) fertiliser. ", FADN, " 'Fertiliser' (IFERT_V).")),
  list("Buy inputs - diesel",       "Euro per ha", "COST", "Motor fuels",      "Euro per ha", 1, "Normalised", "high",   paste0(FADN, " 'Motor fuels' (IFULS_V).")),
  list("pesticides",                "Euro per ha", "COST", "Crop protection",  "Euro per ha", 1, "Normalised", "high",   paste0(FADN, " 'Crop protection' (IPROT_V).")),
  list("OtherDirectCosts",          "Euro per ha", "COST", "Other crop costs", "Euro per ha", 1, "Normalised", "medium", paste0(FADN, " 'Other crop costs' (ICRPOTH_V); content of the FarmDyn residual not documented.")),
  list("Buy inputs - hired labour", "Euro per ha", "COST", "Buy inputs - hired labour", "Euro per ha", 1, "New code", "high", "No FADN equivalent (FADN 'Labour' includes family labour) - new COST category, FarmDyn name kept."),
  list("Mach cost - crop",          "Euro per ha", "COST", "Mach cost - crop",          "Euro per ha", 1, "New code", "high", "Machinery cost of crop operations - new COST category, FarmDyn name kept."),
  list("Mach cost - fert appl",     "Euro per ha", "COST", "Mach cost - fert appl",     "Euro per ha", 1, "New code", "high", "Machinery cost of fertiliser application - new COST category, FarmDyn name kept."),
  list("Man appl cost",             "Euro per ha", "COST", "Man appl cost",             "Euro per ha", 1, "New code", "high", "Manure application cost - new COST category, FarmDyn name kept."),
  list("Mach inv",                  "Euro per ha", "COST", "Mach inv",                  "Euro per ha", 1, "New code", "high", "Machinery investment per ha - new COST category, FarmDyn name kept."),
  list("p_vcostC",                  "Euro per ha", "COST", "p_vcostC",                  "Euro per ha", 1, "New code", "low",  "Undocumented FarmDyn parameter (variable crop cost?) - may be a total of other columns; do not sum with the other categories until confirmed."),
  list("p_fcostC",                  "Euro per ha", "COST", "p_fcostC",                  "Euro per ha", 1, "New code", "low",  "Undocumented FarmDyn parameter (fixed crop cost?) - may overlap with other columns; do not sum until confirmed."),
  list("Diesel input - liter per ha", "liter per ha", "ENUS", "Diesel", "liter per ha", 1, "Direct", "high", "Diesel use per ha -> new variable ENUS (energy / fuel use), Item crop|Diesel."),
  list("min N input - kg N per ha", "kg N per ha", "FRTN", NA, "kg N per ha", 1, "Normalised", "high", "Mineral N per ha -> glossary FRTN (GLOBIOM reports FRTN as a total in 1000 t; per-ha value kept as reported)."),
  list("hectare per crop per farm", "ha", "Area", NA, "1000 ha", 1 / 1000, "Normalised", "high", "Crop area of the farm -> Area; ha / 1000 = 1000 ha (GLOBIOM's area unit).")
))
setnames(var_map, c("source_variable", "source_unit", "Variable", "item_part", "output_unit",
                    "factor", "status", "confidence", "notes"))

# Reviewed but not translated (outside the agreed soft-link scope or replaced).
excluded_vars <- rbindlist(list(
  list("min N input", "Total kg N per crop on the farm (no unit label). Per-ha column is reported instead (project lead, 2026-10-21)."),
  list("salestot", "Revenue - outside the agreed scope (soft-link variables only)."),
  list("salesperha", "Revenue per ha - outside the agreed scope."),
  list("income", "Income per ha - outside the agreed scope."),
  list("labour input - hours per ha", "Physical labour input - outside the agreed scope.")
))
setnames(excluded_vars, c("source_variable", "exclusion_reason"))

# Proposed glossary additions declared by this converter (only those actually
# used and not already GLOBIOM codes end up in proposed_glossary_additions.csv).
additions <- rbindlist(list(
  additions_table("Variable", NEW_VARIABLES$code, NEW_VARIABLES$definition, "", MODEL),
  additions_table("Item", NEW_CROP_CODES$code, NEW_CROP_CODES$definition,
                  crop_map[match(NEW_CROP_CODES$code, crop), fifelse(is.na(source_crop), "", source_crop)], MODEL),
  additions_table("Item", var_map[status == "New code", item_part],
                  var_map[status == "New code", sprintf("COST category: FarmDyn column '%s' (Euro per ha)", source_variable)],
                  var_map[status == "New code", source_variable], MODEL),
  additions_table("Item", "Diesel", "Energy carrier: diesel", "Diesel input - liter per ha", MODEL),
  additions_table("Unit", c("Euro per ha", "liter per ha", "kg N per ha"),
                  c("Euro per hectare (price base not stated by the model)", "Litres per hectare", "Kilogram nitrogen per hectare"),
                  c("Euro per ha (cost block label)", "Diesel input - liter per ha", "min N input - kg N per ha"), MODEL)
))

# Signature of a per-crop cost block header row and its expected unit label.
COST_HEADER_SIGNATURE <- c("seed", "pesticides", "salesperha")
COST_UNIT_LABEL <- "euro per ha"

# -----------------------------------------------------------------------------
# 2. Source parsing
# -----------------------------------------------------------------------------

# Per-crop cost blocks: header row has the scenario name in column A and
# "seed" in column B; the row above carries the unit label ("Euro per ha");
# data rows follow until column A is blank.
parse_cost_blocks <- function(m) {
  hdr_rows <- which(m[, 2] == "seed" & m[, 1] != "" &
                      apply(m, 1, function(r) all(COST_HEADER_SIGNATURE %in% r)))
  if (!length(hdr_rows)) stop("No per-crop cost block found in sheet '", SHEET, "'.")
  out <- list()
  for (r in hdr_rows) {
    scen <- m[r, 1]
    unit_label <- if (r > 1) m[r - 1, 2] else ""
    if (tolower(unit_label) != COST_UNIT_LABEL) {
      stop(sprintf("Cost block '%s' (row %d): expected unit label '%s' above the header, found '%s'.",
                   scen, r, COST_UNIT_LABEL, unit_label))
    }
    cols <- setdiff(which(m[r, ] != ""), 1)
    rows <- integer()
    i <- r + 1
    while (i <= nrow(m) && m[i, 1] != "") { rows <- c(rows, i); i <- i + 1 }
    rng <- sprintf("%s:%s", excel_cell(r, 1), excel_cell(max(rows), max(cols)))
    log_msg("  cost block '%s': rows %d-%d, %d crops x %d variables (%s)",
            scen, min(rows), max(rows), length(rows), length(cols), rng)
    for (j in cols) {
      out[[length(out) + 1]] <- data.table(
        source_scenario = scen, source_crop = m[rows, 1], source_variable = m[r, j],
        raw = m[rows, j], cell = excel_cell(rows, j), block = rng)
    }
  }
  d <- rbindlist(out)
  d[, value := parse_number(raw, "cost-block value")]
  d[]
}

# Hectare block: title "hectare per crop per farm" in column A, next row holds
# the scenario labels at the start column of each sub-table; each sub-table
# has columns crop | management | year | (GAMS '<empty>' dimension) | ha,
# closed by a "total" row.
parse_hectare_block <- function(m) {
  hb <- which(tolower(m[, 1]) == "hectare per crop per farm")
  if (length(hb) != 1) stop("Expected exactly one 'hectare per crop per farm' block, found ", length(hb))
  starts <- which(m[hb + 1, ] != "")
  out <- list()
  for (c0 in starts) {
    scen <- m[hb + 1, c0]
    rows <- integer()
    i <- hb + 2
    while (i <= nrow(m) && m[i, c0] != "" && tolower(m[i, 1]) != "total") { rows <- c(rows, i); i <- i + 1 }
    tot_row <- if (i <= nrow(m) && tolower(m[i, 1]) == "total") i else NA
    d <- data.table(source_scenario = scen, source_crop = m[rows, c0], source_mgmt = m[rows, c0 + 1],
                    year = m[rows, c0 + 2], raw = m[rows, c0 + 4], cell = excel_cell(rows, c0 + 4),
                    block = sprintf("%s:%s", excel_cell(hb, 1), excel_cell(max(rows), c0 + 4)),
                    source_variable = "hectare per crop per farm")
    d[, value := parse_number(raw, "hectare value")]
    if (!is.na(tot_row)) {
      tot <- parse_number(m[tot_row, c0 + 4], "hectare total")
      if (!is.na(tot) && abs(tot - sum(d$value, na.rm = TRUE)) > 1e-6 * max(1, tot)) {
        stop(sprintf("Hectare block '%s': crop sum %.6f differs from total row %.6f", scen,
                     sum(d$value, na.rm = TRUE), tot))
      }
      log_msg("  hectare block '%s': %d crops, sum %.3f ha = total row (%s)", scen, nrow(d),
              sum(d$value, na.rm = TRUE), excel_cell(tot_row, c0 + 4))
    }
    out[[length(out) + 1]] <- d
  }
  rbindlist(out)
}

# -----------------------------------------------------------------------------
# 3. Conversion
# -----------------------------------------------------------------------------

log_msg("== %s converter ==", MODEL)
vocab <- load_template_vocab(ROOT)
src <- file.path(ROOT, SRC_REL)
if (!file.exists(src)) stop("Source file not found: ", src)
log_msg("Source sheets: %s (using '%s')", paste(excel_sheets(src), collapse = ", "), SHEET)
m <- read_sheet_matrix(src, SHEET)

cost <- parse_cost_blocks(m)
ha   <- parse_hectare_block(m)

unknown_scen <- setdiff(unique(c(cost$source_scenario, ha$source_scenario)), scenario_map$source_scenario)
if (length(unknown_scen)) {
  stop("Source scenario(s) not in scenario_map: ", paste(unknown_scen, collapse = ", "),
       ". Add them to scenario_map in section 1.")
}
years <- unique(ha$year)
if (length(years) != 1) stop("Expected one year in the hectare block, found: ", paste(years, collapse = ", "))
YEAR <- years
log_msg("Reporting year (from hectare block, applied to all records): %s", YEAR)
log_msg("Management (hectare block): %s - not part of the Item (project lead, 2026-10-21)",
        paste(unique(ha$source_mgmt), collapse = ", "))

recs <- rbindlist(list(cost[, .(source_scenario, source_crop, source_variable, value, cell, block)],
                       ha[, .(source_scenario, source_crop, source_variable, value, cell, block)]))

reviewed <- c(var_map$source_variable, excluded_vars$source_variable)
unknown_vars  <- setdiff(unique(recs$source_variable), reviewed)
unknown_crops <- setdiff(unique(recs$source_crop), crop_map$source_crop)
if (length(unknown_vars))  log_msg("WARNING: source columns not reviewed (not translated): %s", paste(unknown_vars, collapse = ", "))
if (length(unknown_crops)) log_msg("WARNING: source crops not reviewed (not translated): %s", paste(unknown_crops, collapse = ", "))

x <- recs[var_map, on = "source_variable", nomatch = 0L]
x <- x[crop_map, on = "source_crop", nomatch = 0L]
n_blank <- x[is.na(value), .N]
if (n_blank) log_msg("Blank source cells skipped (not treated as zero): %d", n_blank)
x <- x[!is.na(value)]
x <- x[scenario_map, on = "source_scenario", nomatch = 0L]
x[, `:=`(
  Model  = MODEL,
  Region = REGION,
  Item   = fifelse(is.na(item_part), crop, paste(crop, item_part, sep = "|")),
  Unit   = output_unit,
  Year   = YEAR,
  Value  = value * factor
)]
out <- x[, vocab$columns, with = FALSE]
log_msg("Rows: %d (%s)", nrow(out), paste(out[, .N, by = Variable][, sprintf("%s=%d", Variable, N)], collapse = ", "))

# -----------------------------------------------------------------------------
# 4. Validate and write
# -----------------------------------------------------------------------------

out_dir <- file.path(ROOT, OUT_DIR_REL)
res <- validate_and_write(out, vocab, file.path(out_dir, OUT_CSV), additions = additions)
remove_legacy_output(out_dir, MODEL)

# -----------------------------------------------------------------------------
# 5. Mapping log
# -----------------------------------------------------------------------------

blocks <- unique(recs[, .(source_variable, block, source_scenario)])
block_txt <- blocks[, .(source_table_or_range = paste(sprintf("%s: %s", source_scenario, block), collapse = "; ")),
                    by = source_variable]

var_log <- block_txt[var_map, on = "source_variable"]
cnt <- x[, .N, by = source_variable]
var_log <- cnt[var_log, on = "source_variable"]
var_log[, `:=`(
  source_file = SRC_REL, source_sheet = SHEET,
  source_label_or_definition = sprintf("column '%s', all crops", source_variable),
  template_entry = sprintf("%s | %s", Variable, fifelse(is.na(item_part), "<crop>", paste0("<crop>|", item_part))),
  template_column_or_field = "Variable, Item, Unit, Value",
  transformation = fifelse(factor == 1, "value unchanged", sprintf("value x %s", format(factor, scientific = FALSE))),
  mapping_status = status, n_output_rows = fifelse(is.na(N), 0L, N), exclusion_reason = NA_character_)]

crop_log <- crop_map[, .(source_file = SRC_REL, source_sheet = SHEET, source_table_or_range = "all cost blocks and hectare block",
                         source_variable = "(crop row)", source_label_or_definition = sprintf("crop '%s'", source_crop),
                         template_entry = crop, template_column_or_field = "Item (crop part)",
                         mapping_status = fifelse(crop %in% NEW_CROP_CODES$code, "New code", "Normalised"),
                         confidence = "high", notes = note)]

exc_log <- block_txt[excluded_vars, on = "source_variable"][, .(
  source_file = SRC_REL, source_sheet = SHEET, source_table_or_range, source_variable,
  source_label_or_definition = sprintf("column '%s'", source_variable),
  mapping_status = "Excluded", n_output_rows = 0L, exclusion_reason)]

other <- data.table(
  source_file = SRC_REL,
  source_sheet = c(SHEET, SHEET, SHEET, "GLOBIOM selection"),
  source_table_or_range = c("hectare block, column 'management'",
                            "block 'per farm per ha' (DEarable_k2 rows, ~A27:H47)",
                            "'Level' GWP cells next to the farm block (~N34:Q41)",
                            "whole sheet"),
  source_variable = c("management (conv)", "farm-average per-ha values", "GWP (farm total)", "selected indicators / differences"),
  mapping_status = c("Not used", rep("Excluded", 3)), n_output_rows = 0L,
  exclusion_reason = c("Management is not part of the Item (project lead, 2026-10-21); all crops are 'conv' (conventional).",
                       "No crop dimension; crop-level values are reported instead.",
                       "GWP unit not documented in the source; labels of the 'Level' cells are ambiguous.",
                       "Repeats values from 'raw data' or differences derived from them; not translated to avoid double counting.")
)

not_reviewed <- rbindlist(list(
  if (length(unknown_vars)) data.table(source_file = SRC_REL, source_sheet = SHEET,
                                       source_variable = unknown_vars, mapping_status = "Not reviewed",
                                       n_output_rows = 0L, exclusion_reason = "New source column not present in var_map / excluded_vars"),
  if (length(unknown_crops)) data.table(source_file = SRC_REL, source_sheet = SHEET, source_variable = "(crop row)",
                                        source_label_or_definition = sprintf("crop '%s'", unknown_crops),
                                        mapping_status = "Not reviewed", n_output_rows = 0L,
                                        exclusion_reason = "New crop not present in crop_map")
), fill = TRUE)

map_log <- rbindlist(list(var_log, crop_log, exc_log, other, not_reviewed), fill = TRUE)
write_mapping_log(map_log, file.path(out_dir, "mapping_log.csv"))

# -----------------------------------------------------------------------------
# 6. README
# -----------------------------------------------------------------------------

summ <- out[, .(rows = .N, `example Item` = Item[1]), by = .(Variable, Unit)]
var_tab <- var_map[, .(`FarmDyn column` = source_variable, Variable,
                       Item = fifelse(is.na(item_part), "<crop>", paste0("<crop>|", item_part)),
                       Unit = output_unit, Conversion = fifelse(factor == 1, "none", "ha / 1000"),
                       Status = status, Note = notes)]
crop_tab <- crop_map[, .(`FarmDyn crop` = source_crop, `Crop code` = crop, Note = note)]

readme <- c(
  "# FarmDyn -> common GLOBIOM-style reporting format",
  "",
  "_Generated by `scripts/FarmDyn_to_template.R` - do not edit by hand; rerun the script instead._",
  "",
  "## 1. Source overview",
  "",
  sprintf("- File: `%s`", SRC_REL),
  sprintf("- Sheet used: `%s` (other sheets: %s - not used, see mapping log).", SHEET,
          paste(sprintf("`%s`", setdiff(excel_sheets(src), SHEET)), collapse = ", ")),
  sprintf("- Per-crop cost blocks (Euro per ha), one per scenario: %s",
          paste(unique(cost[, sprintf("`%s` %s", source_scenario, block)]), collapse = "; ")),
  sprintf("- Hectare block 'hectare per crop per farm', one sub-table per scenario: %s",
          paste(unique(ha[, sprintf("`%s` %s", source_scenario, block)]), collapse = "; ")),
  "- Content: one representative German arable farm (`DEarable_k2`), 9 crops, management `conv`, year 2010, two scenarios (`base`, `optimized combine`).",
  "",
  "## 2. Output overview",
  "",
  sprintf("- File: `%s`", file.path(OUT_DIR_REL, OUT_CSV)),
  sprintf("- Rows: %d. Model `%s`, Region `%s`, Year `%s`, Scenario %s.", nrow(out), MODEL, REGION, YEAR,
          paste(sprintf("`%s`", scenario_map$Scenario), collapse = ", ")),
  readme_template_note(),
  "",
  md_table(summ),
  "",
  "## 3. Mappings",
  "",
  md_table(var_tab),
  "",
  "- Every crop is reported, identified by its crop code in `Item`; costs and fuel use add a second part (`Whea|Seeds`, `Whea|Diesel`).",
  "- `COST` follows the glossary's FADN categories where a FarmDyn column matches one; other FarmDyn cost columns are kept as new categories under their FarmDyn names. Do **not** sum all categories: `p_vcostC` / `p_fcostC` are undocumented and may be totals of other columns.",
  "- Management (`conv` for all crops) is not part of the Item (decision of the project lead).",
  "",
  "### Crops",
  "",
  md_table(crop_tab),
  "",
  "### Scenarios and region",
  "",
  "- `base` -> `base`; `optimized combine` -> `optimized_combine`.",
  sprintf("- Region `%s`: the single farm `DEarable_k2` is reported under Germany (agreed with the project lead). Values are farm-level, **not** national totals.", REGION),
  "",
  "## 4. Transformations",
  "",
  "- Wide crop x column blocks reshaped to long format.",
  "- Values unchanged, with the source unit labels - except **Area**: ha / 1000 = 1000 ha, GLOBIOM's area unit.",
  "- Year 2010 is taken from the hectare block and applied to the cost blocks, which carry no year themselves.",
  "- Blank source cells are skipped, never treated as zero. Explicit zeros are kept.",
  "",
  "## 5. Proposed glossary additions",
  "",
  additions_md(res),
  "",
  "## 6. Not translated",
  "",
  md_table(excluded_vars[, .(`FarmDyn column` = source_variable, Reason = exclusion_reason)]),
  "",
  "- Farm-average block, GWP levels and sheet `GLOBIOM selection`: see `mapping_log.csv`.",
  "- Values describe one farm; aggregation to a regional/national level is up to the modelling team.",
  "",
  "## 7. Validation",
  "",
  readme_validation_note(),
  "",
  validation_md(res),
  "",
  "## 8. Reproduction",
  "",
  "```",
  "Rscript scripts/FarmDyn_to_template.R",
  "```",
  "",
  "- Run from anywhere inside the repository (root found via `AgEnRes_R.Rproj`). R packages: `data.table`, `readxl`.",
  "- Rerunning overwrites the outputs deterministically. A new file with the same layout is converted without code changes; new crops / columns are reported as 'Not reviewed' and new scenarios stop the run until added to the tables in section 1."
)
write_lines_lf(readme, file.path(out_dir, "README.md"))
log_msg("== %s done ==", MODEL)
