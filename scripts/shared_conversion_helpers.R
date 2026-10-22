# =============================================================================
# Shared helpers for translating partner-model outputs into the common
# GLOBIOM-style reporting format.
#
# Principles agreed with the project lead (2026-10-21):
#   * COLUMNS: fixed by inputs/template/20260213_GLOBIOM_comprehensive.csv
#     (Model,Scenario,Region,Item,Variable,Year,Unit,Value). That file only
#     defines the columns and layout.
#   * CODES: the GLOBIOM glossary (inputs/template/GLOBIOM_glossary.xlsx) and the
#     codes used in the comprehensive file describe what GLOBIOM reports today.
#     They are a SUGGESTION: partner models are fitted into this framework as
#     well as possible, and where nothing fits a new code is proposed. Every new
#     code must be declared by the converter (definition + original model term)
#     and is written to proposed_glossary_additions.csv for review.
#   * VALUES: never converted. Only values that appear in the model's original
#     reporting are written, with the original unit label.
#   * Model = model name; Scenario = the model's scenario name, baseline spelled BASE. The template
#     has no SSP / RCP columns (partner models follow GLOBIOM's assumptions).
#   * Crops of farm models are always identified in Item (glossary crop code,
#     or a new code from NEW_CROP_CODES). Models without crop detail use the
#     Item AGR, with sub-classes as AGR|<subclass>.
#
# No official executable validator exists in the repository. validate_template()
# implements the checks described above; it is NOT an official validator.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
})

TEMPLATE_CSV      <- file.path("inputs", "template", "20260213_GLOBIOM_comprehensive.csv")
TEMPLATE_GLOSSARY <- file.path("inputs", "template", "GLOBIOM_glossary.xlsx")

# Fallback only - the header of the template CSV is read when available.
TEMPLATE_COLUMNS_FALLBACK <- c("Model", "Scenario", "Region", "Item", "Variable", "Year", "Unit", "Value")

# Proposed new Variables (shared by all converters).
NEW_VARIABLES <- rbindlist(list(
  list("PRIC", "Price of an input (e.g. energy carrier) faced by the sector given in Item; unit as reported by the model."),
  list("ENUS", "Energy / fuel use, by crop (farm models, per ha) or by sector and carrier (Item AGR|<carrier>); unit as reported."),
  list("ENSV", "Energy-service activity level driving energy demand (e.g. greenhouse area, forestry output); unit as reported.")
))
setnames(NEW_VARIABLES, c("code", "definition"))

# Proposed new crop / land-use codes, in the style of the glossary crop codes
# (Whea, Barl, SugC, BeaD ...). Shared by FarmDyn and AgriPolis so that the
# same crop gets the same code in both models.
NEW_CROP_CODES <- rbindlist(list(
  list("RyeG", "Rye (grain)"),
  list("RyeB", "Rye grown for biogas"),
  list("SugB", "Sugar beet"),
  list("CorS", "Silage maize (whole plant)"),
  list("WCSi", "Whole-crop silage (cereals harvested green, 'GPS')"),
  list("BeaF", "Field beans (faba / summer beans)"),
  list("Prot", "Protein crops, not further specified (peas, beans, lupins)"),
  list("Alfa", "Alfalfa (lucerne)"),
  list("LeyG", "Ley / temporary grass on arable land"),
  list("GrSI", "Grass silage, intensive grassland"),
  list("GrSE", "Grass silage, extensive grassland"),
  list("PasS", "Pasture, strip grazing (Portionsweide)"),
  list("PasR", "Pasture, rotational grazing (Umtriebsweide)"),
  list("PasC", "Pasture, continuous grazing (Standweide)"),
  list("SetA", "Set-aside land"),
  list("IdlA", "Idle arable land"),
  list("IdlG", "Idle grassland")
))
setnames(NEW_CROP_CODES, c("code", "definition"))

ADDITION_COLUMNS <- c("dimension", "code", "definition", "source_label", "model")

