# =============================================================================
# GLOBIOM economic indicators (VAAD, BUDG, BUDG_1stP, BUDG_2ndP), sourced by
# scripts/GLOBIOM_to_template.R. Ported from the GLOBIOM_to_AgMIP routine (IIASA).
#
# Expects in the calling environment:
#   GLOBIOM.file      GLOBIOM output GDX (symbol OUTPUT)
#   costs.file        exogenous cost per ha by country and GLOBIOM item
#   region_map        data.table(region, region_61) from REGION_AG_MAP
#   compose_scenario  scenario naming (scripts/GLOBIOM_processing.R)
# Creates Econ_tidy (Model, Scenario, Region, Item, Variable, Year, Unit, Value).
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(data.table)
})

# -------------------------
# Read GDX
# -------------------------
output_econ <- tryCatch(
  gamstransfer::readGDX(GLOBIOM.file, symbols = "OUTPUT"),
  error = function(e) stop("Failed to read OUTPUT: ", e$message)
)

output_econ <- output_econ$OUTPUT$records
new_names <- c("ALLRUN", "VAR_ID", "VAR_UNIT", "ANYREGION", "ITEM_AG",
               "ALLSCEN1","ALLSCEN2","ALLSCEN3","Year","Value")
colnames(output_econ) <- new_names

# Scenario name = SCEN2 (as for the other GLOBIOM variables)
output_econ <- compose_scenario(output_econ)

# Units used throughout (all money in Mio USD until the final /1000 -> bn):
#   Prod, Feed: 1000 t (fresh weight, "1000 t dm" excluded)
#   XPRP:       USD 2000 per ton (per GJ / per m3 prices excluded)
#   Area:       1000 ha
#   BUDG:       Mn USD 2000
#   costs.file: 1000 EUR/ha (crop and grassland items on the same scale)
price.unit <- "USD 2000 per ton"

costs <- read.csv(costs.file)
costs <- costs[!is.na(costs$ALLITEM) & costs$ALLITEM != "", ] # trailing empty rows in the csv
cost.items <- unique(costs$ALLITEM)



##### Crop sector - BEGIN #####

area.item <- output_econ %>% filter(ITEM_AG %in% cost.items, VAR_ID=="Area", VAR_UNIT=="1000 ha") %>% mutate(area=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)
prod.item <- output_econ %>% filter(ITEM_AG %in% cost.items, VAR_ID=="Prod", VAR_UNIT=="1000 t") %>% mutate(prod=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)
prices <- output_econ %>% filter(ITEM_AG %in% cost.items, VAR_ID=="XPRP", VAR_UNIT==price.unit) %>% mutate(price=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)
subsidies <- output_econ %>% filter(ITEM_AG %in% cost.items, VAR_ID=="BUDG", VAR_UNIT=="Mn USD 2000") %>% mutate(subs=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)

full <- prices %>% left_join(prod.item) %>% 
  left_join(area.item) %>% 
  left_join(subsidies) %>% 
  left_join(costs %>% 
              group_by(country, ALLITEM) %>% 
              summarise(cost=sum(value)) %>% 
              mutate(ANYREGION=paste0(country,"Reg")) %>% ungroup() %>%
              dplyr::select(-country) %>% rename("ITEM_AG"="ALLITEM"))

# Scope = regions/items with LAMASUS costs; within that scope missing
# prod/area/subsidies are zero (previously na.omit() dropped the whole row,
# e.g. revenue and cost of every crop without a BUDG entry)
crop.sector.res <- full %>%
  filter(!is.na(cost), !is.na(price)) %>%
  mutate(across(c(prod, area, subs), ~replace_na(.x, 0))) %>%
  # cost (1000 EUR/ha) * area (1000 ha) = Mio; price (USD/t) * prod (1000 t) / 1000 = Mio
  mutate(econ.cost=cost*area, econ.rev=price*prod/1000, econ.sub=subs, econ.inc=econ.rev-econ.cost+econ.sub)
# 
# df_plot <- full %>% filter(ALLSCEN3%in%c('BASE','EA','FP','CP')) %>%
#   mutate(
#     C.econ.cost = cost * area,
#     B.econ.rev  = price * prod / 1000,
#     D.econ.sub  = subs,
#     A.econ.inc  = B.econ.rev - C.econ.cost + D.econ.sub
#   ) %>%
#   select(ANYREGION, Year, ALLSCEN3, ITEM_AG, A.econ.inc, D.econ.sub, B.econ.rev, C.econ.cost) %>%
#   na.omit()   %>%
#   pivot_longer(
#     cols = contains("econ"),
#     names_to = "variable",
#     values_to = "value"
#   )
# 
# df_plot <- df_plot %>%
#   group_by(ALLSCEN3, Year, variable) %>%
#   summarise(value = sum(value))
# 
# ggplot(
#   df_plot,
#   aes(x = Year, y = value, color = ALLSCEN3, group = ALLSCEN3)
# ) +
#   geom_line(linewidth = 1) +
#   facet_grid(~ variable) +
#   theme_minimal() +
#   labs(
#     title = "Economic quantities - crop sector",
#     y = "Mio USD"
# )

