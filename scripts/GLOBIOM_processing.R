# =============================================================================
# GLOBIOM processing functions used by scripts/GLOBIOM_to_template.R
#
# Reads OUTPUT_AG_REG from the GLOBIOM output GDX and maps it to the AgMIP
# reporting conventions (ported from the GLOBIOM_to_AgMIP routine, IIASA):
#   * Scenario = the second scenario dimension of the GDX (SCEN2: BASE, EPS-S1, ...)
#   * dry-matter series as <VAR>_dm, AgMIP units (MtCO2e, ktCH4, USD/t, ...)
#   * land cover from LAND2 (TOT, CRP, GRS, AGR, FOR, ECP, NLD, ONV)
#   * FOOD = food + waste, fertiliser = inorganic + organic where split
#   * FADN crop production costs (COST) appended from the exogenous add-on
# Pure functions only (no side effects), so they can be unit-tested.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

GLOBIOM_GDX_COLUMNS <- c("ALLRUN", "VAR_ID", "VAR_UNIT", "ANYREGION", "ITEM_AG",
                         "ALLSCEN1", "ALLSCEN2", "ALLSCEN3", "Year", "Value")

# Fixed reporting conventions
GLOBIOM_YEARS_KEEP <- seq(2000L, 2100L, by = 10L)
GLOBIOM_SOC_ITEMS  <- c("SOC", "SOCE", "SOCC", "SOCG", "SOCB")
GLOBIOM_EXCLUDE_ITEMS <- c(
  "Meat", "ALL", "CER", "SRP", "PULP", "MEAL", "BIOM", "LUC", "LUCF", "LUCC", "LUCR", "LUCR2",
  "LUCG", "LUCE", "LUCS", "PEAT", "IP_Biomass", "EW_Biomass",
  GLOBIOM_SOC_ITEMS # soil carbon flux, not yet in the AgMIP template
)
GLOBIOM_EXCLUDE_REGIONS <- c("ROW", "CHE")

# Scenario name = SCEN2, written to ALLSCEN3 so all code keyed on ALLSCEN3 uses
# the reported name. Stops if SCEN2 alone does not identify the scenarios.
compose_scenario <- function(d) {
  scens <- unique(data.table(s1 = as.character(d$ALLSCEN1), s2 = as.character(d$ALLSCEN2),
                             s3 = as.character(d$ALLSCEN3)))
  if (anyDuplicated(scens$s2)) {
    stop("SCEN2 is not unique per scenario, cannot report SCEN2 only: ",
         paste(scens[s2 %in% s2[duplicated(s2)], paste(s1, s2, s3, sep = "-")], collapse = ", "))
  }
  d$ALLSCEN3 <- as.character(d$ALLSCEN2)
  d
}

# Reads OUTPUT_AG_REG as a cleaned data.table (character codes, integer Year,
# numeric Value, World -> WLD, scenario composed). GAMS Eps comes in as 0.
read_output_ag_reg <- function(gdx_file) {
  d <- tryCatch(
    gamstransfer::readGDX(gdx_file, symbols = "OUTPUT_AG_REG"),
    error = function(e) stop("Failed to read OUTPUT_AG_REG from ", gdx_file, ": ", e$message)
  )$OUTPUT_AG_REG$records
  setDT(d)
  if (all(grepl("^uni_", names(d)[1:9]))) setnames(d, GLOBIOM_GDX_COLUMNS)
  d[, ALLRUN := NULL]
  fact_cols <- names(which(sapply(d, is.factor)))
  d[, (fact_cols) := lapply(.SD, function(x) trimws(as.character(x))), .SDcols = fact_cols]
  d <- compose_scenario(d)
  d[, ANYREGION := fifelse(ANYREGION == "World", "WLD", ANYREGION)]
  d[, Year := as.integer(Year)]
  d[, Value := as.numeric(Value)]
  d[]
}

# Fertiliser: inorganic + organic 5-letter codes (FRTIN+FRTON, FRTIP+FRTOP)
# where they exist in the GDX, otherwise the 4-letter total (FRTN, FRTP).
# Decided per item: the split is only reported for some items (e.g. TOT).
process_fert <- function(output_ag, split_ids, total_id, common_cols) {
  fert_by <- c("VAR_ID", "VAR_UNIT", "ANYREGION", "ITEM_AG", "ALLSCEN1", "ALLSCEN2", "ALLSCEN3", "Year")
  # a missing split component is a zero (GAMS does not write zeros to the GDX)
  split <- output_ag[VAR_ID %in% split_ids & VAR_UNIT == "1000 t", ..common_cols]
  split[, VAR_ID := total_id]
  split <- split[, .(Value = sum(Value)), by = fert_by]

  total <- output_ag[VAR_ID == total_id & VAR_UNIT == "1000 t", ..common_cols]
  total <- total[!split, on = setdiff(fert_by, "VAR_ID")]

  rbindlist(list(split, total), use.names = TRUE)
}