log_msg <- function(...) message(sprintf(...))

# -----------------------------------------------------------------------------
# Reference vocabulary (what GLOBIOM reports today)
# -----------------------------------------------------------------------------

read_template_columns <- function(root) {
  path <- file.path(root, TEMPLATE_CSV)
  if (!file.exists(path)) {
    warning("Template data file not found (", path, "); using built-in column list.")
    return(TEMPLATE_COLUMNS_FALLBACK)
  }
  hdr <- sub("\r$", "", readLines(path, n = 1, warn = FALSE))
  hdr <- sub(paste0("^", intToUtf8(0xFEFF)), "", hdr)   # drop a UTF-8 byte-order mark
  cols <- gsub('^"|"$', "", strsplit(hdr, ",", fixed = TRUE)[[1]])
  if (!identical(cols, TEMPLATE_COLUMNS_FALLBACK)) {
    log_msg("NOTE: template header differs from the built-in list; using the file header: %s",
            paste(cols, collapse = ","))
  }
  cols
}

# Reads one glossary sheet: the table starts below the first row whose first
# cell is a known header word ("Code", "Unit", "Dimension").
read_glossary_sheet <- function(path, sheet) {
  raw <- read_excel(path, sheet = sheet, col_names = FALSE, col_types = "text",
                    .name_repair = "minimal")
  m <- as.matrix(raw)
  m[is.na(m)] <- ""
  m <- trimws(m)
  h <- which(m[, 1] %in% c("Code", "Unit", "Dimension"))[1]
  if (is.na(h)) stop("No header row found in glossary sheet '", sheet, "'.")
  body <- m[(h + 1):nrow(m), , drop = FALSE]
  body <- body[body[, 1] != "", , drop = FALSE]
  dt <- as.data.table(body)
  setnames(dt, paste0("c", seq_len(ncol(dt))))
  dt
}

split_item <- function(x) unlist(strsplit(x, "|", fixed = TRUE), use.names = FALSE)

load_template_vocab <- function(root) {
  cpath <- file.path(root, TEMPLATE_CSV)
  if (!file.exists(cpath)) stop("Template file not found: ", cpath)
  t0 <- Sys.time()
  d <- unique(fread(cpath, select = c("Region", "Item", "Variable", "Year", "Unit"),
                    colClasses = "character", showProgress = FALSE))
  log_msg("Template: %s - %d distinct Region|Item|Variable|Year|Unit tuples (%.1fs)",
          TEMPLATE_CSV, nrow(d), as.numeric(difftime(Sys.time(), t0, units = "secs")))

  gpath <- file.path(root, TEMPLATE_GLOSSARY)
  if (!file.exists(gpath)) stop("Template glossary not found: ", gpath)
  log_msg("Template glossary: %s", TEMPLATE_GLOSSARY)
  vars_g  <- read_glossary_sheet(gpath, "Variables")
  regs_g  <- read_glossary_sheet(gpath, "Regions")
  items_g <- read_glossary_sheet(gpath, "Items")
  units_g <- read_glossary_sheet(gpath, "Units")

  list(
    columns         = read_template_columns(root),
    variables       = sort(unique(c(vars_g$c1, d$Variable))),
    item_parts      = sort(unique(c(items_g$c1, split_item(d$Item)))),
    units           = sort(unique(c(units_g$c1, d$Unit))),
    regions         = sort(unique(c(regs_g$c1, d$Region))),
    years           = sort(unique(d$Year)),
    crop_items      = items_g[c3 == "Crop product", c1],
    cost_categories = items_g[c3 == "FADN cost category (COST)", c1],
    item_labels     = setNames(items_g$c2, items_g$c1),
    variable_labels = setNames(vars_g$c2, vars_g$c1)
  )
}

