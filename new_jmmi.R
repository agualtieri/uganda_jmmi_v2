## Uganda Market Monitoring - Update R Script
## Last modified 10/04/2020

## this code cleans your environment
rm(list=ls())

today <- Sys.Date()

## Download and install hypegrammaR from IMPACT GitHub
#devtools::install_github("impact-initiatives/hypegrammaR", build_opts = c())


## Load required packaged
library(openxlsx)
library(tidyverse)
library(data.table)
library(hypegrammaR)


# Sources
source("./R/locations_list.R")
source("./R/functions.R")


## Round names - these need to be changed at every round
this_round_vec <- "October"
last_round_vec <- "September"


## Load data from this round, last round, and march
this_round <- read.xlsx("./inputs/Raw market data-October 2020.xlsx") # update the code with the latest cleaned file
this_round <- this_round %>% mutate(month = as.numeric(month)) %>% mutate(settlement = str_replace(settlement, "rhino", "rhino camp"))
names(this_round)[names(this_round)=="_uuid"] <- "uuid"


## Load data from last round
last_round <- read.xlsx("inputs/Raw market data-September 2020_New_format.xlsx") # update the code with last month cleaned file
last_round <- last_round %>% mutate(month = as.numeric(month)) %>% mutate(settlement = str_replace(settlement, "rhino", "rhino camp"))
names(last_round)[names(last_round)=="X_uuid"] <- "uuid"


# Load old data and rename variables
df_march <- read.csv("inputs/March raw data.csv",stringsAsFactors=FALSE, na.strings = c(""," ","NA"))
df_march <- df_march %>% mutate(settlement = str_replace(settlement, "rhino", "rhino camp"))


### ANALYSIS

# Creating one big dataframe with all the values from past rounds
df <- rbindlist(list(this_round, last_round, df_march), fill = TRUE)

# Add the settlement coordinates to the dataset
df <- left_join(df, settlement_data, by="settlement") 

# Add district shape values to dataset
df <- left_join(df, district_data, by = "district")

# Some house cleaning 
# Remove columns that we don't need and rename our uuid columns 
df <- df %>% select(settlement:district,F15Regions,DName2019, uuid) %>%  
  select(-contains("X_"),-name, -objectid ) %>% 
  mutate(sub_regions = str_to_sentence(F15Regions))


df$regions <- "south west"
df$regions[df$sub_regions == "Acholi" | df$sub_regions == "West nile" ] <- "west nile"

df$regions[df$DISTRICT == "Bunyoro" ] <- "west nile"


# Collection period
mymonths <- c("January","February","March",
              "April","May","June",
              "July","August","September",
              "October","November","December")

df$month <- mymonths[df$month]

df <- df %>% filter(!is.na(month))


# Add new market column that includes other markets
df <- df %>%  mutate(market_final = ifelse(market == "Other",market_other,market))
df$market <- NULL
df$market_other <- NULL

# Move things around using moveme function and delete column not needed
df <- select(df, -c("day", "F15Regions", "DName2019", "sub_regions"))
df$country <- "uganda"

df <- df %>% select(c("month","country", "district", "regions", "settlement", "market_final"), everything())



## Means Calculation
# Prices columns
item_prices <- df %>%  select(uuid,month,
                              regions,district,
                              settlement,market_final,
                              contains("price"), starts_with("weight_"), -starts_with("price_increase"), -starts_with("price_decrease"),
                              -ends_with(".prices"), -starts_with("challenge."))

item_prices[item_prices == 99] <- NA
item_prices[item_prices == "yes"] <- 1

# Because WFP added "no" in the columns we now have to turn them into integers
# item_prices[ , 7:54] <- apply(item_prices[ , 7:54], 2,            
#                              function(x) as.numeric(as.character(x)))


# Recalculate non standard items
item_prices <- item_prices %>% ungroup() %>% mutate(price_dodo = price_dodo/weight_dodo,
                                                    price_cassava = price_cassava/weight_cassava,
                                                    price_fish = price_fish/weight_fish,
                                                    price_firewood = price_firewood/weight_firewood,
                                                    price_charcoal = price_charcoal/weight_charcoal)

