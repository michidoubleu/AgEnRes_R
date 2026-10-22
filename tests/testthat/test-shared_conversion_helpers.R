# Run from the repository root:
#   Rscript -e "testthat::test_dir('tests/testthat')"

library(testthat)

root <- normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "AgEnRes_R.Rproj"))) root <- normalizePath(getwd(), winslash = "/")
source(file.path(root, "scripts", "shared_conversion_helpers.R"))

# Minimal reference vocabulary so the tests do not depend on the large template file.
mini_vocab <- list(
  columns    = TEMPLATE_COLUMNS_FALLBACK,
  variables  = c("Area", "COST", "FRTN", "CTAX"),
  item_parts = c("Whea", "Barl", "AGR", "Seeds", "CGR", "MAI"),
  units      = c("1000 ha", "1000 t", "USD 2000 per ha"),
  regions    = c("DEU", "World"),
  years      = c("2000", "2010")
)

row <- function(...) {
  d <- data.table(Model = "M", Scenario = "base", Region = "DEU", Item = "Whea", Variable = "Area",
                  Year = "2010", Unit = "1000 ha", Value = 1.5)
  mods <- list(...)
  for (n in names(mods)) set(d, j = n, value = mods[[n]])
  d
}
errs <- function(d, ...) validate_template(d, mini_vocab, ...)$errors
adds <- additions_table(c("Variable", "Item", "Unit"), c("ENUS", "Diesel", "liter per ha"),
                        c("energy use", "diesel", "litres per ha"), c("", "Diesel input", "liter per ha"), "M")

test_that("excel_cell builds A1 references", {
  expect_equal(excel_cell(2, 1), "A2")
  expect_equal(excel_cell(10, 27), "AA10")
  expect_equal(excel_col(20), "T")
})

test_that("parse_number keeps blanks as NA and rejects text", {
  expect_equal(parse_number(c("1.5", "", " 2 ")), c(1.5, NA, 2))
  expect_error(parse_number(c("1", "abc")), "Non-numeric")
})

test_that("read_dat_table aligns names when data rows have an extra trailing tab", {
  f <- tempfile(fileext = ".dat")
  writeLines(c("a\tb\tc", "1\t2\t3\t", "4\t5\t6\t"), f)
  d <- read_dat_table(f)
  expect_equal(names(d), c("a", "b", "c"))
  expect_equal(d$a, c("1", "4"))
  expect_equal(d$c, c("3", "6"))
  writeLines(c("a\tb", "1\t2\t3"), f)
  expect_error(read_dat_table(f), "Unnamed non-empty")
})

test_that("reference codes pass, compound Items are checked part by part", {
  expect_length(errs(rbind(row(), row(Item = "Whea|Seeds", Variable = "COST", Unit = "USD 2000 per ha"),
                           row(Item = "CGR|MAI"))), 0)
  expect_match(errs(row(Item = "Whea|Foo")), "Item codes neither", all = FALSE)
})

test_that("new codes are errors unless declared, and declared ones are reported", {
  d <- row(Variable = "ENUS", Item = "Whea|Diesel", Unit = "liter per ha")
  e <- errs(d)
  expect_match(e, "Variable codes neither", all = FALSE)
  expect_match(e, "Item codes neither", all = FALSE)
  expect_match(e, "Unit codes neither", all = FALSE)
  res <- validate_template(d, mini_vocab, additions = adds)
  expect_length(res$errors, 0)
  expect_match(res$warnings, "3 new codes proposed", all = FALSE)
  expect_setequal(res$new_codes$code, c("ENUS", "Diesel", "liter per ha"))
})

test_that("structural errors are caught", {
  expect_match(errs(row(Region = "FOO")), "Region codes neither", all = FALSE)
  expect_match(errs(row(Year = "2015")), "Year codes neither", all = FALSE)
  expect_match(errs(rbind(row(), row())), "duplicate", all = FALSE)
  expect_match(errs(row(Value = NA_real_)), "non-finite", all = FALSE)
  expect_match(errs(row(Year = "")), "blank field Year", all = FALSE)
  expect_match(errs(row(Scenario = 'a"b')), "quotes", all = FALSE)
  expect_match(errs(row(Item = "Whea|")), "empty", all = FALSE)
  d <- row(); setcolorder(d, rev(names(d)))
  expect_match(errs(d), "Columns must be exactly")
})

test_that("model-specific regions and years need the regex and give warnings", {
  d <- row(Region = "AgriPolis_r0_f1_X", Year = "3")
  expect_match(errs(d), "Region codes neither", all = FALSE)
  res <- validate_template(d, mini_vocab, allowed_region_regex = "^AgriPolis_", allowed_year_regex = "^[0-9]+$")
  expect_length(res$errors, 0)
  expect_match(res$warnings, "model-specific Region", all = FALSE)
  expect_match(res$warnings, "Year values outside", all = FALSE)
})

test_that("write_template_csv reproduces the comprehensive layout and round-trips", {
  f <- tempfile(fileext = ".csv")
  d <- rbind(row(Item = "Whea", Value = 0.0409466221894075), row(Item = "Barl", Year = "2000", Value = 0),
             row(Item = "AGR|Hard Coal, Coke and Other Solids", Value = 2))
  write_template_csv(d, f, mini_vocab$columns)
  txt <- rawToChar(readBin(f, "raw", file.info(f)$size))
  expect_true(grepl("\r\n", txt, fixed = TRUE))
  lines <- strsplit(txt, "\r\n", fixed = TRUE)[[1]]
  expect_equal(lines[1], "Model,Scenario,Region,Item,Variable,Year,Unit,Value")
  expect_equal(lines[2], 'M,base,DEU,"AGR|Hard Coal, Coke and Other Solids",Area,2010,1000 ha,2')   # sorted by key
  expect_equal(lines[3], "M,base,DEU,Barl,Area,2000,1000 ha,0")
  expect_equal(lines[4], "M,base,DEU,Whea,Area,2010,1000 ha,0.0409466221894075")
  back <- read_template_output(f, mini_vocab$columns)
  expect_equal(back$Item[1], "AGR|Hard Coal, Coke and Other Solids")
  expect_equal(back$Value, c(2, 0, 0.0409466221894075))
})

test_that("real template vocabulary loads (if template files are present)", {
  skip_if_not(file.exists(file.path(root, TEMPLATE_CSV)) && file.exists(file.path(root, TEMPLATE_GLOSSARY)))
  v <- load_template_vocab(root)
  expect_equal(v$columns, TEMPLATE_COLUMNS_FALLBACK)
  expect_true(all(c("Area", "COST", "FRTN", "CTAX", "ARIR", "Anim") %in% v$variables))
  expect_true(all(c("Whea", "Barl", "AGR", "CRP", "Seeds", "Motor fuels") %in% v$item_parts))
  expect_length(v$cost_categories, 11)
  expect_equal(v$years, c("2000", "2010", "2020", "2030", "2040", "2050"))
  expect_false(any(NEW_CROP_CODES$code %in% v$item_parts))      # new codes really are new
  expect_false(any(NEW_VARIABLES$code %in% v$variables))
})