##### Crop sector - END #####


##### Livestock sector - BEGIN #####

# Define Livestock items
ls.items <- c("BVMEAT", "SGMEAT", "PGMEAT", "PTMEAT", "ALMILK", "PTEGGS")
ls.items.subs <- c("PIGS", "BOVD", "BOVO", "BOVF", "SGTD", "SGTO", "PTRB", "PTRH", "PTRX")

# 1. Base Data Extraction
prod.ls <- output_econ %>% filter(ITEM_AG %in% ls.items, VAR_ID=="Prod", VAR_UNIT=="1000 t") %>% mutate(prod=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)
prices.ls <- output_econ %>% filter(ITEM_AG %in% ls.items, VAR_ID=="XPRP", VAR_UNIT==price.unit) %>% mutate(price=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)
subsidies.ls <- output_econ %>% filter(ITEM_AG %in% ls.items.subs, VAR_ID=="BUDG", VAR_UNIT=="Mn USD 2000") %>% mutate(subs=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)

# 2a. Aggregate Revenues per Region/Year/Scenario
rev_ls_agg <- prices.ls %>% 
  left_join(prod.ls, by = c("ANYREGION", "Year", "ALLSCEN3", "ITEM_AG")) %>% 
  mutate(
    # price (USD/t) * prod (1000 t) = 1000 USD. Divide by 1000 -> Mio USD
    rev_mio = (price * prod) / 1000
  ) %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(
    B.econ.rev = sum(rev_mio, na.rm = TRUE),
    .groups = "drop"
  )

# 2b. Aggregate Subsidies per Region/Year/Scenario
sub_ls_agg <- subsidies.ls %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(
    D.econ.sub = sum(subs, na.rm = TRUE),
    .groups = "drop"
  )

# 2c. Combine Aggregated Revenues and Subsidies
rev_sub_ls <- rev_ls_agg %>%
  full_join(sub_ls_agg, by = c("ANYREGION", "Year", "ALLSCEN3")) %>%
  mutate(
    # Replace NAs with 0 in case a region/year has revenues but no subsidies, or vice versa
    B.econ.rev = replace_na(B.econ.rev, 0),
    D.econ.sub = replace_na(D.econ.sub, 0)
  )

# 2. Feed Costs (Tons of crops * Price of crops)
# Assuming VAR_ID == "Feed" records the crops used, so ITEM_AG is the crop name.
# Feed is reported both in "1000 t" and "1000 t dm" -- only fresh tons match the per-ton prices
feed_quantities <- output_econ %>% filter(VAR_ID=="Feed", VAR_UNIT=="1000 t") %>% mutate(feed_tons=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)
crop_prices <- output_econ %>% filter(VAR_ID=="XPRP", VAR_UNIT==price.unit) %>% mutate(price=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value)

feed_costs <- feed_quantities %>%
  left_join(crop_prices, by = c("ANYREGION", "Year", "ALLSCEN3", "ITEM_AG")) %>%
  mutate(
    # feed_tons (1000 t) * price (USD/t) = 1000 USD. Divide by 1000 -> Mio USD
    feed_cost_mio = (feed_tons * price) / 1000
  ) %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(total_feed_cost = sum(feed_cost_mio, na.rm = TRUE), .groups = "drop")

# 3. Grassland Costs (Grassland area in 1000ha * csv cost in EUR/ha)
grass_area <- output_econ %>% filter(ITEM_AG=="2.Grassland", VAR_ID=="LAND2", VAR_UNIT=="1000 ha") %>% mutate(area_1000ha=Value) %>% dplyr::select(-VAR_UNIT, -VAR_ID, -Value) %>% mutate(ITEM_AG="Grassland")

grass_cost_rate <- costs %>% 
  filter(ALLITEM == "Grassland") %>%
  group_by(country, ALLITEM) %>% 
  summarise(cost_per_ha=sum(value), .groups="drop") %>% 
  mutate(ANYREGION=paste0(country,"Reg")) %>% 
  dplyr::select(-country) %>% 
  rename("ITEM_AG"="ALLITEM")

grass_costs <- grass_area %>%
  left_join(grass_cost_rate, by = c("ANYREGION", "ITEM_AG")) %>%
  mutate(
    # area (1000 ha) * cost_per_ha (1000 EUR/ha) = Mio EUR (treated as USD),
    # same as the crop costs above (the former extra /1000 put this in bn)
    grass_cost_mio = area_1000ha * cost_per_ha
  ) %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(total_grass_cost = sum(grass_cost_mio, na.rm = TRUE), .groups = "drop")

