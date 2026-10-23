# =============================================================================
# GLOBIOM (output GDX) -> common GLOBIOM-style reporting format
#
# Run from anywhere inside the repository (project root is found via
# AgEnRes_R.Rproj), e.g. from the repository root:
#   Rscript scripts/GLOBIOM_to_template.R [path/to/GLOBIOM_output.gdx]
#
# Source : inputs/GLOBIOM/merged_AgEnRes.gdx (OUTPUT_AG_REG, OUTPUT, REGION_AG_MAP)
#          data/GLOBIOM/FADN_costs/FADN_costs_country_USD2000_ha.csv (COST add-on, versioned)
#          data/GLOBIOM/LAMASUS_costs_country_20260420.csv (cost per ha for VAAD, versioned)
# Output : outputs/GLOBIOM/GLOBIOM_GLOBIOM_comprehensive.csv
#          outputs/GLOBIOM/mapping_log.csv
#          outputs/GLOBIOM/proposed_glossary_additions.csv
#          outputs/GLOBIOM/README.md
#
# Reads the GDX directly and reports GLOBIOM in the AgMIP conventions of the
# GLOBIOM_to_AgMIP routine (IIASA), see scripts/GLOBIOM_processing.R:
#   Scenario = SCEN2 (BASE, EPS-S1, EPS-S2, EPS-S3); dry-matter series as
#   <VAR>_dm; AgMIP units; World -> WLD; LAND, FOOD, FRTN/FRTP aggregates;
#   economic indicators (scripts/GLOBIOM_econ_calc.R); FADN crop production
#   costs (COST) appended unchanged. Replaces the earlier pass-through of the
#   hand-built inputs/template/OUTPUT_AG_REG.csv.
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
source(file.path(ROOT, "scripts", "GLOBIOM_processing.R"))

MODEL       <- "GLOBIOM"
args        <- commandArgs(trailingOnly = TRUE)
GDX_REL     <- if (length(args) >= 1) args[1] else file.path("inputs", "GLOBIOM", "merged_AgEnRes.gdx")
FADN_REL    <- file.path("data", "GLOBIOM", "FADN_costs", "FADN_costs_country_USD2000_ha.csv")
COSTS_REL   <- file.path("data", "GLOBIOM", "LAMASUS_costs_country_20260420.csv")
OUT_DIR_REL <- file.path("outputs", "GLOBIOM")
OUT_CSV     <- "GLOBIOM_GLOBIOM_comprehensive.csv"

# New codes: everything else is already in the GLOBIOM glossary / comprehensive file.
ADDITIONS <- additions_table(
  dimension = "Variable",
  code = c("VAAD", "BUDG", "BUDG_1stP", "BUDG_2ndP"),
  definition = c(
    "Value added of agriculture: revenue - production costs + subsidies (Item CRP, LSP, TOT); EU regions only.",
    "Agricultural subsidies (GLOBIOM BUDG) by sector (Item CRP, LSP, TOT); EU regions only.",
    "CAP Pillar 1 payments (direct payments, EAGF); Item TOT; EU regions only.",
    "CAP Pillar 2 payments (rural development, EAFRD); Item TOT; EU regions only."),
  source_label = c("computed from OUTPUT (XPRP, Prod, Area, Feed, BUDG) and exogenous costs per ha",
                   "OUTPUT BUDG", "OUTPUT BUDG, Pillar 1 payment codes", "OUTPUT BUDG, Pillar 2 payment codes"),
  model = MODEL
)

# -----------------------------------------------------------------------------
# 1. Read and map
# -----------------------------------------------------------------------------

log_msg("== %s converter ==", MODEL)
vocab <- load_template_vocab(ROOT)

GLOBIOM.file <- if (file.exists(GDX_REL)) GDX_REL else file.path(ROOT, GDX_REL)
costs.file   <- file.path(ROOT, COSTS_REL)
fadn.file    <- file.path(ROOT, FADN_REL)
for (f in c(GLOBIOM.file, costs.file, fadn.file)) if (!file.exists(f)) stop("Source not found: ", f)

t0 <- Sys.time()
output_ag <- read_output_ag_reg(GLOBIOM.file)
scenarios <- sort(unique(output_ag$ALLSCEN3))
log_msg("Source: %s - OUTPUT_AG_REG %d rows, scenarios %s (%.1fs)", GDX_REL, nrow(output_ag),
        paste(scenarios, collapse = ", "), as.numeric(difftime(Sys.time(), t0, units = "secs")))