# Codes of the output that are not in the reference vocabulary, by dimension.
# Item codes are checked part by part ("Whea|Seeds" -> Whea, Seeds).
new_codes <- function(dt, vocab) {
  rbindlist(list(
    data.table(dimension = "Variable", code = setdiff(unique(dt$Variable), vocab$variables)),
    data.table(dimension = "Item",     code = setdiff(unique(split_item(unique(dt$Item))), vocab$item_parts)),
    data.table(dimension = "Unit",     code = setdiff(unique(dt$Unit), vocab$units)),
    data.table(dimension = "Region",   code = setdiff(unique(dt$Region), vocab$regions)),
    data.table(dimension = "Year",     code = setdiff(unique(dt$Year), vocab$years))
  ))
}

# -----------------------------------------------------------------------------
# Source reading
# -----------------------------------------------------------------------------

# Reads an AgriPolis-style tab-separated .dat file. Header and data rows may
# have different numbers of trailing tabs (e.g. farm_standard_indicators.dat has
# 61 header names but 62 data fields), which makes fread's auto-detection shift
# all columns. Names are therefore taken from the header line and any surplus
# trailing data columns must be completely empty.
read_dat_table <- function(path) {
  hdr <- trimws(strsplit(readLines(path, n = 1, warn = FALSE), "\t", fixed = TRUE)[[1]])
  hdr <- hdr[hdr != ""]
  if (anyDuplicated(hdr)) stop("Duplicate column names in ", path)
  d <- fread(path, sep = "\t", header = FALSE, skip = 1, colClasses = "character",
             strip.white = TRUE, na.strings = c("", "NA"), showProgress = FALSE)
  if (ncol(d) < length(hdr)) stop("Fewer data columns than header names in ", path)
  extra <- setdiff(seq_len(ncol(d)), seq_along(hdr))
  for (j in extra) {
    if (!all(is.na(d[[j]]))) stop("Unnamed non-empty data column ", j, " in ", path)
  }
  d <- d[, seq_along(hdr), with = FALSE]
  setnames(d, hdr)
  for (j in names(d)) set(d, j = j, value = trimws(d[[j]]))
  log_msg("Read %s: %d rows x %d columns", basename(path), nrow(d), ncol(d))
  d
}

# Reads a worksheet as a trimmed character matrix (blank = ""), preserving the
# Excel row/column positions so that source cells can be traced.
read_sheet_matrix <- function(path, sheet) {
  raw <- read_excel(path, sheet = sheet, col_names = FALSE, col_types = "text",
                    .name_repair = "minimal")
  m <- as.matrix(raw)
  m[is.na(m)] <- ""
  m <- trimws(m)
  log_msg("Read %s, sheet '%s': %d rows x %d columns", basename(path), sheet, nrow(m), ncol(m))
  m
}

excel_col <- function(j) {
  vapply(j, function(k) {
    s <- ""
    while (k > 0) { r <- (k - 1) %% 26; s <- paste0(LETTERS[r + 1], s); k <- (k - 1) %/% 26 }
    s
  }, character(1))
}
excel_cell <- function(i, j) paste0(excel_col(j), i)