item_prices <- item_prices %>% select(-contains("weight"), -contains("Observed"))

# Collection_order
item_prices <- item_prices %>% mutate(collection_order = ifelse(month == this_round_vec, 4,
                                                                ifelse(month == last_round_vec,3, 1)))



# Mean prices
nan_inf_to_na <- function(x) {
  y <- replace(x, is.infinite(x), NA) 
  z <- replace(y, is.nan(y), NA)
  z
}  ## function to replace Inf and NaN with NAs for a cleaner output


national_items <- item_prices %>%  
  select(-uuid, -regions, -district, -settlement, -market_final) %>% 
  group_by(month, collection_order) %>% 
  summarise_all(funs(mean(., na.rm = TRUE))) %>%
  mutate_at(vars(-group_cols()), nan_inf_to_na)


markets_items <- item_prices %>%  select(-uuid,-regions,-district) %>% 
  group_by(settlement,market_final,month) %>% 
  summarise_all(funs(mean(., na.rm = TRUE))) %>% 
  mutate_at(vars(-group_cols()), nan_inf_to_na)


settlement_items <- item_prices %>%  select(-uuid,-market_final) %>% 
  group_by(regions,district,settlement,month) %>% 
  summarise_all(funs(mean(., na.rm = TRUE))) %>%
  mutate_at(vars(-group_cols()), nan_inf_to_na)


district_items <- item_prices %>%  select(-uuid,-settlement,-market_final) %>% 
  group_by(regions,district,month) %>% 
  summarise_all(funs(mean(., na.rm = TRUE))) %>%
  mutate_at(vars(-group_cols()), nan_inf_to_na)  


region_items <- item_prices %>%  select(-uuid,-market_final,-district,-settlement) %>% 
  group_by(regions,month) %>% 
  summarise_all(funs(mean(., na.rm = TRUE))) %>%
  mutate_at(vars(-group_cols()), nan_inf_to_na)


# Counts per area: region and settlements
markets_per_region <- item_prices %>%  select(regions, month, market_final) %>% 
  group_by(regions,month) %>% 
  summarise(num_market_assessed = n_distinct(market_final),
            num_assessed = length(month)) %>% 
  rename("level"= regions) %>% filter(month == this_round_vec) %>% 
  select(level,num_market_assessed,num_assessed)


settlements_per_region <- item_prices %>%  select(regions,settlement,month) %>% 
  group_by(regions,month) %>% 
  summarise(markets_numer = n_distinct(settlement))


# Counts per area: nation wide
markets_nationwide <- item_prices %>%  select(regions, month, market_final) %>% 
  group_by(month) %>% 
  summarise(num_market_assessed = n_distinct(market_final),
            num_assessed = length(month),
            level = "national") %>% 
  filter(month == this_round_vec) %>% 
  select(level,num_market_assessed,num_assessed)


data_merge_summary <- bind_rows(markets_nationwide,markets_per_region)

# Calcualte MEBs
source("./R/meb_calc.R")

# Calculate % changes
source("./R/percent_change_calc.R")

## Data exports 
list_of_datasets_med <- list("Market mean price" = markets_items,
                         "Settlement mean price" = settlement_items,
                         "District Mean" = district_items,
                         "Region mean" = region_items,
                         "National level mean" = national_items,
                         "Percent change Settlement" = change_settlement,
                         "Percent change Region" = percent_change_region,
                         "Percent change National" = percent_change_national,
                         "Rank settlements" = rank_settlments
                         )

list_of_datasets_meb <- list("Settlement MEB" = meb_items,
                         "Regional MEB" = meb_items_regional,
                         "National MEB" = meb_items_national,
                         "Percent change MEB Settlment" = percent_change_meb_settlement,
                         "Percent change MEB Regional" = percent_change_meb_regional,
                         "Percent change MEB National" = percent_change_meb_national
                          )


