-- Add-to-basket rate per reco widget on the ADP (Artikeldetailseite)
-- Denominator: page impressions only (ot_MessageType = 'page impression') per widget, deduplicated on dl_brain_message_hash
-- Numerator:   AddToBasket events attributed to each widget via promo_AttributionFeature, deduplicated on dl_brain_message_hash
-- Filters:     excludes internal (campus) traffic, bot-flagged sessions, and good-bots
-- Date range:  2026-06-30

WITH base_events AS (
  -- ADP events from 2026-06-30, excluding internal and bot traffic
  SELECT
    dl_brain_message_hash,
    partition_day_utc,
    ot_MessageType,
    promo_AttributionFeature
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamic`
  WHERE partition_day_utc >= TIMESTAMP('2026-06-30')
    AND partition_day_utc <  TIMESTAMP('2026-07-01')
    AND ot_PageCluster = 'Artikeldetailseite'
    AND ot_InternalTraffic IS NULL
    AND ot_Bot IS NULL
    AND (bot_Classification IS NULL OR bot_Classification NOT IN ('BAD-BOT', 'GOOD-BOT'))
),
reco_views AS (
  SELECT
    f.dl_feature_name AS reco_widget,
    COUNT(DISTINCT f.dl_brain_message_hash) AS adp_widget_impressions
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures` f
  JOIN base_events b
    ON f.dl_brain_message_hash = b.dl_brain_message_hash
   AND f.partition_day_utc = b.partition_day_utc
  WHERE f.dl_feature_name IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'Spx-Cinema')
    AND b.ot_MessageType = 'page impression'
  GROUP BY 1
),
reco_atbs AS (
  SELECT
    CASE REGEXP_EXTRACT(b.promo_AttributionFeature, r'^(.+)_DetailView$')
      WHEN 'SpaCinema' THEN 'Spx-Cinema'
      ELSE REGEXP_EXTRACT(b.promo_AttributionFeature, r'^(.+)_DetailView$')
    END AS reco_widget,
    COUNT(DISTINCT f.dl_brain_message_hash) AS atb_count
  FROM base_events b
  JOIN `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures` f
    ON b.dl_brain_message_hash = f.dl_brain_message_hash
   AND b.partition_day_utc = f.partition_day_utc
  WHERE f.dl_feature_name = 'AddToBasket'
    AND REGEXP_EXTRACT(b.promo_AttributionFeature, r'^(.+)_DetailView$')
          IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'SpaCinema')
  GROUP BY 1
)
SELECT
  v.reco_widget,
  v.adp_widget_impressions,
  COALESCE(a.atb_count, 0) AS atb_count,
  ROUND(100.0 * COALESCE(a.atb_count, 0) / v.adp_widget_impressions, 3) AS atb_pct
FROM reco_views v
LEFT JOIN reco_atbs a ON v.reco_widget = a.reco_widget
ORDER BY atb_count DESC