# Strict numeric parsing: blanks -> NA (never 0); non-numeric text -> error.
parse_number <- function(x, what = "value") {
  x <- trimws(as.character(x))
  x[x == ""] <- NA
  v <- suppressWarnings(as.numeric(x))
  bad <- !is.na(x) & is.na(v)
  if (any(bad)) stop("Non-numeric ", what, ": ", paste(head(unique(x[bad]), 5), collapse = ", "))
  v
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

# Returns list(errors, warnings, new_codes).
# additions: data.table(dimension, code, definition, source_label, model) - the
#   new codes the converter declares. Codes that are neither in the reference
#   vocabulary nor declared are errors (protects against typos).
# allowed_region_regex / allowed_year_regex: model-specific Region / Year values
#   (farm IDs, model time steps) accepted without individual declaration.
validate_template <- function(dt, vocab, additions = NULL, allowed_region_regex = NULL,
                              allowed_year_regex = NULL) {
  err <- character(); wrn <- character()
  E <- function(...) err <<- c(err, sprintf(...))
  W <- function(...) wrn <<- c(wrn, sprintf(...))
  show <- function(x) paste(head(unique(x), 8), collapse = ", ")
  out <- function(nc = data.table(dimension = character(), code = character()))
    list(errors = err, warnings = wrn, new_codes = nc)

  # 1. Columns: exact names, order, no extras
  if (!identical(names(dt), vocab$columns)) {
    E("Columns must be exactly [%s]; got [%s]", paste(vocab$columns, collapse = ","),
      paste(names(dt), collapse = ","))
    return(out())
  }
  if (nrow(dt) == 0) { W("Output contains 0 data rows."); return(out()) }

  # 2. Types
  chr_cols <- setdiff(vocab$columns, "Value")
  for (cl in chr_cols) if (!is.character(dt[[cl]])) E("Column %s must be character", cl)
  if (!is.numeric(dt$Value)) E("Column Value must be numeric")
  if (length(err)) return(out())

  # 3. Mandatory fields, no line breaks / quotes inside text
  for (cl in chr_cols) {
    n <- sum(is.na(dt[[cl]]) | dt[[cl]] == ""); if (n) E("%d rows with blank field %s", n, cl)
    bad <- dt[[cl]][grepl('["\r\n]', dt[[cl]])]
    if (length(bad)) E("Column %s contains quotes or line breaks: %s", cl, show(bad))
  }
  bad <- dt$Item[grepl("^[|]|[|]$|[|][|]", dt$Item)]
  if (length(bad)) E("Item with an empty '|' part: %s", show(bad))
  n <- sum(!is.finite(dt$Value)); if (n) E("%d rows with missing / non-finite Value", n)

  # 4. Codes: reference vocabulary, model-specific patterns or declared additions
  nc <- new_codes(dt, vocab)
  if (!is.null(allowed_region_regex)) {
    k <- nc$dimension == "Region" & grepl(allowed_region_regex, nc$code)
    if (any(k)) W("%d model-specific Region IDs matching '%s' (farm level, authorised for this model)", sum(k), allowed_region_regex)
    nc <- nc[!k]
  }
  if (!is.null(allowed_year_regex)) {
    k <- nc$dimension == "Year" & grepl(allowed_year_regex, nc$code)
    if (any(k)) W("%d Year values outside GLOBIOM's reporting years, matching '%s' (authorised for this model): %s",
                  sum(k), allowed_year_regex, show(nc$code[k]))
    nc <- nc[!k]
  }
  declared <- if (is.null(additions)) nc[0] else unique(additions[, .(dimension, code)])
  undeclared <- nc[!declared, on = c("dimension", "code")]
  for (d in unique(undeclared$dimension)) {
    E("%s codes neither in the GLOBIOM glossary / comprehensive file nor declared as proposed additions: %s",
      d, show(undeclared[dimension == d, code]))
  }
  used_new <- nc[declared, on = c("dimension", "code"), nomatch = 0L]
  if (nrow(used_new)) {
    W("%d new codes proposed as glossary additions (see proposed_glossary_additions.csv): %s",
      nrow(used_new), paste(used_new[, sprintf("%s %s", dimension, code)], collapse = "; "))
  }

  # 5. Duplicates on the key (all columns except Value)
  key <- setdiff(vocab$columns, "Value")
  nd <- sum(duplicated(dt, by = key))
  if (nd) E("%d duplicate rows on key (%s)", nd, paste(key, collapse = ","))

  out(used_new)
}

print_validation <- function(res, label) {
  log_msg("Validation (%s): %d error(s), %d warning(s)", label, length(res$errors), length(res$warnings))
  for (e in res$errors)   log_msg("  ERROR:   %s", e)
  for (w in res$warnings) log_msg("  WARNING: %s", w)
}

# -----------------------------------------------------------------------------
# Writing
# -----------------------------------------------------------------------------

# Writes in the layout of the template: comma-separated, CRLF line endings,
# fields unquoted unless they contain a comma (e.g. OpenPROM's
# "Hard Coal, Coke and Other Solids"), rows sorted by the key columns.
write_template_csv <- function(dt, path, columns) {
  dt <- copy(dt)
  setcolorder(dt, columns)
  key <- setdiff(columns, "Value")
  setorderv(dt, key)
  q <- function(x) fifelse(grepl(",", x, fixed = TRUE), paste0('"', x, '"'), x)
  body <- if (nrow(dt)) {
    do.call(paste, c(lapply(key, function(cl) q(dt[[cl]])), list(as.character(dt$Value)), sep = ","))
  } else character()
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(c(paste(columns, collapse = ","), body), con, sep = "\r\n", useBytes = TRUE)
  invisible(dt)
}

read_template_output <- function(path, columns) {
  d <- fread(path, colClasses = "character", na.strings = NULL, showProgress = FALSE)
  if (nrow(d)) d[, Value := as.numeric(Value)] else d[, Value := numeric()]
  d
}

# Validates, writes, re-reads and re-validates. Stops (without leaving an
# output CSV behind) if any error is found. Also writes the proposed glossary
# additions actually used by the output. Returns the validation results.
validate_and_write <- function(dt, vocab, out_csv, additions = NULL, allowed_region_regex = NULL,
                               allowed_year_regex = NULL) {
  dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
  res <- validate_template(dt, vocab, additions, allowed_region_regex, allowed_year_regex)
  print_validation(res, "pre-write")
  if (length(res$errors)) {
    if (file.exists(out_csv)) file.remove(out_csv)
    stop("Template validation failed - no output written. See errors above.", call. = FALSE)
  }
  write_template_csv(dt, out_csv, vocab$columns)
  back <- read_template_output(out_csv, vocab$columns)
  res2 <- validate_template(back, vocab, additions, allowed_region_regex, allowed_year_regex)
  print_validation(res2, "round-trip of written file")
  if (length(res2$errors)) stop("Written file failed re-validation: ", out_csv, call. = FALSE)
  if (nrow(back) != nrow(dt)) stop("Row count changed on round-trip: ", out_csv, call. = FALSE)
  # Values are written with 15 significant digits (as in the GLOBIOM file).
  srt <- setorderv(copy(dt), setdiff(vocab$columns, "Value"))
  if (!isTRUE(all.equal(back$Value, srt$Value, tolerance = 1e-13)))
    stop("Values changed on round-trip beyond 15 significant digits: ", out_csv, call. = FALSE)
  log_msg("Wrote %s (%d rows)", out_csv, nrow(dt))

  add_path <- file.path(dirname(out_csv), "proposed_glossary_additions.csv")
  used <- if (is.null(additions)) NULL else additions[res2$new_codes, on = c("dimension", "code"), nomatch = 0L]
  if (!is.null(used) && nrow(used)) {
    used <- unique(used[, ADDITION_COLUMNS, with = FALSE])
    setorderv(used, c("dimension", "code"))
    fwrite(used, add_path, quote = TRUE)
    log_msg("Wrote %s (%d proposed codes)", add_path, nrow(used))
  } else if (file.exists(add_path)) file.remove(add_path)
  res2$additions <- used
  res2
}

# Builds the additions table: one row per (dimension, code).
additions_table <- function(dimension, code, definition, source_label, model) {
  d <- data.table(dimension = dimension, code = code, definition = definition,
                  source_label = source_label, model = model)
  d[, .(definition = definition[1], source_label = paste(unique(source_label), collapse = "; "),
        model = model[1]), by = .(dimension, code)][, ADDITION_COLUMNS, with = FALSE]
}

# Removes output files of an earlier format, which this converter generated
# before the template changed.
remove_legacy_output <- function(out_dir, model) {
  for (old in file.path(out_dir, paste0(model, "_OUTPUT_AG_REG.csv"))) {
    if (!file.exists(old)) next
    ok <- suppressWarnings(file.remove(old))
    if (ok) log_msg("Removed legacy output %s", old)
    else log_msg("NOTE: legacy output %s (old OUTPUT_AG_REG format) could not be removed - delete it by hand.", old)
  }
}

# -----------------------------------------------------------------------------
# Documentation
# -----------------------------------------------------------------------------

MAPPING_LOG_COLUMNS <- c("source_file", "source_sheet", "source_table_or_range", "source_variable",
                         "source_label_or_definition", "source_unit", "template_entry",
                         "template_column_or_field", "transformation", "output_unit",
                         "mapping_status", "confidence", "n_output_rows", "notes", "exclusion_reason")

write_mapping_log <- function(log_dt, path) {
  log_dt <- as.data.table(log_dt)
  for (cl in setdiff(MAPPING_LOG_COLUMNS, names(log_dt))) set(log_dt, j = cl, value = NA)
  log_dt <- log_dt[, MAPPING_LOG_COLUMNS, with = FALSE]
  fwrite(log_dt, path, na = "", quote = TRUE)
  log_msg("Wrote %s (%d mapping-log rows)", path, nrow(log_dt))
}

md_table <- function(dt) {
  dt <- as.data.frame(dt)
  if (!nrow(dt)) return("_(none)_")
  esc <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; gsub("|", "\\|", x, fixed = TRUE) }
  c(paste0("| ", paste(names(dt), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(dt)), collapse = "|"), "|"),
    apply(dt, 1, function(r) paste0("| ", paste(esc(r), collapse = " | "), " |")))
}