## Save files
write.xlsx(list_of_datasets_med, paste0("./outputs/UGA_JMMI_Means and percentage change_",today,".xlsx"))

write.xlsx(list_of_datasets_meb, paste0("outputs/UGA_JMMI_MEB and percentage change_",today,".xlsx"))


## Market Functionality Page

### Load data analysis plan and questionnaire
dap <- load_analysisplan("./inputs/dap/jmmi_dap_v1.csv")


kobo_tool <- load_questionnaire(this_round,
                                questions = read.csv("./inputs/kobo/questions.csv"),
                                choices = read.csv("./inputs/kobo/choices.csv"),
                                choices.label.column.to.use = "label")


## Prepare dataset for analysis
df_analysis <- df %>% mutate(mobile_accepted = ifelse(grepl("mobile_money", payment_type), "yes", "no")) %>% filter(month == this_round_vec)

df_analysis$customer_number <- as.numeric(df_analysis$customer_number)
df_analysis$agents_number <- as.numeric(df_analysis$agents_number)


## Launch analysis and isolate analysis results
analysis <- from_analysisplan_map_to_output(data = df_analysis,
                                            analysisplan = dap,
                                            weighting = NULL,
                                            questionnaire = kobo_tool)
## SUMMARY STATS LIST ##
summary.stats.list <- analysis$results %>% 
  lapply(function(x){map_to_labeled(result = x, questionnaire = kobo_tool)})


## Save tabulated analysis file
summary.stats.list %>% 
                resultlist_summary_statistics_as_one_table %>% 
                select(-se, -min, -max) %>%
                map_to_file(paste0("./outputs/jmmi_analysis_",today,".csv"))


## Save html analysis file
hypegrammaR:::map_to_generic_hierarchical_html(resultlist = analysis,
                                               render_result_with = hypegrammaR:::from_result_map_to_md_table,
                                               by_analysisplan_columns = c("research.question","indicator"),
                                               by_prefix = c("RQ:", "Indicator: "),
                                               level = 2,
                                               questionnaire = kobo_tool,
                                               label_varnames = TRUE,
                                               dir = "./outputs",
                                               filename = paste0("html_analysis_jmmi_",today,".html"))


## TOP 3 Analysis
### Slice result list by areas
summary.stats.list <- analysis$results %>% resultlist_summary_statistics_as_one_table %>% select(-se, -min, -max, -repeat.var, -repeat.var.value)
vec1 <- c(1,2,3,1,2,3,1,2,3,1,2,3,1,2,3,1,2,3,1,2,3)
vec2 <- c(1,2,1,2,1,2,1,2,1,2,1,2,1,2,1,2,1,2,1,2)

## Rename based on choices from kobo
summary.stats.list$dependent.var.value <- choices$label[match(summary.stats.list$dependent.var.value, choices$name)]

## All markets 
top3_uganda <- summary.stats.list %>% filter(dependent.var == "payment_type" |
                                             dependent.var == "safety_reason_less_secure" |
                                             dependent.var == "safety_reason_more_secure" |
                                             dependent.var == "item_scarcity_reason" |
                                             dependent.var == "price_increase_item" |
                                             dependent.var == "price_decrease_item" |
                                             dependent.var == "challenge") %>% 
                                      filter(independent.var.value == "uganda") %>%
                                      arrange(desc(numbers)) %>%
                                      group_by(dependent.var) %>%
                                      slice(1:3)

## Add ranking col and rename the options
top3_uganda$rank <- vec1

## New var for data merge and pivot wider
top3_uganda <- top3_uganda %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                                       select(new_var, numbers, dependent.var.value) %>%
                                       pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))


## South West Region
top3_southwest <- summary.stats.list %>% filter(dependent.var == "payment_type" |
                                                dependent.var == "safety_reason_less_secure" |
                                                dependent.var == "safety_reason_more_secure" |
                                                dependent.var == "item_scarcity_reason" |
                                                dependent.var == "price_increase_item" |
                                                dependent.var == "price_decrease_item" |
                                                dependent.var == "challenge") %>% 
                                        filter(independent.var.value == "south west") %>%
                                        arrange(desc(numbers)) %>%
                                        group_by(dependent.var) %>%
                                        slice(1:3)