core <- map_output_ag(output_ag, MODEL)
log_msg("OUTPUT_AG_REG mapped: %d rows", nrow(core))

# Economic indicators: region_61 -> reporting region from REGION_AG_MAP
region_map <- setDT(gamstransfer::readGDX(GLOBIOM.file, symbols = "REGION_AG_MAP")$REGION_AG_MAP$records)
region_map <- unique(region_map[, .(region = as.character(uni_2), region_61 = as.character(uni_3))])
suppressMessages(source(file.path(ROOT, "scripts", "GLOBIOM_econ_calc.R")))
Econ_tidy[, Model := MODEL]
log_msg("Economic indicators: %d rows", nrow(Econ_tidy))

fadn <- fadn_cost_rows(fadn.file, scenarios, MODEL)
log_msg("FADN costs: %d rows", nrow(fadn))

all_rows <- rbindlist(list(core, Econ_tidy, fadn), use.names = TRUE)
out <- filter_reporting(all_rows)
out[, Year := as.character(Year)]
setcolorder(out, vocab$columns)
log_msg("Rows: %d (%d before the reporting filters)", nrow(out), nrow(all_rows))

# -----------------------------------------------------------------------------
# 2. Validate and write
# -----------------------------------------------------------------------------

out_dir <- file.path(ROOT, OUT_DIR_REL)
res <- validate_and_write(out, vocab, file.path(out_dir, OUT_CSV), additions = ADDITIONS)

# -----------------------------------------------------------------------------
# 3. Mapping log: one row per output Variable x Unit
# -----------------------------------------------------------------------------

dm_src <- c(YILD_dm = "YILD", YIRF_dm = "YIRF", YIIR_dm = "YIIR", YEXO_dm = "YEXO", FOOD_dm = "food",
            FEED_dm = "Feed", OTHU_dm = "OTHU", IMPO_dm = "IMPO", EXPO_dm = "EXPO", PROD_dm = "Prod",
            CONS_dm = "CONS", NETT_dm = "NETT")
describe <- function(v) {
  if (v %in% names(dm_src)) return(c(dm_src[[v]], "OUTPUT_AG_REG", "dry-matter series renamed; unit label 1000 t dm / dm t/ha -> 1000 t / t/ha; value unchanged"))
  switch(v,
    ECH4_eq   = c("ECH4", "OUTPUT_AG_REG", "renamed; unit label Mt CO2eq/yr -> MtCO2e; value unchanged"),
    EN2O_eq   = c("EN2O", "OUTPUT_AG_REG", "renamed; unit label Mt CO2eq/yr -> MtCO2e; value unchanged"),
    ECH4      = c("CH4", "OUTPUT_AG_REG", "renamed; Mt CH4 -> kt CH4 (x 1000)"),
    EN2O      = c("N2O", "OUTPUT_AG_REG", "renamed; Mt N2O -> kt N2O (x 1000)"),
    PROTO     = c("NUTR", "OUTPUT_AG_REG", "gprot/cap/d rows only; renamed; value unchanged"),
    PROTI     = c("NTRI", "OUTPUT_AG_REG", "gprot/cap/d rows only; renamed; value unchanged"),
    FOOD      = c("food + WAST", "OUTPUT_AG_REG", "sum of food and waste (1000 t)"),
    LAND      = c("LAND2", "OUTPUT_AG_REG", "land cover classes recoded (TOT, FOR, ECP, GRS, NLD, ONV); CRP = sum of crop classes; AGR = CRP + GRS"),
    FRTN      = c("FRTIN + FRTON / FRTN", "OUTPUT_AG_REG", "inorganic + organic where the split exists for the item, otherwise FRTN"),
    FRTP      = c("FRTIP + FRTOP / FRTP", "OUTPUT_AG_REG", "inorganic + organic where the split exists for the item, otherwise FRTP"),
    VAAD      = c("XPRP, Prod, Area, Feed, BUDG", "OUTPUT + costs per ha", "computed: revenue - costs + subsidies, Mio -> bn"),
    BUDG      = c("BUDG", "OUTPUT", "summed by sector, Mio -> bn"),
    BUDG_1stP = c("BUDG (Pillar 1 codes)", "OUTPUT", "summed over payment codes, Mio -> bn"),
    BUDG_2ndP = c("BUDG (Pillar 2 codes)", "OUTPUT", "summed over payment codes, Mio -> bn"),
    COST      = c("COST", "FADN add-on", "appended unchanged"),
    c(v, "OUTPUT_AG_REG", "unit label mapped to AgMIP where it differs; value unchanged"))
}
lbl <- vocab$variable_labels
new_vars <- ADDITIONS[dimension == "Variable", code]
log_rows <- out[, .(n_output_rows = .N), by = .(Variable, Unit)][order(Variable, Unit)]
desc <- rbindlist(lapply(log_rows$Variable, function(v) as.list(setNames(describe(v), c("source_variable", "source_table_or_range", "transformation")))))
log_rows <- cbind(log_rows, desc)
var_log <- log_rows[, .(
  source_file = fifelse(source_table_or_range == "FADN add-on", FADN_REL,
                fifelse(Variable == "VAAD", paste(GDX_REL, COSTS_REL, sep = "; "), GDX_REL)),
  source_table_or_range, source_variable,
  source_label_or_definition = fifelse(is.na(lbl[Variable]), NA_character_, unname(lbl[Variable])),
  template_entry = Variable, template_column_or_field = "Variable", transformation,
  output_unit = Unit,
  mapping_status = fifelse(Variable %in% new_vars, "New code", "Direct"),
  confidence = "high", n_output_rows,
  notes = fifelse(Variable == "COST", "Item crop|management|cost item, USD 2000 per ha; EU27 ISO3 regions.",
          fifelse(Variable %in% new_vars, "EU regions only (exogenous costs cover EU countries).", NA_character_)))]