# 4. Combine all components into the full Livestock dataframe
full_ls <- rev_sub_ls %>%
  full_join(feed_costs, by = c("ANYREGION", "Year", "ALLSCEN3")) %>%
  full_join(grass_costs, by = c("ANYREGION", "Year", "ALLSCEN3")) %>%
  mutate(
    # Replace NAs with 0 before doing math
    across(c(B.econ.rev, D.econ.sub, total_feed_cost, total_grass_cost), ~replace_na(.x, 0)),
    C.econ.cost = total_feed_cost + total_grass_cost,
    A.econ.inc  = B.econ.rev - C.econ.cost + D.econ.sub
  ) %>% filter(ANYREGION %in% unique(crop.sector.res$ANYREGION))

# # 5. Prepare dataframe for plotting
# df_plot_ls <- full_ls %>%
#   select(ANYREGION, Year, ALLSCEN3, A.econ.inc, D.econ.sub, B.econ.rev, C.econ.cost) %>%
#   pivot_longer(
#     cols = contains("econ"),
#     names_to = "variable",
#     values_to = "value"
#   ) %>% 
#   group_by(ALLSCEN3, Year, variable) %>% 
#   summarise(value = sum(value, na.rm = TRUE), .groups="drop")
# 
# # 6. Plotting
# ggplot(
#   df_plot_ls %>% filter(variable=="A.econ.inc"),
#   aes(x = Year, y = value, color = ALLSCEN3, group = ALLSCEN3)
# ) +
#   geom_line(linewidth = 1) +
#   theme_minimal() +
#   labs(
#     title = "Economic quantities - Livestock sector",
#     y = "Mio USD"
#   )

##### Livestock sector - END #####



##### Combined Regional Reporting - BEGIN #####

# 1. Aggregate Crop Sector per Region/Year/Scenario
# Summarise the item-level crop data up to the regional level
crop_region <- crop.sector.res %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(
    crop_rev  = sum(econ.rev, na.rm = TRUE),
    crop_cost = sum(econ.cost, na.rm = TRUE),
    crop_sub  = sum(econ.sub, na.rm = TRUE),
    crop_inc  = sum(econ.inc, na.rm = TRUE),
    .groups = "drop"
  )

# 2. Prepare Livestock Sector per Region/Year/Scenario
# full_ls is already at the regional level, so we just select and rename
ls_region <- full_ls %>%
  select(ANYREGION, Year, ALLSCEN3, 
         ls_rev  = B.econ.rev, 
         ls_cost = C.econ.cost, 
         ls_sub  = D.econ.sub, 
         ls_inc  = A.econ.inc)

# 3. Extract Total Subsidies ("TOT" item in BUDG)
tot_sub_data <- output_econ %>%
  filter(ITEM_AG == "TOT", VAR_ID == "BUDG", VAR_UNIT == "Mn USD 2000") %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(tot_sub = sum(Value, na.rm = TRUE), .groups = "drop")

# 3b. Extract CAP Pillar 1 (direct payments) / Pillar 2 (rural development)
# subsidies from the payment-scheme ITEM_AG codes under BUDG. These codes are
# not commodity-linked, so unlike tot_sub above there is no crop/livestock
# split available for them -- see scripts/GLOBIOM_CAP_BUDG_pillar_mapping.md for the
# full code -> pillar mapping and the reasoning/confidence behind it.
pillar1_codes <- c("dp_bps", "DPSAPS", "DPBPS_SAPS", "DPAGG_biss", "DPGREEN", "DPYOUNG",
                    "DPAGG_cisyf", "dpVcs", "DPAGG_cispr", "DPAGG_cotto", "DPCSCS", "DP68",
                    "DPAGG_criss", "DPFIRHA", "DPREG", "DPAGG_ecos", "DPNAT", "DPFRMF", "DPFRMS")
pillar2_codes <- c("DPRD_LFA", "DPRD_N2K", "DPRD_SeExte", "DPAE", "DPAGG_envc",
                    "DPAGG_ANC7", "DPNATCO")

pillar1_sub_data <- output_econ %>%
  filter(ITEM_AG %in% pillar1_codes, VAR_ID == "BUDG", VAR_UNIT == "Mn USD 2000") %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(pillar1_sub = sum(Value, na.rm = TRUE), .groups = "drop")

pillar2_sub_data <- output_econ %>%
  filter(ITEM_AG %in% pillar2_codes, VAR_ID == "BUDG", VAR_UNIT == "Mn USD 2000") %>%
  group_by(ANYREGION, Year, ALLSCEN3) %>%
  summarise(pillar2_sub = sum(Value, na.rm = TRUE), .groups = "drop")

