# Claude Code Task Brief: Bring GLOBIOM `OUTPUT_AG_REG.csv` into the Shared Template

## Role and objective

Act as a careful data-integration engineer in this repository. Three
partner models (FarmDyn, AgriPolis, OpenPROM) have already been
converted into the shared 8-column template by
`scripts/<Model>_to_template.R`. Your job is to write the fourth
converter, **`scripts/GLOBIOM_to_template.R`**. It brings GLOBIOM's own
reporting file `inputs/template/OUTPUT_AG_REG.csv` into exactly the same
format, so that a dashboard can put GLOBIOM next to the partner models.

You have two deliverables:

1. The GLOBIOM data in the template format.
2. A **comparison crosswalk** stating, for every partner row type, which
   GLOBIOM entries it corresponds to and how comparable they are.

The project lead's rule is: **don't assume, ask if something is not
clear.** Section 9 lists the decisions that need confirmation. Ask them
before you code; if they cannot be asked, use the defaults given there
and record them as defaults in the README.

## 1. Read first (do not modify)

- `scripts/shared_conversion_helpers.R`: the shared helpers you must
  reuse (`load_template_vocab`, `validate_template`,
  `validate_and_write`, `additions_table`, `write_mapping_log`,
  `md_table`, `validation_md`, `additions_md`, `readme_template_note`,
  `readme_validation_note`, `write_lines_lf`). Do not re-implement them.
  Only add a helper if it is generic, and add a test for it.
