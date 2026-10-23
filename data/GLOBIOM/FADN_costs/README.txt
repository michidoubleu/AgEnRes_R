FADN-BASED CROP PRODUCTION COSTS PER HECTARE - ADD-ON TO GLOBIOM OUTPUT
=======================================================================
Generated: 2026-10-02 by cost_shocks_energy.R (IIASA GLOBIOM FADN module, folder database/06_GLOBIOM_shocks).
Do not hand-edit the data files; rerun the R script to regenerate this whole folder.

1. WHAT THIS IS
---------------
Production cost per hectare of crop area, by EU country, crop, management system and
cost item, for the AgEnRes joint oil & gas price scenarios. It is ADDITIONAL REPORTED
INFORMATION to attach to a GLOBIOM full output. It is NOT computed by the GLOBIOM model
run: it is the cost data on the input side, from which the energy cost shocks fed into
GLOBIOM were derived (see section 5).

2. FILES
--------
FADN_costs_country_USD2000_ha.csv  MAIN FILE. The data in USD 2000 per ha (append this one).
FADN_costs_country_EUR_ha.csv      Same data in EUR/ha (original currency, 2020 price level), same rows.
dictionary_items.csv               Every Item code split into crop / management / cost item,
                                   with names, the FADN source code, whether it changes
                                   across scenarios, and how many Regions report it.
dictionary_regions.csv             Region (ISO3) -> GLOBIOM ALLCOUNTRY name, and whether the
                                   country has its own FADN data or is a proxy copy.
usd2000_conversion.csv             EUR -> USD 2000 conversion factor applied to each Year.
scenario_price_multipliers.csv     Energy price multipliers per scenario x year x commodity.
README.txt                         This file.

3. FORMAT (long / IAMC-like, one value per row, comma-separated, header row)
----------------------------------------------------------------------------
Rows: 217888 (same in the EUR file).
Columns:
  Region    character  ISO3 country code (EU27), e.g. AUT. See dictionary_regions.csv.
  Year      integer    2000, 2010, 2020, 2030, 2040.
  Scenario  character  BASE, EPS-S1, EPS-S2, EPS-S3.
  Variable  character  always COST.
  Item      character  crop|management|cost item, e.g. Whea|HI|Labour (pipe-separated).
  Unit      character  USD 2000 per ha (constant 2000 US dollars; EUR/ha in the EUR file). Per hectare of crop area.
  value     numeric    the cost, rounded to 4 decimals.
Unique key: Region + Year + Scenario + Variable + Item (no duplicates).

Example (Austria, wheat, high input, fertiliser cost, EPS-S3):
  Region,Year,Scenario,Variable,Item,Unit,value
  AUT,2000,EPS-S3,COST,Whea|HI|Fertiliser,USD 2000 per ha,34.7132
  AUT,2010,EPS-S3,COST,Whea|HI|Fertiliser,USD 2000 per ha,36.5277
  AUT,2020,EPS-S3,COST,Whea|HI|Fertiliser,USD 2000 per ha,40.6587
  AUT,2030,EPS-S3,COST,Whea|HI|Fertiliser,USD 2000 per ha,60.988
  AUT,2040,EPS-S3,COST,Whea|HI|Fertiliser,USD 2000 per ha,81.3173

4. DIMENSIONS
-------------
Scenarios:
  BASE     No energy price shock: 2020 cost levels are held constant after 2020.
  EPS-S1   Shock in 2020-2030, back to BAU by 2040 (shock resolves, does not recur).
  EPS-S2   Persistent shock: the 2030 level holds through 2040.
  EPS-S3   Escalating shock: Hormuz + Ukraine disruption twice in the 2030s, higher in 2040.
  These names are the same elements used in GLOBIOM's second scenario dimension
  (ALLSCEN2/SCEN2) for the cost shock runs; BASE is GLOBIOM's existing BASE element.

Years: 2000, 2010, 2020 are historical and IDENTICAL in every scenario. 2030, 2040 are scenario years.
  No values for other years (no interpolation was done).

Item = crop|management|cost item.
  Crops (GLOBIOM SPECIES codes):
    Barl = Barley
    BeaD = Dry beans
    ChkP = Chickpea
    Corn = Maize (grain)
    Cott = Cotton
    Pota = Potato
    Rape = Rapeseed
    Rice = Rice
    Soya = Soybean
    Srgh = Sorghum
    Sunf = Sunflower
    Whea = Wheat
  Management (GLOBIOM ALLTECH codes):
    SS = Subsistence
    LI = Low input (rainfed)
    HI = High input (rainfed)
    IR = Irrigated (high input)
  Cost items (FADN cost categories):
    Electricity       IELE_V            changes across scenarios
    Fertiliser        IFERT_V           changes across scenarios
    Heating fuels     IHFULS_V          changes across scenarios
    Motor fuels       IFULS_V           changes across scenarios
    Total             sum of all items  changes across scenarios
    Contract work     ICNTR_V           same in all scenarios
    Crop protection   IPROT_V           same in all scenarios
    Labour            LABOR_VALUE       same in all scenarios
    Other crop costs  ICRPOTH_V         same in all scenarios
    Seeds             ISED_V            same in all scenarios
    Water             IWATR_V           same in all scenarios
  528 distinct Items in total. Not every Region has every crop x management
  combination: a row exists only where there is source data. A MISSING ROW MEANS NO DATA,
  NOT ZERO COST. GLOBIOM crops Mill, Gnut, SwPo and SugC have no FADN cost data and
  therefore no rows.