## Add ranking col
top3_southwest$rank <- vec1

## New var for datamerge and pivot wider
top3_southwest <- top3_southwest %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>%  ungroup() %>%
                                     select(new_var, numbers, dependent.var.value) %>% 
                                     pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))




## West Nile regions
top3_westnile<- summary.stats.list %>% filter(dependent.var == "payment_type" |
                                              dependent.var == "safety_reason_less_secure" |
                                              dependent.var == "safety_reason_more_secure" |
                                              dependent.var == "item_scarcity_reason" |
                                              dependent.var == "price_increase_item" |
                                              dependent.var == "price_decrease_item" |
                                              dependent.var == "challenge") %>%
                                      filter(independent.var.value == "west nile") %>% 
                                      arrange(desc(numbers)) %>%
                                      group_by(dependent.var) %>%
                                      slice(1:3)

## Add ranking col
top3_westnile$rank <- vec1


## New var for datamerge and pivot wider
top3_westnile <- top3_westnile %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                                   select(new_var, numbers, dependent.var.value) %>% 
                                   pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))





## TOP 2 Analysis - Increase in price

## All markets 
top2_uganda <- summary.stats.list %>% filter(dependent.var == "cereal_increase_reason" |
                                             dependent.var == "cassava_increase_reason" |
                                             dependent.var == "beans_increase_reason" |
                                             dependent.var == "vegetables_increase_reason" |
                                             dependent.var == "milk_increase_reason" |
                                             dependent.var == "fish_increase_reason" |
                                             dependent.var == "oil_increase_reason" |
                                             dependent.var == "salt_increase_reason" |
                                             dependent.var == "wash_increase_reason" |
                                             dependent.var == "energy_increase_reason") %>% 
                                      filter(independent.var.value == "uganda") %>%
                                      arrange(desc(numbers)) %>%
                                      group_by(dependent.var) %>%
                                      slice(1:2)
## Add ranking col
top2_uganda$rank <- vec2

## New var for datamerge and pivot wider
top2_uganda <- top2_uganda %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                               select(dependent.var.value,  new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))


## South West
top2_southwest <- summary.stats.list %>% filter(dependent.var == "cereal_increase_reason" |
                                                dependent.var == "cassava_increase_reason" |
                                                dependent.var == "beans_increase_reason" |
                                                dependent.var == "vegetables_increase_reason" |
                                                dependent.var == "milk_increase_reason" |
                                                dependent.var == "fish_increase_reason" |
                                                dependent.var == "oil_increase_reason" |
                                                dependent.var == "salt_increase_reason" |
                                                dependent.var == "wash_increase_reason" |
                                                dependent.var == "energy_increase_reason") %>% 
                                         filter(independent.var.value == "south west") %>%
                                         arrange(desc(numbers)) %>%
                                         group_by(dependent.var) %>%
                                         slice(1:2)
## Add ranking col
top2_southwest$rank <- vec2

## New var for datamerge and pivot wider
top2_southwest <- top2_southwest %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                                     select(dependent.var.value,  new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))


## West Nile
top2_westnile <- summary.stats.list %>% filter(dependent.var == "cereal_increase_reason" |
                                               dependent.var == "cassava_increase_reason" |
                                               dependent.var == "beans_increase_reason" |
                                               dependent.var == "vegetables_increase_reason" |
                                               dependent.var == "milk_increase_reason" |
                                               dependent.var == "fish_increase_reason" |
                                               dependent.var == "oil_increase_reason" |
                                               dependent.var == "salt_increase_reason" |
                                               dependent.var == "wash_increase_reason" |
                                               dependent.var == "energy_increase_reason") %>% 
                                       filter(independent.var.value == "west nile") %>%
                                       arrange(desc(numbers)) %>%
                                       group_by(dependent.var) %>%
                                       slice(1:2)