- One existing converter as a style reference.
  `scripts/OpenPROM_to_template.R` is closest (rule table, "first match
  wins").
- The outputs in `outputs/FarmDyn`, `outputs/AgriPolis` and
  `outputs/OpenPROM` (CSV, README.md, mapping_log.csv,
  proposed_glossary_additions.csv). Your outputs must look the same.
- `tests/testthat/test-shared_conversion_helpers.R`.
- Do **not** modify the source files in `inputs/`, the template CSV or
  the glossary. Do not touch `outputs/AgriPolis/AgriPolis_test.csv`
  (it belongs to the user). Do not commit unless asked.

## 2. Agreed rules (they apply to all four models)

- **Columns** come only from `inputs/template/20260213_GLOBIOM_comprehensive.csv`:
  `Model,Scenario,Region,Item,Variable,Year,Unit,Value`, in that order.
  That file is about 100 MB. Read only its header, or selected columns
  via `fread(select=...)`, which is what `load_template_vocab` already
  does.
- **Codes:** the glossary `inputs/template/GLOBIOM_glossary.xlsx` plus
  the codes in the comprehensive CSV are the reference vocabulary. New
  codes are allowed but must be declared via `additions_table()`.
  Undeclared codes are an error.
- **Values are not converted.** Only values that appear in the source go
  into the output. No currency, energy or mass conversions, no sums, no
  per-ha versus total recalculation, no copying a value onto extra
  items. The only conversion ever allowed is area to 1000 ha and
  production to 1000 t, and GLOBIOM already reports in those units.
- **Model** = model name (`GLOBIOM`). **Scenario** = the model's own
  scenario names.
- **Output layout:** written via `validate_and_write()`. Unquoted except
  fields containing a comma; CRLF line endings; sorted by key; 15
  significant digits; the round-trip check must pass.
- 0 validation errors. Re-running must give a byte-identical output
  (check the md5).

## 3. What the source file looks like (already inspected)

`inputs/template/OUTPUT_AG_REG.csv`: 1,748,685 rows, about 97 MB, CRLF
line endings, no BOM. Read the whole file with
`data.table::fread(..., colClasses = "character")` and then parse
`Value`.

| Source column | Template column | Action |
|---|---|---|
| (none) | `Model` | constant `GLOBIOM` |
| `CostScenario` | `Scenario` | verbatim: `BASE`, `EPS-S1`, `EPS-S2`, `EPS-S3` |
| `Region` | `Region` | verbatim. All 48 codes are in the vocabulary (ISO3 such as `DEU`, `AUT`, plus `World`, `EUR`, `ROW`, …) |
| `Item` | `Item` | verbatim. All `|` parts are already in the vocabulary |
| `Indicator` | `Variable` | rename only. All 59 indicators are in the vocabulary |
| `Year` | `Year` | verbatim: 2000, 2010, …, 2050 |
| `Unit` | `Unit` | verbatim. All units are in the vocabulary |
| `Value` | `Value` | numeric; see the `Eps` decision in section 9 |

Facts checked by the person who wrote this brief:

- No blank fields. No commas or quotes in Item. No duplicate keys over
  all 7 source columns.
- Many key combinations repeat once Unit is dropped (fresh weight vs
  `1000 t dm` vs `1000 m3` vs `PJ`). This is fine because Unit is part
  of the template key. Never drop Unit.
- 208 values are the literal `Eps`. This is the GAMS marker for "zero
  but present"; every other value is numeric.
- As a result, the GLOBIOM converter needs **no new codes** and should
  produce an empty additions table. If a code fails validation, it is a
  bug in your code, not a reason to declare a new one.

## 4. The structure of the soft-link variables (this is what the crosswalk must capture)

| Variable | GLOBIOM Item structure | Unit |
|---|---|---|
| `COST` | `crop|management|category`, e.g. `Whea|HI|Seeds`. Management: `HI`, `IR`, `LI`, `SS`. Categories: `Contract work`, `Crop protection`, `Electricity`, `Fertiliser`, `Heating fuels`, `Labour`, `Motor fuels`, `Other crop costs`, `Seeds`, `Water`, **`Total`** | `USD 2000 per ha` |
| `Area` | crop (`Whea`, `Barl`, `Corn`, `Rape`, `Pota`, …) and livestock grassland items (`BVMEAT`, `SGMEAT`, `ALMILK`) and `IP_Biomass` | `1000 ha` |
| `FRTN` | crop | `1000 t` **and** `1000 t dm` (both reported; keep both) |
| `ARIR` | crop | `1000 ha` |
| `Anim` | animal type (`PIGS`, `BOVD`, `BOVF`, …, `BVMEAT`, …) | `1000 TLU` |
| `CTAX` | emission source (`ENT`, `MAS`, `MGR`, `Mmg`, `SFR`, `LUC*`, `SOC*`, `PEAT`, `RCC`); same value for every source within region and year | `USD/tCO2e` |
| `XPRI`, `XPRP` | commodity | `USD 2000 per ton`, `USD 2000 per GJ` |

GLOBIOM has **no** `ENUS`, `ENSV` or `PRIC`. These were proposed for the
partner models. Do not invent GLOBIOM rows for them.

Keep the GLOBIOM COST items with their management part, exactly as
reported. The partner models carry no management part (the project lead
decided that for the partner models). Comparing COST across models is
therefore done through the crosswalk, not by rewriting GLOBIOM items.
Removing the management part would create duplicate keys, and averaging
over management systems would be a value conversion. See section 9,
decision B.

## 5. Script requirements (`scripts/GLOBIOM_to_template.R`)

Follow the structure of the existing converters:

1. Find the project root by walking up to `AgEnRes_R.Rproj`, then
   `source()` the shared helpers.
2. Set constants at the top: `MODEL <- "GLOBIOM"`, the source path, the
   output dir `outputs/GLOBIOM/`, and the output file
   `GLOBIOM_GLOBIOM_comprehensive.csv` (the same `<Model>_GLOBIOM_comprehensive.csv`
   naming as the others; awkward but consistent).
3. Use a small, explicit column-rename table rather than inline renames,
   so that it can be written to the mapping log.
4. Apply the scope filter (decision A) as a named vector of Variables at
   the top of the script.
5. Use a rule table for `Value` parsing (`Eps`, decision C). Every other
   non-numeric value must stop the script with a clear error listing
   examples. It must not silently become NA.
6. Call `validate_and_write(dt, vocab, out_csv, additions = <empty additions_table>)`
   with no region or year regex; GLOBIOM must pass on the reference
   vocabulary alone.
7. Write `mapping_log.csv` (via `write_mapping_log`) with one row per source Indicator and Unit, using exactly the 15 columns of the existing logs (`source_file`, `source_sheet`, `source_table_or_range`, `source_variable`, `source_label_or_definition`, `source_unit`, `template_entry`, `template_column_or_field`, `transformation`, `output_unit`, `mapping_status`, `confidence`, `n_output_rows`, `notes`, `exclusion_reason`).
8. Write `README.md` with the same section order as
   `outputs/OpenPROM/README.md`. Include:
   - source and size;
   - column mapping;
   - scope;
   - the `Eps` handling;
   - the note that COST keeps the management part;
   - FRTN reported in two units;
   - the CTAX structure;
   - a short "How this lines up with the partner models" section that
     points to the crosswalk;
   - the validation result;
   - the reproduction command
     `Rscript scripts/GLOBIOM_to_template.R`.
9. Since there are no additions, make sure no stale
   `proposed_glossary_additions.csv` is left (the helper already removes
   it).
10. Performance: 1.7 M rows. Use data.table throughout. The script
    should run in well under a few minutes. Print timing with
    `log_msg`.

## 6. The comparison crosswalk (the important part for the dashboard)

Create `scripts/build_comparison_crosswalk.R`, which writes
`outputs/comparison_crosswalk.csv`. It **reads the four template
outputs** (not the raw sources) and writes one row for each distinct
partner `(Model, Variable, Item, Unit)`. The columns are:

| column | meaning |
|---|---|
| `Model`, `Variable`, `Item`, `Unit` | the partner entry, as written in its output |
| `GLOBIOM_Variable`, `GLOBIOM_Item_pattern`, `GLOBIOM_Unit` | matching GLOBIOM entry. `GLOBIOM_Item_pattern` may use `*` for a wildcard part, e.g. `Whea|*|Seeds` |
| `match` | `exact` (same Variable, Item and Unit), `same_concept_other_unit`, `needs_aggregation` (one side is a sum or split of the other), `candidate` (plausible, needs partner confirmation), `none` |
| `note` | one sentence on what a dashboard must do (e.g. "GLOBIOM split by management system; choose one or area-weight") |

The table must be **rule-driven**. Use a small, hand-maintained rule
table in the script, so that partners can correct it, rather than
hard-coding each row. Then check every rule against the actual GLOBIOM
output, so that a pattern which matches nothing is reported. Also write
a short `outputs/comparison_crosswalk_README.md` with match counts by
model and the list of `candidate` rows to confirm.

Starting rules, found by comparing the current outputs with
`OUTPUT_AG_REG.csv`:

**FarmDyn** (Region `DEU`, Year 2010, `Euro per ha`, `kg N per ha`, `liter per ha`)

- Crops `Whea`, `Barl`, `Rape`, `Corn` exist in GLOBIOM. `CorS`,
  `RyeG`, `SugB`, `Alfa`, `BeaF` do not, so their match is `none`.
  `BeaF` (field beans) is *not* GLOBIOM `BeaD` (dry beans); mark it
  `candidate` at most.
- COST categories that are identical in GLOBIOM: `Seeds`, `Fertiliser`,
  `Motor fuels`, `Crop protection`, `Other crop costs`. Use
  `same_concept_other_unit` (Euro per ha vs USD 2000 per ha) with the
  pattern `<crop>|*|<category>`.
- `candidate`: `Buy inputs - hired labour` vs `Labour`;
  `Mach cost - crop` vs `Contract work`; `p_vcostC` vs `Total`.
  Otherwise `none`.
- `FRTN` in kg N per ha vs GLOBIOM FRTN in `1000 t`: `needs_aggregation`
  (needs Area). Note that the dashboard can derive GLOBIOM kg/ha as
  FRTN/Area; the data file must not.
- `Area` (one farm, in 1000 ha) vs GLOBIOM `Area` per crop:
  `needs_aggregation` (farm vs country).
- `ENUS` (`<crop>|Diesel`, liter per ha): `none`. GLOBIOM only has
  diesel *cost* (`Motor fuels`).

**AgriPolis** (farm-level Regions, 2020–2029, Area only)

- `Whea`, `Barl`, `Rape`, `Pota` vs GLOBIOM `Area`: `needs_aggregation`
  (farms vs `DEU`).
- Grassland codes (`LeyG`, `GrSI`, `GrSE`, `PasS`, `PasR`, `PasC`):
  `candidate` against GLOBIOM's livestock grassland Area items
  (`BVMEAT`, `SGMEAT`, `ALMILK`). These are probably not comparable;
  ask.
- All other crops: `none`.

**OpenPROM** (Region `AUT`, annual 2010–2100)

- `CTAX` `AGR` (`$2015/tn CO2`) vs GLOBIOM `CTAX` `*` (`USD/tCO2e`):
  `same_concept_other_unit`. GLOBIOM repeats one value across emission
  sources, so the dashboard should take one source and not sum them.
- `Area` `AGR|Crops`: `needs_aggregation` (sum of GLOBIOM crop Area).
- `ARIR` `AGR|Irrigation & Water management`: `candidate`. OpenPROM's
  value is an energy-service activity relabelled 1000 ha; GLOBIOM's is
  irrigated area by crop.
- `Anim` `AGR|Livestock operations` `1000 LU` vs GLOBIOM `1000 TLU`:
  `candidate`. Ask whether LU equals TLU.
- `ENUS`, `PRIC`, `ENSV`: `none`.
- Years: only 2010, 2020, … 2050 overlap with GLOBIOM. State this in the
  crosswalk README.

Do **not** change the three partner converters as part of this task.
Collect any improvements the crosswalk suggests on the partner side
(e.g. mapping FarmDyn hired labour to `Labour` once confirmed) in a list
at the end of the crosswalk README.

## 7. Tests

Extend `tests/testthat/` and do not weaken the existing 43 tests.

- Test the `Eps` handling and that any other non-numeric value is an
  error. Use a tiny fixture written to `tempfile()`, not the 97 MB
  file.
- Test the crosswalk rule matching with mini data: exact, wildcard
  management part, and a rule that matches nothing gets reported.
- The full test command `Rscript -e "testthat::test_dir('tests/testthat')"`
  must pass.

## 8. Definition of done

- `outputs/GLOBIOM/` contains `GLOBIOM_GLOBIOM_comprehensive.csv`,
  `README.md` and `mapping_log.csv`, with 0 validation errors.
- The row count equals the source rows in scope. Report it next to the
  source count, with any difference explained (e.g. by `Eps`).
- Spot-check 5 values against the source, including one COST, one FRTN
  `1000 t dm` and one CTAX row. Cite them in the README.
- `outputs/comparison_crosswalk.csv` and its README exist. Every
  partner `(Model, Variable, Item, Unit)` has exactly one crosswalk row,
  and no rule pattern matches zero GLOBIOM rows without being flagged.
- All tests pass. Re-running both scripts gives identical md5 hashes.
- Final report to the user: what was produced, counts, decisions used
  (asked or defaulted), the `candidate` list, and open questions. No
  commit unless asked.

## 9. Decisions to confirm with the project lead (ask before coding)

| # | Question | Default if unanswered |
|---|---|---|
| A | Scope: all 59 GLOBIOM variables, or only the variables the partner models report (`Area`, `COST`, `FRTN`, `ARIR`, `Anim`, `CTAX`)? | **All variables**. GLOBIOM is the reference and the conversion is only renaming, so it carries no mapping risk. The output is about 100 MB. |
| B | COST: keep the management part (`Whea|HI|Seeds`) as reported? | **Keep it.** Comparison happens through the crosswalk. |
| C | `Eps` values (208 rows, GAMS "zero"): write them as `0`, or drop them? | **Write `0`**, list them in the mapping log and README. This is the GAMS meaning, not a unit conversion. |
| D | FRTN is reported both in `1000 t` and `1000 t dm`: keep both? | **Keep both** (Unit is part of the key). |
| E | Output file name `GLOBIOM_GLOBIOM_comprehensive.csv`, or a cleaner name such as `GLOBIOM_template.csv`? | **The consistent name.** |
| F | The `candidate` crosswalk matches in section 6: are any already known to be right or wrong? | Leave them as `candidate`. |