# Maps OUTPUT_AG_REG to the AgMIP reporting variables.
# Returns Model, Scenario, Region, Item, Variable, Year (integer), Unit, Value.
map_output_ag <- function(output_ag, model = "GLOBIOM") {
  varid_dm_map <- c(
    YILD = "YILD_dm", YIRF = "YIRF_dm", YIIR = "YIIR_dm", YEXO = "YEXO_dm",
    food = "FOOD_dm", Feed = "FEED_dm", OTHU = "OTHU_dm", IMPO = "IMPO_dm",
    EXPO = "EXPO_dm", Prod = "PROD_dm", CONS = "CONS_dm", NETT = "NETT_dm"
  )
  unit_map_dm <- c("1000 t dm" = "1000 t", "dm t/ha" = "t/ha")
  unit_map_other <- c(
    "Mln pers" = "Million", "Bn USD 2005" = "bn USD 2005 MER", "USD 2000 per ton" = "USD/t",
    "1000 ha" = "1000 ha", "t/ha" = "t/ha", "1000 t" = "1000 t", "km3" = "km3",
    "kcal/cap/d" = "kcal/cap/d", "Mt CO2eq/yr" = "MtCO2e", "USD/tCO2e" = "USD/tCO2e",
    "kg protein/ha" = "kg prt/ha"
  )
  unit_map_emis <- c("Mt CH4/yr" = "ktCH4", "Mt N2O/yr" = "ktN2O")
  dm_vars <- names(varid_dm_map)
  # FRTN/FRTP are built by process_fert only
  other_vars <- c(
    "POPT", "GDPT", "Area", "ARRF", "ARIR", "YILD", "YIRF", "YIIR", "YEXO",
    "Feed", "OTHU", "IMPO", "EXPO", "WATR", "CALO", "CALI", "Prod", "CONS",
    "NETT", "EMIS", "ECH4", "EN2O", "ECO2", "CTAX", "NBAL",
    "PBAL", "LYLD", "LYXO", "YEXO_I", "YEXO_R", "XPRP", "XPRX", "ABII"
  )
  emis_vars <- c("CH4", "N2O")
  common_cols <- c("VAR_ID", "VAR_UNIT", "ANYREGION", "ITEM_AG", "ALLSCEN1", "ALLSCEN2", "ALLSCEN3", "Year", "Value")
  by_cols <- c("VAR_ID", "VAR_UNIT", "ANYREGION", "ITEM_AG", "ALLSCEN1", "ALLSCEN2", "ALLSCEN3", "Year")

  # A: dry-matter series
  dm <- output_ag[VAR_ID %in% dm_vars & VAR_UNIT %in% c("1000 t dm", "dm t/ha"), ..common_cols]
  dm[, `:=`(VAR_ID = varid_dm_map[VAR_ID], VAR_UNIT = unit_map_dm[VAR_UNIT])]

  # B: other variables
  oth <- output_ag[VAR_ID %in% other_vars & VAR_UNIT %in% names(unit_map_other), ..common_cols]
  oth[, VAR_ID := fifelse(VAR_ID == "ECH4", "ECH4_eq", fifelse(VAR_ID == "EN2O", "EN2O_eq", VAR_ID))]
  oth[, VAR_UNIT := unit_map_other[VAR_UNIT]]

  # C: emissions in physical units
  emis <- output_ag[VAR_ID %in% emis_vars, ..common_cols]
  emis[, `:=`(VAR_ID = fifelse(VAR_ID == "CH4", "ECH4", "EN2O"), VAR_UNIT = unit_map_emis[VAR_UNIT],
              Value = Value * 1000)] # Mt -> kt

  # D: protein supply
  proto <- output_ag[VAR_ID == "NUTR" & VAR_UNIT == "gprot/cap/d", ..common_cols]
  proto[, `:=`(VAR_ID = "PROTO", VAR_UNIT = "gprt/cap/day")]
  proti <- output_ag[VAR_ID == "NTRI" & VAR_UNIT == "gprot/cap/d", ..common_cols]
  proti[, `:=`(VAR_ID = "PROTI", VAR_UNIT = "gprt/cap/day")]

  # E: land cover from LAND2
  land_noncrop_recode <- c(
    "0.TotLand" = "TOT", "3.Forest" = "FOR", "1.2.2.PlantationEnerCrp" = "ECP",
    "2.Grassland" = "GRS", "5.OthLand" = "NLD", "4.OthNatLand" = "ONV"
  )
  crop_items <- c("1.1.AnnualCrp", "1.2.1.PlantationFoodCrp", "1.3.OthCrpLnd")
  land_noncrop <- output_ag[VAR_ID == "LAND2" & ITEM_AG %in% names(land_noncrop_recode), ..common_cols]
  land_noncrop[, `:=`(VAR_ID = "LAND", ITEM_AG = land_noncrop_recode[ITEM_AG])]
  land_crp <- output_ag[VAR_ID == "LAND2" & ITEM_AG %in% crop_items, ..common_cols]
  land_crp[, `:=`(VAR_ID = "LAND", ITEM_AG = "CRP")]
  land_crp <- land_crp[, .(Value = sum(Value)), by = by_cols]
  land <- rbindlist(list(land_noncrop, land_crp), use.names = TRUE)
  land_agr <- land[ITEM_AG %in% c("CRP", "GRS"), .(Value = sum(Value)),
                   by = .(VAR_ID, VAR_UNIT, ANYREGION, ALLSCEN1, ALLSCEN2, ALLSCEN3, Year)]
  land_agr[, ITEM_AG := "AGR"]
  land <- rbindlist(list(land, land_agr), use.names = TRUE)

  # F: food (food + waste) and fertiliser
  food <- output_ag[VAR_ID %in% c("food", "WAST") & VAR_UNIT == "1000 t", ..common_cols]
  food[, VAR_ID := "FOOD"]
  food <- food[, .(Value = sum(Value)), by = by_cols]
  frtn <- process_fert(output_ag, c("FRTIN", "FRTON"), "FRTN", common_cols)
  frtp <- process_fert(output_ag, c("FRTIP", "FRTOP"), "FRTP", common_cols)

  all <- rbindlist(list(dm, oth, emis, proto, proti, food, land, frtp, frtn), use.names = TRUE)
  all[, .(Model = model, Scenario = ALLSCEN3, Region = ANYREGION, Item = ITEM_AG,
          Variable = VAR_ID, Year = Year, Unit = VAR_UNIT, Value = Value)]

  # SOC reporting -- soil carbon flux items are currently dropped via
  # GLOBIOM_EXCLUDE_ITEMS as they are not yet in the AgMIP template. To report
  # them, remove GLOBIOM_SOC_ITEMS from GLOBIOM_EXCLUDE_ITEMS and drop the
  # duplicate ECO2 (identical to EMIS for these items) and CTAX rows:
  # all <- all[!(Item %in% GLOBIOM_SOC_ITEMS & Variable %in% c("ECO2", "CTAX"))]
}