col_log <- data.table(
  source_file = GDX_REL, source_table_or_range = "OUTPUT_AG_REG domains",
  source_variable = c("(ALLSCEN2)", "(ANYREGION)", "(ITEM_AG)", "(VAR_ID)", "(Year)", "(VAR_UNIT)", "(value)", "(constant)"),
  template_entry = c(vocab$columns[2:8], MODEL),
  template_column_or_field = c(vocab$columns[2:8], "Model"),
  transformation = c("SCEN2 only (SCEN1, SCEN3 constant per scenario)", "World -> WLD; ROW, CHE dropped",
                     "kept; helper / SOC items dropped", "see variable rows", "2000-2100, 10-year steps",
                     "AgMIP unit labels", "see variable rows", "constant"),
  mapping_status = "Direct", confidence = "high")
write_mapping_log(rbindlist(list(col_log, var_log), fill = TRUE), file.path(out_dir, "mapping_log.csv"))

# -----------------------------------------------------------------------------
# 4. README
# -----------------------------------------------------------------------------

overview <- out[, .(rows = .N, regions = uniqueN(Region), years = paste(range(as.integer(Year)), collapse = "-")),
                by = .(Source = fifelse(Variable == "COST", "FADN add-on",
                                fifelse(Variable %in% new_vars, "economic indicators", "OUTPUT_AG_REG")))]
spot <- out[(Scenario == "EPS-S1" & Region == "AUT" & Item == "Whea" & Variable == "Area" & Year == "2020") |
            (Scenario == "EPS-S1" & Region == "AUT" & Item == "Whea|HI|Fertiliser" & Variable == "COST" & Year == "2030") |
            (Scenario == "BASE" & Region == "WLD" & Item == "TOT" & Variable == "ECH4_eq" & Year == "2020") |
            (Scenario == "BASE" & Region == "AUT" & Item == "TOT" & Variable == "VAAD" & Year == "2020")]

