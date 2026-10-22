# AgEnRes_R

Support scripts for the AgEnRes modelling toolbox.

These R scripts translate the outputs of the partner models into one shared
GLOBIOM-style reporting format. The purpose is to compare the agent-based and
farm models with the GLOBIOM model and to soft-link them via costs,
management, fuel use and fertiliser.

Every translated file has the columns
`Model, Scenario, Region, Item, Variable, Year, Unit, Value`. Codes follow
the GLOBIOM glossary where they fit. Where nothing fits, a new code is
proposed and listed in `proposed_glossary_additions.csv`. **Values are not
converted** and keep the unit the model reports them in. The only exception
is area, which is written as 1000 ha. Every baseline is called `BASE`.

Inputs and outputs are not versioned (`inputs/`, `outputs/` are git-ignored).
Every output folder has its own `README.md` and `mapping_log.csv`.

## Usage

```
Rscript scripts/GLOBIOM_to_template.R
Rscript scripts/FarmDyn_to_template.R
Rscript scripts/AgriPolis_to_template.R
Rscript scripts/OpenPROM_to_template.R
Rscript scripts/merge_template_outputs.R     # -> outputs/merged/AllModels_GLOBIOM_comprehensive.csv
Rscript -e "testthat::test_dir('tests/testthat')"
```

The required packages are `data.table`, `readxl` and `testthat`. The shared
validation and writing code is in `scripts/shared_conversion_helpers.R`.

## Models

### GLOBIOM
- Source: `OUTPUT_AG_REG.csv`, 48 regions (countries and aggregates),
  2000–2050 in 10-year steps, scenarios `BASE` and `EPS-S1` to `EPS-S3`.
- Translated: all 59 variables, about 1.75 M rows. Only the columns are
  renamed; codes and values are kept as reported. GAMS `Eps` is written as 0.

### FarmDyn
- Source: an Excel template for one representative German arable farm, 9
  crops, 2010, scenarios `BASE` and `optimized_combine`.
- Translated:
  - crop area;
  - costs per ha by FADN-style category (Euro);
  - diesel use (litres per ha);
  - mineral N per ha.

  This gives 268 rows, with Region `DEU`.

### AgriPolis
- Source: `.dat` output files of an agent-based regional model, 92 farms,
  10 time steps (written as 2020–2029), scenario `BASE-Oct 15`.
- Translated: land use by crop and grassland type for each farm (Region =
  farm ID), 15,257 rows.

### OpenPROM
- Source: an Excel reporting template for the energy-system model (currently
  placeholder values for Austria only), annual 2010–2100, scenario `BASE`.
- Translated: for agriculture as a whole (Item `AGR|<sub-class>`), 3,276 rows:
  - energy use by carrier;
  - energy prices;
  - carbon price;
  - activity levels behind agricultural energy demand (crop area, irrigation,
    livestock, other services).
