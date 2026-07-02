-- Checkout rate per reco widget on the PDP (Artikeldetailseite), grouped by visitor gender
-- Denominator: page impressions on the PDP per widget per gender, deduplicated on dl_brain_message_hash.
--              Gender (user_CustomerGender) taken from the base event of the PDP page impression.
-- Numerator:   Variation feature rows on a BBS page impression where
--              feature_promo_AttributionFeature carries a reco widget _DetailView attribution,
--              deduplicated on dl_brain_message_hash. Gender taken from the base BBS event.
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
),
reco_views AS (
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures`
  |> WHERE dl_feature_name IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'Spx-Cinema')
  |> JOIN base_events USING (dl_brain_message_hash, partition_day_utc)
  |> WHERE ot_PageCluster = 'Artikeldetailseite'
  |> AGGREGATE COUNT(DISTINCT dl_brain_message_hash) AS adp_widget_impressions
     GROUP BY dl_feature_name AS reco_widget,
              user_CustomerGender AS gender
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
       user_CustomerGender AS gender
)
FROM reco_views
|> LEFT JOIN reco_checkouts USING (reco_widget, gender)
|> SET checkout_count = COALESCE(checkout_count, 0)
|> EXTEND ROUND(100.0 * checkout_count / adp_widget_impressions, 3) AS checkout_pct
|> ORDER BY gender, reco_widget
