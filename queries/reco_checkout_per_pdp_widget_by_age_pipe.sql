-- Checkout rate per reco widget on the PDP (Artikeldetailseite), grouped by visitor age group
-- Denominator: page impressions on the PDP per widget per age group, deduplicated on dl_brain_message_hash.
--              Age group derived from user_Age on the base PDP event:
--              under_25 (<25), 25_to_39 (25-39), 40_to_54 (40-54), 55_plus (55+).
-- Numerator:   Variation feature rows on a BBS page impression where
--              feature_promo_AttributionFeature carries a reco widget _DetailView attribution,
--              deduplicated on dl_brain_message_hash. Age group from the base BBS event.
-- Filters:     excludes internal (campus) traffic, bot-flagged sessions, and good-bots
-- Date range:  2025-09-18T09:00:00 – 2025-09-19T09:00:00
-- Syntax:      BigQuery pipe syntax

WITH base_events AS (
  -- PDP and BBS page impressions in the date window, excluding internal and bot traffic
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamic`
  |> WHERE partition_day_utc >= TIMESTAMP('2025-09-18T09:00:00')
       AND partition_day_utc <  TIMESTAMP('2025-09-19T09:00:00')
       AND ot_PageCluster IN ('Artikeldetailseite', 'BBS')
       AND ot_MessageType = 'page impression'
       AND ot_InternalTraffic IS NULL
       AND ot_Bot IS NULL
       AND (bot_Classification IS NULL OR bot_Classification NOT IN ('BAD-BOT', 'GOOD-BOT'))
  |> EXTEND CASE
       WHEN SAFE_CAST(user_Age AS INT64) < 25 THEN 'under_25'
       WHEN SAFE_CAST(user_Age AS INT64) BETWEEN 25 AND 39 THEN '25_to_39'
       WHEN SAFE_CAST(user_Age AS INT64) BETWEEN 40 AND 54 THEN '40_to_54'
       WHEN SAFE_CAST(user_Age AS INT64) >= 55 THEN '55_plus'
     END AS age_group
),
reco_views AS (
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures`
  |> WHERE dl_feature_name IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'Spx-Cinema')
  |> JOIN base_events USING (dl_brain_message_hash, partition_day_utc)
  |> WHERE ot_PageCluster = 'Artikeldetailseite'
  |> AGGREGATE COUNT(DISTINCT dl_brain_message_hash) AS adp_widget_impressions
     GROUP BY dl_feature_name AS reco_widget, age_group
),
reco_checkouts AS (
  FROM base_events
  |> WHERE ot_PageCluster = 'BBS'
  |> JOIN `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures`
       USING (dl_brain_message_hash, partition_day_utc)
  |> WHERE dl_feature_name = 'Variation'
       AND REGEXP_EXTRACT(feature_promo_AttributionFeature, r'^(.+)_DetailView$')
             IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'SpaCinema')
  |> AGGREGATE COUNT(DISTINCT dl_brain_message_hash) AS checkout_count
     GROUP BY
       CASE REGEXP_EXTRACT(feature_promo_AttributionFeature, r'^(.+)_DetailView$')
         WHEN 'SpaCinema' THEN 'Spx-Cinema'
         ELSE REGEXP_EXTRACT(feature_promo_AttributionFeature, r'^(.+)_DetailView$')
       END AS reco_widget,
       age_group
)
FROM reco_views
|> LEFT JOIN reco_checkouts USING (reco_widget, age_group)
|> SET checkout_count = COALESCE(checkout_count, 0)
|> EXTEND ROUND(100.0 * checkout_count / adp_widget_impressions, 3) AS checkout_pct
|> ORDER BY age_group, reco_widget