# FADN crop production costs (COST, USD 2000 per ha), appended unchanged.
# The add-on Scenario (BASE, EPS-S1, ...) matches SCEN2 = the reported scenario.
# Region is ISO3 (EU27), Item is crop|management|cost item. No aggregation and
# no filling: a missing row means no data, not zero cost.
fadn_cost_rows <- function(fadn_file, scenarios, model = "GLOBIOM") {
  fadn <- fread(fadn_file, colClasses = c(Year = "integer", value = "numeric"))
  stopifnot(all(fadn$Variable == "COST"), all(fadn$Unit == "USD 2000 per ha"))
  if (anyDuplicated(fadn, by = c("Region", "Year", "Scenario", "Variable", "Item")))
    stop("Duplicate keys in ", fadn_file)
  unmatched <- setdiff(unique(fadn$Scenario), scenarios)
  if (length(unmatched)) log_msg("FADN costs: scenario(s) %s not in the GDX - not reported", paste(unmatched, collapse = ", "))
  fadn[Scenario %in% scenarios, .(Model = model, Scenario, Region, Item, Variable, Year, Unit, Value = value)]
}

# Applies the fixed reporting filters.
filter_reporting <- function(dt) {
  dt[Year %in% GLOBIOM_YEARS_KEEP & !(Item %in% GLOBIOM_EXCLUDE_ITEMS) & !(Region %in% GLOBIOM_EXCLUDE_REGIONS)]
}
