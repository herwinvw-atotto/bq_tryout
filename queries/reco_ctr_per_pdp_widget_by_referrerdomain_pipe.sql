-- CTR per reco widget on the PDP (Artikeldetailseite), grouped by referrer domain of session start
-- Denominator: page impressions on the PDP per widget per session-start referrer domain,
--              deduplicated on dl_brain_message_hash
-- Numerator:   events with promo_Click matching a reco widget name on the PDP per session-start referrer domain,
--              deduplicated on dl_brain_message_hash
-- Note:        Spx-Cinema does not appear in promo_Click; only RecoAlternative, RecoComplementary, RecoSeries included
-- Session start referrer: ot_ReferrerDomain of the earliest event (any page cluster) in the session
-- Filters:     excludes internal (campus) traffic, bot-flagged sessions, and good-bots
-- Date range:  2026-06-30
-- Syntax:      BigQuery pipe syntax

WITH base_events AS (
  -- All page events from 2026-06-30 (any page cluster), excluding internal and bot traffic
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamic`
  |> WHERE partition_day_utc >= TIMESTAMP('2026-06-30')
       AND partition_day_utc <  TIMESTAMP('2026-07-01')
       AND ot_InternalTraffic IS NULL
       AND ot_Bot IS NULL
       AND (bot_Classification IS NULL OR bot_Classification NOT IN ('BAD-BOT', 'GOOD-BOT'))
  |> SELECT
       dl_brain_message_hash,
       partition_day_utc,
       ot_MessageType,
       ot_PageCluster,
       ot_SessionId_tok,
       ot_utc,
       ot_ReferrerDomain,
       promo_Click
),
session_referrers AS (
  -- Referrer domain of the first event in each session (session start), across all page clusters
  FROM base_events
  |> WHERE 1 = ROW_NUMBER() OVER (
       PARTITION BY ot_SessionId_tok
       ORDER BY ot_utc ASC
     )
  |> SELECT ot_SessionId_tok, ot_ReferrerDomain AS referrer_domain
),
reco_views AS (
  -- Denominator: distinct PDP page impressions per (widget, session-start referrer domain)
  FROM `brain-ac-access-prd.prd_biwa_ft3intent.TRACKINGDATAOPTIN_datadynamicfeatures`
  |> WHERE dl_feature_name IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries', 'Spx-Cinema')
  |> JOIN base_events USING (dl_brain_message_hash, partition_day_utc)
  |> WHERE ot_PageCluster = 'Artikeldetailseite'
       AND ot_MessageType = 'page impression'
  |> JOIN session_referrers ON base_events.ot_SessionId_tok = session_referrers.ot_SessionId_tok
  |> AGGREGATE COUNT(DISTINCT dl_brain_message_hash) AS adp_widget_impressions
     GROUP BY dl_feature_name AS reco_widget, referrer_domain
),
reco_clicks AS (
  -- Numerator: events with promo_Click matching a reco widget on the PDP per (widget, session-start referrer domain)
  FROM base_events
  |> WHERE ot_PageCluster = 'Artikeldetailseite'
       AND promo_Click IN ('RecoAlternative', 'RecoComplementary', 'RecoSeries')
  |> JOIN session_referrers ON base_events.ot_SessionId_tok = session_referrers.ot_SessionId_tok
  |> AGGREGATE COUNT(DISTINCT dl_brain_message_hash) AS click_count
     GROUP BY promo_Click AS reco_widget, referrer_domain
)
FROM reco_views
|> LEFT JOIN reco_clicks USING (reco_widget, referrer_domain)
|> SET click_count = COALESCE(click_count, 0)
|> EXTEND ROUND(100.0 * click_count / adp_widget_impressions, 3) AS ctr_pct
|> ORDER BY reco_widget, click_count DESC