## Add ranking col
top2_westnile$rank <- vec2

## New var for datamerge and pivot wider
top2_westnile <- top2_westnile %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                                   select(dependent.var.value,  new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))





## TOP 2 Analysis - Decrease in price

## All markets 
top2_uganda_dec <- summary.stats.list %>% filter(dependent.var == "cereal_decrease_reason" |
                                                 dependent.var == "cassava_decrease_reason" |
                                                 dependent.var == "beans_decrease_reason" |
                                                 dependent.var == "vegetables_decrease_reason" |
                                                 dependent.var == "milk_decrease_reason" |
                                                 dependent.var == "fish_decrease_reason" |
                                                 dependent.var == "oil_decrease_reason" |
                                                 dependent.var == "salt_decrease_reason" |
                                                 dependent.var == "wash_decrease_reason" |
                                                 dependent.var == "energy_decrease_reason") %>% 
                                         filter(independent.var.value == "uganda") %>%
                                         arrange(desc(numbers)) %>%
                                         group_by(dependent.var) %>%
                                         slice(1:2)
## Add ranking col
top2_uganda_dec$rank <- vec2

## New var for datamerge and pivot wider
top2_uganda_dec <- top2_uganda_dec %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                                       select(dependent.var.value,  new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))




## South West 
top2_southwest_dec <- summary.stats.list %>% filter(dependent.var == "cereal_decrease_reason" |
                                                    dependent.var == "cassava_decrease_reason" |
                                                    dependent.var == "beans_decrease_reason" |
                                                    dependent.var == "vegetables_decrease_reason" |
                                                    dependent.var == "milk_decrease_reason" |
                                                    dependent.var == "fish_decrease_reason" |
                                                    dependent.var == "oil_decrease_reason" |
                                                    dependent.var == "salt_decrease_reason" |
                                                    dependent.var == "wash_decrease_reason" |
                                                    dependent.var == "energy_decrease_reason") %>% 
                                              filter(independent.var.value == "south west") %>%
                                              arrange(desc(numbers)) %>%
                                              group_by(dependent.var) %>%
                                              slice(1:2)
## Add ranking col
top2_southwest_dec$rank <- vec2

## New var for datamerge and pivot wider
top2_southwest_dec <- top2_southwest_dec %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                                             select(dependent.var.value,  new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))



## West Nile 
top2_westnile_dec <- summary.stats.list %>% filter(dependent.var == "cereal_decrease_reason" |
                                                    dependent.var == "cassava_decrease_reason" |
                                                    dependent.var == "beans_decrease_reason" |
                                                    dependent.var == "vegetables_decrease_reason" |
                                                    dependent.var == "milk_decrease_reason" |
                                                    dependent.var == "fish_decrease_reason" |
                                                    dependent.var == "oil_decrease_reason" |
                                                    dependent.var == "salt_decrease_reason" |
                                                    dependent.var == "wash_decrease_reason" |
                                                    dependent.var == "energy_decrease_reason") %>% 
                                            filter(independent.var.value == "west nile") %>%
                                            arrange(desc(numbers)) %>%
                                            group_by(dependent.var) %>%
                                            slice(1:2)
## Add ranking col
top2_westnile_dec$rank <- vec2

## New var for datamerge and pivot wider
top2_westnile_dec <- top2_westnile_dec %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",rank)) %>% ungroup() %>%
                                            select(dependent.var.value,  new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))


## Bind all together in one data merge-ready file, multiply by 100 and round up
top_analysis <- cbind(top3_uganda, top3_southwest, top3_westnile, top2_uganda, top2_uganda_dec, top2_southwest,
                      top2_southwest_dec, top2_westnile, top2_westnile_dec)

cols <- sapply(top_analysis, is.numeric)
top_analysis[, cols] <- top_analysis[, cols] * 100


## Select one and other analysis spread

## All markets
non_perct_vars <- summary.stats.list %>% filter(dependent.var == "agents_number" |
                                                dependent.var == "customer_number") %>%
                                         filter(independent.var.value == "uganda")
                                        