readme <- c(
  "# GLOBIOM -> common GLOBIOM-style reporting format",
  "",
  "_Generated by `scripts/GLOBIOM_to_template.R` - do not edit by hand; rerun the script instead._",
  "",
  "## 1. Source overview",
  "",
  sprintf("- GDX: `%s`, symbol `OUTPUT_AG_REG` (%d records), plus `OUTPUT` and `REGION_AG_MAP` for the economic indicators.", GDX_REL, nrow(output_ag)),
  sprintf("- Scenarios (SCEN2): %s.", paste(sprintf("`%s`", scenarios), collapse = ", ")),
  sprintf("- FADN crop production costs: `%s` (exogenous add-on, documented in `data/GLOBIOM/FADN_costs/README.txt`).", FADN_REL),
  sprintf("- Costs per ha for the value added: `%s` (EU countries).", COSTS_REL),
  "",
  "## 2. Output overview",
  "",
  sprintf("- File: `%s`", file.path(OUT_DIR_REL, OUT_CSV)),
  sprintf("- Rows: %d.", nrow(out)),
  "",
  md_table(overview),
  "",
  "- Columns fixed by `inputs/template/20260213_GLOBIOM_comprehensive.csv`: `Model, Scenario, Region, Item, Variable, Year, Unit, Value`; comma-separated, CRLF line endings, fields quoted only if they contain a comma.",
  "- GLOBIOM is reported in the **AgMIP conventions** of the GLOBIOM_to_AgMIP routine (the vocabulary of the comprehensive file), not as a pass-through of the raw GLOBIOM codes. Unlike the partner models, a few values are therefore derived (see section 4).",
  "- `Scenario` = the second scenario dimension of the GDX (SCEN2); SSP2 / RCP2.6 are not reported, as for the partner models.",
  "",
  "## 3. Mappings",
  "",
  "See `mapping_log.csv` (one row per output Variable x Unit).",
  "",
  "- Dry-matter series as `<VAR>_dm` (e.g. `YILD_dm` in `t/ha` = GLOBIOM `YILD` in `dm t/ha`); fresh-weight series keep the GLOBIOM name.",
  "- Unit labels: `Mt CO2eq/yr` -> `MtCO2e`, `USD 2000 per ton` -> `USD/t`, `Mln pers` -> `Million`, `Bn USD 2005` -> `bn USD 2005 MER`, `kg protein/ha` -> `kg prt/ha`, `gprot/cap/d` -> `gprt/cap/day`.",
  "- `ECH4`/`EN2O` in `Mt CO2eq/yr` -> `ECH4_eq`/`EN2O_eq`; `PROTO`/`PROTI` = `NUTR`/`NTRI` protein rows.",
  "- `Region`: `World` -> `WLD`; `ROW` and `CHE` not reported. Items `Meat`, `ALL`, `CER`, `LUC*`, `PEAT`, `BIOM`, `IP_Biomass`, ... not reported; soil carbon items (`SOC*`) not reported (not yet in the AgMIP template).",
  "- `COST`: Item `crop|management|cost item` (e.g. `Whea|HI|Fertiliser`), `USD 2000 per ha`, EU27 countries as ISO3; values appended unchanged. Do not sum over Items (`Total` is included).",
  "- `CTAX` is reported per emission source with the same price for each source; when comparing with a single carbon price take one source, do not sum.",
  "",
  "## 4. Transformations",
  "",
  "- `LAND` from `LAND2`: `CRP` = sum of the crop land classes, `AGR` = `CRP` + `GRS`.",
  "- `FOOD` = `food` + `WAST`.",
  "- `FRTN`/`FRTP` = inorganic + organic (`FRTIN`+`FRTON`, `FRTIP`+`FRTOP`) where the split exists for the item, otherwise GLOBIOM's `FRTN`/`FRTP`.",
  "- Physical CH4/N2O (if in the GDX): Mt -> kt.",
  "- Economic indicators (`scripts/GLOBIOM_econ_calc.R`), `bn USD 2005 MER`, EU regions only: `VAAD` = revenue - costs + subsidies (crops: price x production - cost per ha x area; livestock: price x production - feed and grassland costs), `BUDG` = subsidies, `BUDG_1stP`/`BUDG_2ndP` = CAP Pillar 1 / 2 payments (`scripts/GLOBIOM_CAP_BUDG_pillar_mapping.md`). GLOBIOM prices and subsidies are USD 2000 and the costs EUR; no deflator or exchange rate is applied.",
  "- GAMS `Eps` (zero but present) is read as 0.",
  "",
  "Spot check:",
  "",
  md_table(spot),
  "",
  "## 5. Proposed glossary additions",
  "",
  additions_md(res),
  "",
  "## 6. Validation",
  "",
  readme_validation_note(),
  "",
  validation_md(res),
  "",
  "## 7. Reproduction",
  "",
  "```",
  "Rscript scripts/GLOBIOM_to_template.R",
  "Rscript scripts/GLOBIOM_to_template.R path/to/other_GLOBIOM_output.gdx",
  "```",
  "",
  "- R packages: `data.table`, `readxl`, `gamstransfer`, `dplyr`, `tidyr`.",
  "- Inputs: the GLOBIOM output GDX in `inputs/GLOBIOM/` (not versioned); the FADN cost add-on (`data/GLOBIOM/FADN_costs/`) and the cost file (`data/GLOBIOM/`) are part of the repository. The run stops if SCEN2 does not identify the scenarios uniquely."
)
write_lines_lf(readme, file.path(out_dir, "README.md"))
log_msg("== %s done (%.1fs) ==", MODEL, as.numeric(difftime(Sys.time(), t0, units = "secs")))