validation_md <- function(res) {
  c(sprintf("- Errors: %d", length(res$errors)),
    if (length(res$errors)) paste0("  - ", res$errors),
    sprintf("- Warnings: %d", length(res$warnings)),
    if (length(res$warnings)) paste0("  - ", res$warnings))
}

additions_md <- function(res) {
  a <- res$additions
  if (is.null(a) || !nrow(a)) return("_No new codes - everything fits the current GLOBIOM vocabulary._")
  c("Codes used in the output that GLOBIOM does not report today (also in `proposed_glossary_additions.csv`):",
    "", md_table(a[, .(Dimension = dimension, Code = code, Definition = definition, `Original term` = source_label)]))
}

# Standard README paragraphs shared by all converters.
readme_template_note <- function() c(
  "- Columns fixed by `inputs/template/20260213_GLOBIOM_comprehensive.csv`: `Model, Scenario, Region, Item, Variable, Year, Unit, Value`; comma-separated, CRLF line endings, fields quoted only if they contain a comma.",
  "- Codes follow the GLOBIOM glossary / comprehensive file where they fit; otherwise new codes are proposed (section 'Proposed glossary additions').",
  "- **Values are not converted**: every value is taken unchanged from the model's original reporting, with the original unit label.",
  "- `Model` = model name; `Scenario` = the model's scenario name, with the baseline spelled `BASE` as in GLOBIOM. The template has no SSP / RCP columns; the partner models follow GLOBIOM's assumptions (glossary: SSP2, RCP2.6) without reporting them."
)

readme_validation_note <- function() paste(
  "No official executable validator exists in the repository. The script runs `validate_template()` (`scripts/shared_conversion_helpers.R`) before writing and again on the re-read file.",
  "Checks: exact columns and order; types; no blank fields, quotes or line breaks; every Variable, Item part, Unit, Region and Year is either a GLOBIOM code (glossary or comprehensive file) or a declared proposed addition (undeclared codes are errors);",
  "duplicate keys; finite values.")

write_lines_lf <- function(lines, path) {
  con <- file(path, open = "wb"); on.exit(close(con))
  writeLines(enc2utf8(lines), con, sep = "\n", useBytes = TRUE)
  log_msg("Wrote %s", path)
}
