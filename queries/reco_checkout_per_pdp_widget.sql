-- Checkout rate per reco widget on the PDP (Artikeldetailseite)
-- Denominator: page impressions on the PDP per widget, deduplicated on dl_brain_message_hash
--              (identical to reco_atb_per_adp_widget.sql)
-- Numerator:   Variation feature rows on a BBS page impression where
--              feature_promo_AttributionFeature carries a reco widget _DetailView attribution,
--              deduplicated on dl_brain_message_hash. A BBS page impression is by definition
--              a confirmed order; dedup on dl_brain_message_hash handles reloads.
-- Filters:     excludes internal (campus) traffic, bot-flagged sessions, and good-bots
-- Date range:  2025-09-18T09:00:00 – 2025-09-19T09:00:00

WITH base_events AS (
  -- PDP and BBS page impressions in the date window, excluding internal and bot traffic
  SELECT
    dl_brain_message_hash,
    partition_day_utc,
    ot_PageCluster,
    ot_MessageType
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamic`
  WHERE partition_day_utc >= TIMESTAMP('2025-09-18T09:00:00')
    AND partition_day_utc <  TIMESTAMP('2025-09-19T09:00:00')
    AND ot_PageCluster IN ('Artikeldetailseite', 'BBS')
    AND ot_MessageType = 'page impression'
    AND ot_InternalTraffic IS NULL
    AND ot_Bot IS NULL
    AND (bot_Classification IS NULL OR bot_Classification NOT IN ('BAD-BOT', 'GOOD-BOT'))
),
reco_views AS (
  -- Widget impressions on the PDP: one count per unique page impression per widget
  SELECT
    f.dl_feature_name AS reco_widget,
    COUNT(DISTINCT f.dl_brain_message_hash) AS adp_widget_impressions
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures` f
  JOIN base_events b
    ON f.dl_brain_message_hash = b.dl_brain_message_hash
   AND f.partition_day_utc = b.partition_day_utc
  WHERE f.dl_feature_name IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'Spx-Cinema')
    AND b.ot_PageCluster = 'Artikeldetailseite'
  GROUP BY 1
),
reco_checkouts AS (
  -- Confirmed orders where a Variation feature row carries a reco widget _DetailView attribution
  SELECT
    CASE REGEXP_EXTRACT(f.feature_promo_AttributionFeature, r'^(.+)_DetailView$')
      WHEN 'SpaCinema' THEN 'Spx-Cinema'
      ELSE REGEXP_EXTRACT(f.feature_promo_AttributionFeature, r'^(.+)_DetailView$')
    END AS reco_widget,
    COUNT(DISTINCT f.dl_brain_message_hash) AS checkout_count
  FROM base_events b
  JOIN `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures` f
    ON b.dl_brain_message_hash = f.dl_brain_message_hash
   AND b.partition_day_utc = f.partition_day_utc
  WHERE b.ot_PageCluster = 'BBS'
    AND f.dl_feature_name = 'Variation'
    AND REGEXP_EXTRACT(f.feature_promo_AttributionFeature, r'^(.+)_DetailView$')
          IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'SpaCinema')
  GROUP BY 1
)
SELECT
  v.reco_widget,
  v.adp_widget_impressions,
  COALESCE(c.checkout_count, 0) AS checkout_count,
  ROUND(100.0 * COALESCE(c.checkout_count, 0) / v.adp_widget_impressions, 3) AS checkout_pct
FROM reco_views v
LEFT JOIN reco_checkouts c ON v.reco_widget = c.reco_widget
ORDER BY checkout_count DESC