# 4. Combine and Calculate Final Reporting Variables
regional_report <- crop_region %>%
  full_join(ls_region, by = c("ANYREGION", "Year", "ALLSCEN3")) %>%
  full_join(tot_sub_data, by = c("ANYREGION", "Year", "ALLSCEN3")) %>%
  full_join(pillar1_sub_data, by = c("ANYREGION", "Year", "ALLSCEN3")) %>%
  full_join(pillar2_sub_data, by = c("ANYREGION", "Year", "ALLSCEN3")) %>%
  mutate(
    # Replace NAs with 0 so math doesn't fail if a region lacks crops or livestock
    across(where(is.numeric), ~replace_na(.x, 0)),

    # Calculate Other Subsidies (Total BUDG minus specific Crop and Livestock subsidies)
    other_sub = tot_sub - crop_sub - ls_sub,
    other_sub = ifelse(other_sub<0,0,other_sub),

    # Calculate Total Income
    tot_inc = crop_inc + ls_inc + other_sub
  ) %>%
  # Organize columns for a clean final report
  select(ANYREGION, Year, ALLSCEN3,
         crop_inc, crop_rev, crop_cost, crop_sub,
         ls_inc, ls_rev, ls_cost, ls_sub,
         tot_inc, tot_sub, other_sub, pillar1_sub, pillar2_sub)

##### Combined Regional Reporting - END #####



# Map to new regions and aggregate
regional_report <- regional_report %>%
  # 1. Join the mapping data using left_join
  # region_map (region_61 -> region), built in scripts/GLOBIOM_to_template.R
  left_join(
    region_map %>%
      rename(ANYREGION = region_61) %>%
      filter(region != "World"),
    by = "ANYREGION",
    relationship = "many-to-many" # Replaces allow.cartesian = TRUE
  ) %>%
  # 2. Drop any original regions that didn't get mapped to a new region
  filter(!is.na(region)) %>%
  # 3. Group by the NEW region, Year, and Scenario
  group_by(region, Year, ALLSCEN3) %>%
  # 4. Sum all the numeric economic columns for the new regional grouping
  summarise(
    across(where(is.numeric), ~ sum(.x, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  # 5. Rename the new 'region' column back to 'ANYREGION' 
  # This ensures your downstream Econ_tidy script doesn't break!
  rename(ANYREGION = region)

Econ_tidy <- regional_report %>%
  # 1. Rename columns to match the "Item_Variable" pattern for easy pivoting
  select(
    Region   = ANYREGION, 
    Scenario = ALLSCEN3, 
    Year,
    CRP_VAAD = crop_inc, 
    LSP_VAAD = ls_inc, 
    TOT_VAAD = tot_inc,
    CRP_BUDG = crop_sub, 
    LSP_BUDG = ls_sub, 
    TOT_BUDG = tot_sub
  ) %>%
  # 2. Pivot the data from wide to long
  pivot_longer(
    cols = contains("_"),
    names_to = c("Item", "Variable"),
    names_sep = "_",
    values_to = "Value"
  ) %>%
  # 3. Add the static columns, convert units, and fix the Year factor
  mutate(
    Model = "GLOBIOM",
    Unit  = "bn USD 2005 MER",
    Year  = as.integer(as.character(Year)),
    Value = Value / 1000 # Converting from Millions to Billions
  ) %>%
  # 4. Reorder columns to exactly match your requested layout
  select(Model, Scenario, Region, Item, Variable, Year, Unit, Value)

# CAP Pillar 1 / Pillar 2 payments -- reported at "Total" item level only
# (built separately from the pivot above because "BUDG_1stP"/"BUDG_2ndP"
# contain a second underscore that pivot_longer's names_sep would mis-split)
budg_pillar_tidy <- regional_report %>%
  select(Region = ANYREGION, Scenario = ALLSCEN3, Year, pillar1_sub, pillar2_sub) %>%
  pivot_longer(
    cols = c(pillar1_sub, pillar2_sub),
    names_to = "Variable",
    values_to = "Value"
  ) %>%
  mutate(
    Model    = "GLOBIOM",
    Item     = "TOT",
    Variable = ifelse(Variable == "pillar1_sub", "BUDG_1stP", "BUDG_2ndP"),
    Unit     = "bn USD 2005 MER",
    Year     = as.integer(as.character(Year)),
    Value    = Value / 1000 # Converting from Millions to Billions
  ) %>%
  select(Model, Scenario, Region, Item, Variable, Year, Unit, Value)

Econ_tidy <- as.data.table(bind_rows(Econ_tidy, budg_pillar_tidy))
Econ_tidy[, `:=`(Scenario = as.character(Scenario), Region = as.character(Region))]