5. WHERE IT COMES FROM
----------------------
Source: EU Farm Accountancy Data Network (FADN) farm-level data, processed by the
IIASA GLOBIOM FADN module (R + GAMS):
  steps 1-4  import, tabulate, outlier removal and imputation of FADN data;
  step 5     Bayesian HPD estimation of per-crop input coefficients (cost per ha per
             crop and cost category) for each country and year;
  step 5.3   mapping to GLOBIOM crops, NUTS2 regions and management systems
             -> GLOBIOM_COSTS.RDS (EUR/ha per NUTS2 x crop x management x cost item).
             The FADN 2020 estimates are the anchor; 2000 and 2010 are the 2020 costs
             scaled by GLOBIOM's output value per ha index (constant USD2000 prices),
             i.e. all historical years are in 2020 price terms.
  cost_shocks_energy.R (this folder's generator):
    - NUTS2 -> country: mean of the NUTS2 cost/ha, weighted by GLOBIOM crop area of the
      same NUTS2 x crop x management x year (unweighted mean where no area exists).
    - Scenario years: 2020 cost x scenario price multiplier of the commodity that
      prices the item (scenario_price_multipliers.csv):
        Diesel farm gas oil -> Motor fuels (IFULS_V)
        Heating oil -> Heating fuels (IHFULS_V)
        Fertiliser composite -> Fertiliser (IFERT_V)
        Natural gas -> Electricity (IELE_V)
      Natural gas is used as the proxy for electricity (gas-fired plants set the EU
      marginal electricity price). All other items keep their base-year level.
    - Total = sum of the 10 items (may differ from the item sum by <= 0.0003 because
      of rounding).
    - EUR -> USD 2000:
      All years converted with one factor of 0.759963: EUR -> USD 2020 at the ECB
      2020 annual average reference rate (1.1422 USD per EUR), then deflated to USD
      2000 with the US CPI-U (BLS, annual averages, 2000 = 172.2, 2020 = 258.811;
      factor 0.66535). One factor for all years because all costs are expressed at
      the 2020 price level.
    - 11 countries have no FADN data and carry a copy of a similar country's
      values (same proxies as in the GLOBIOM cost shock): 
        BGR <- ROU
        CYP <- GRC
        DNK <- DEU
        EST <- FIN
        HRV <- HUN
        IRL <- FRA
        LTU <- POL
        LUX <- BEL
        LVA <- POL
        MLT <- ITA
        SVN <- AUT

Relation to the GLOBIOM run: GLOBIOM receives the scenario-minus-BASE difference of
the 4 energy items as an additive shock to CROP_DATA(...,'COST') (unit 1000 EUR/ha)
at its LUID grid level (parameter COST_SHOCK, files cost_shock_energy_gams.csv /
cost_shock_energy_gams_snippet.txt in the parent folder). That grid-level shock
averages grid cells without area weights, so these country values are close to,
but not exactly, the average of what GLOBIOM used.

6. HOW TO APPEND TO A GLOBIOM FULL OUTPUT
-----------------------------------------
- Use FADN_costs_country_USD2000_ha.csv. It is already in long format; map its columns
  onto the target's columns (Region, Year, Scenario, Variable, Item, Unit, value) and
  append the rows. Do not change the numbers.
- Scenario: if the GLOBIOM output carries more scenario dimensions (e.g. SSP, RCP or
  SCEN1/SCEN3), these rows apply to all of them: match on the ALLSCEN2-type
  dimension (BASE, EPS-S1, EPS-S2, EPS-S3) and repeat the rows for the other
  dimensions, or leave those fields empty if the target format allows.
- Region: ISO3. If the GLOBIOM output uses GLOBIOM country names (ALLCOUNTRY, e.g.
  CzechRep) use the GLOBIOM_ALLCOUNTRY column of dictionary_regions.csv. These are
  country rows only; do not add them into GLOBIOM regional aggregates (EU etc.).
- Variable: COST. If the GLOBIOM output already has a variable called COST with a
  different meaning or unit, rename this one (e.g. COST_FADN) to avoid mixing them,
  and document the rename.
- Item: keep as is. If the target needs separate columns, split on '|' into crop,
  management and cost item (dictionary_items.csv has this split).
- Do NOT sum over Items: 'Total' is already included (double counting), and costs per
  ha cannot be summed across crops or management systems anyway. To aggregate, use
  area-weighted means with GLOBIOM areas.
- Years: only the years listed in section 4. Do not fill missing years or missing
  combinations with zeros.
- After appending, check: same row count as this file, no duplicate keys, no
  collision with existing rows of the target.