## New var for datamerge and pivot wider
non_perct_vars <- non_perct_vars %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var)) %>% ungroup() %>%
                                      select(new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers))


## South West
non_perct_vars_southwest <- summary.stats.list %>% filter(dependent.var == "agents_number" |
                                                          dependent.var == "customer_number") %>%
                                                   filter(independent.var.value == "south west")


## New var for datamerge and pivot wider
non_perct_vars_southwest <- non_perct_vars_southwest %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var)) %>% ungroup() %>%
                                                         select(new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers))


## West Nile
non_perct_vars_westnile <- summary.stats.list %>% filter(dependent.var == "agents_number" |
                                                         dependent.var == "customer_number") %>%
                                                  filter(independent.var.value == "west nile")


## New var for datamerge and pivot wider
non_perct_vars_westnile <- non_perct_vars_westnile %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var)) %>% ungroup() %>%
                                                       select(new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers))


## Cbind the non-percent analysis
non_perct_vars_fin <- cbind(non_perct_vars, non_perct_vars_southwest, non_perct_vars_westnile)

## All markets
perct_vars <- summary.stats.list %>% filter(dependent.var == "mobile_accepted" |
                                            dependent.var == "vendor_number" |
                                            dependent.var == "vendors_change" |
                                            dependent.var == "safety" |
                                            dependent.var == "item_scarcity" |
                                            dependent.var == "stock_runout") %>%
                                    filter(independent.var.value == "uganda")


## New var for datamerge and pivot wider
perct_vars <- perct_vars %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",dependent.var.value)) %>% ungroup() %>%
                                    select(dependent.var.value, new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))


## South West
perct_vars_southwest <- summary.stats.list %>% filter(dependent.var == "mobile_accepted" |
                                                      dependent.var == "vendor_number" |
                                                      dependent.var == "vendors_change" |
                                                      dependent.var == "safety" |
                                                      dependent.var == "item_scarcity" |
                                                      dependent.var == "stock_runout") %>%
                                               filter(independent.var.value == "south west")


## New var for datamerge and pivot wider
perct_vars_southwest <- perct_vars_southwest %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",dependent.var.value)) %>% ungroup() %>%
                                                 select(dependent.var.value, new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))


## West Nile
perct_vars_westnile <- summary.stats.list %>% filter(dependent.var == "mobile_accepted" |
                                                     dependent.var == "vendor_number" |
                                                     dependent.var == "vendors_change" |
                                                     dependent.var == "safety" |
                                                     dependent.var == "item_scarcity" |
                                                     dependent.var == "stock_runout") %>%
                                              filter(independent.var.value == "west nile")


## New var for datamerge and pivot wider
perct_vars_westnile <- perct_vars_westnile %>% mutate(new_var = paste0(independent.var.value,"_",dependent.var,"_",dependent.var.value)) %>% ungroup() %>%
                                               select(dependent.var.value, new_var, numbers) %>% pivot_wider(names_from = new_var, values_from = c(numbers, dependent.var.value))


## Bind all together in one data merge-ready file, multiply by 100 and round up
perct_vars_fin <- cbind(perct_vars, perct_vars_southwest, perct_vars_westnile)

cols <- sapply(perct_vars_fin, is.numeric)
perct_vars_fin[, cols] <- perct_vars_fin[, cols] * 100



## Launch script that pivots all the prices, mebs, and percent changes, and most expensive settlements
source("./R/data_merge.R")


## Cbind everything, round up, and save as a csv file
data_merge_final <- cbind(top_analysis, 
                          non_perct_vars_fin, 
                          perct_vars_fin,
                          data_merge)

cols <- sapply(data_merge_final, is.numeric)
data_merge_final[, cols] <- round(data_merge_final[, cols], 0)

## Save
write.csv(data_merge_final, paste0("./outputs/jmmi_data merge_",today,".csv"), na = "n/a", row.names = FALSE)
