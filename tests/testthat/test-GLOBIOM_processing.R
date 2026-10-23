# Run from the repository root:
#   Rscript -e "testthat::test_dir('tests/testthat')"

library(testthat)

root <- normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "AgEnRes_R.Rproj"))) root <- normalizePath(getwd(), winslash = "/")
source(file.path(root, "scripts", "shared_conversion_helpers.R"))
source(file.path(root, "scripts", "GLOBIOM_processing.R"))

# Minimal OUTPUT_AG_REG records, as returned by read_output_ag_reg()
ag <- function(VAR_ID, VAR_UNIT, ITEM_AG, Value, ANYREGION = "AUT", s2 = "BASE", Year = 2020L) {
  data.table(VAR_ID = VAR_ID, VAR_UNIT = VAR_UNIT, ANYREGION = ANYREGION, ITEM_AG = ITEM_AG,
             ALLSCEN1 = "SSP2", ALLSCEN2 = s2, ALLSCEN3 = s2, Year = Year, Value = Value)
}

test_that("compose_scenario reports SCEN2 and stops if SCEN2 is not unique", {
  d <- data.table(ALLSCEN1 = "SSP2", ALLSCEN2 = c("BASE", "EPS-S1"), ALLSCEN3 = "scenRCP2p6")
  expect_equal(compose_scenario(d)$ALLSCEN3, c("BASE", "EPS-S1"))
  d2 <- data.table(ALLSCEN1 = "SSP2", ALLSCEN2 = "BASE", ALLSCEN3 = c("scenRCP2p6", "scenRCP4p5"))
  expect_error(compose_scenario(d2), "SCEN2 is not unique")
})

test_that("process_fert uses the inorganic + organic split per item, else the total", {
  d <- rbind(ag("FRTIN", "1000 t", "TOT", 3), ag("FRTON", "1000 t", "TOT", 1),
             ag("FRTN", "1000 t", "TOT", 99), ag("FRTN", "1000 t", "Whea", 2))
  cc <- c("VAR_ID", "VAR_UNIT", "ANYREGION", "ITEM_AG", "ALLSCEN1", "ALLSCEN2", "ALLSCEN3", "Year", "Value")
  r <- process_fert(d, c("FRTIN", "FRTON"), "FRTN", cc)
  expect_equal(nrow(r), 2)
  expect_equal(r[ITEM_AG == "TOT", Value], 4)   # split wins over the 4-letter total
  expect_equal(r[ITEM_AG == "Whea", Value], 2)  # no split -> 4-letter total
  expect_true(all(r$VAR_ID == "FRTN"))
})

test_that("map_output_ag applies the AgMIP conventions", {
  d <- rbind(
    ag("YILD", "dm t/ha", "Whea", 5), ag("YILD", "t/ha", "Whea", 6),
    ag("ECH4", "Mt CO2eq/yr", "TOT", 10), ag("CH4", "Mt CH4/yr", "TOT", 2),
    ag("food", "1000 t", "Whea", 7), ag("WAST", "1000 t", "Whea", 1),
    ag("LAND2", "1000 ha", "1.1.AnnualCrp", 10), ag("LAND2", "1000 ha", "1.3.OthCrpLnd", 5),
    ag("LAND2", "1000 ha", "2.Grassland", 20), ag("NUTR", "gprot/cap/d", "TOT", 80))
  r <- map_output_ag(d)
  expect_equal(names(r), c("Model", "Scenario", "Region", "Item", "Variable", "Year", "Unit", "Value"))
  expect_equal(r[Variable == "YILD_dm", .(Unit, Value)], data.table(Unit = "t/ha", Value = 5))
  expect_equal(r[Variable == "YILD", Value], 6)
  expect_equal(r[Variable == "ECH4_eq", Unit], "MtCO2e")
  expect_equal(r[Variable == "ECH4", .(Unit, Value)], data.table(Unit = "ktCH4", Value = 2000))  # Mt -> kt
  expect_equal(r[Variable == "FOOD", Value], 8)
  expect_equal(r[Variable == "LAND" & Item == "CRP", Value], 15)
  expect_equal(r[Variable == "LAND" & Item == "AGR", Value], 35)
  expect_equal(r[Variable == "PROTO", Unit], "gprt/cap/day")
})

test_that("fadn_cost_rows appends unchanged and keeps only GDX scenarios", {
  f <- tempfile(fileext = ".csv")
  fwrite(data.table(Region = "AUT", Year = 2030L, Scenario = c("BASE", "EPS-S9"), Variable = "COST",
                    Item = "Whea|HI|Fertiliser", Unit = "USD 2000 per ha", value = c(40.5, 60)), f)
  r <- fadn_cost_rows(f, scenarios = "BASE")
  expect_equal(nrow(r), 1)
  expect_equal(r$Value, 40.5)
  expect_equal(r$Item, "Whea|HI|Fertiliser")
  fwrite(data.table(Region = "AUT", Year = 2030L, Scenario = "BASE", Variable = "COST",
                    Item = "Whea|HI|Seeds", Unit = "USD 2000 per ha", value = c(1, 2)), f)
  expect_error(fadn_cost_rows(f, "BASE"), "Duplicate keys")
})

test_that("filter_reporting drops excluded regions, items and years", {
  d <- data.table(Region = c("AUT", "ROW", "AUT", "AUT"), Item = c("Whea", "Whea", "SOC", "Whea"),
                  Year = c(2020L, 2020L, 2020L, 2025L))
  expect_equal(nrow(filter_reporting(d)), 1)
})
