-- Add-to-basket rate per reco widget on the ADP (Artikeldetailseite)
-- Denominator: page impressions only (ot_MessageType = 'page impression') per widget, deduplicated on dl_brain_message_hash
-- Numerator:   AddToBasket events attributed to each widget via promo_AttributionFeature, deduplicated on dl_brain_message_hash
-- Filters:     excludes internal (campus) traffic, bot-flagged sessions, and good-bots
-- Date range:  2026-06-30
-- Syntax:      BigQuery pipe syntax

WITH base_events AS (
  -- ADP events from 2026-06-30, excluding internal and bot traffic
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamic`
  |> WHERE partition_day_utc >= TIMESTAMP('2026-06-30')
       AND partition_day_utc <  TIMESTAMP('2026-07-01')
       AND ot_PageCluster = 'Artikeldetailseite'
       AND ot_InternalTraffic IS NULL
       AND ot_Bot IS NULL
       AND (bot_Classification IS NULL OR bot_Classification NOT IN ('BAD-BOT', 'GOOD-BOT'))
),
reco_views AS (
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures`
  |> WHERE dl_feature_name IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'Spx-Cinema')
  |> JOIN base_events USING (dl_brain_message_hash, partition_day_utc)
  |> WHERE ot_MessageType = 'page impression'
  |> AGGREGATE COUNT(DISTINCT dl_brain_message_hash) AS adp_widget_impressions
     GROUP BY dl_feature_name AS reco_widget
),
reco_atbs AS (
  FROM base_events
  |> WHERE REGEXP_EXTRACT(promo_AttributionFeature, r'^(.+)_DetailView$')
             IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'SpaCinema')
  |> JOIN `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures`
       USING (dl_brain_message_hash, partition_day_utc)
  |> WHERE dl_feature_name = 'AddToBasket'
  |> AGGREGATE COUNT(DISTINCT dl_brain_message_hash) AS atb_count
     GROUP BY
       CASE REGEXP_EXTRACT(promo_AttributionFeature, r'^(.+)_DetailView$')
         WHEN 'SpaCinema' THEN 'Spx-Cinema'
         ELSE REGEXP_EXTRACT(promo_AttributionFeature, r'^(.+)_DetailView$')
       END AS reco_widget
)
FROM reco_views
|> LEFT JOIN reco_atbs USING (reco_widget)
|> SET atb_count = COALESCE(atb_count, 0)
|> EXTEND ROUND(100.0 * atb_count / adp_widget_impressions, 3) AS atb_pct
|> ORDER BY atb_count DESC
