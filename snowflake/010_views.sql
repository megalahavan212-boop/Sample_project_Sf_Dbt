/*
==============================================================================
 File:        010_views.sql
 Purpose:     Hand-maintained operational/BI convenience views that sit
              alongside dbt-managed marts. dbt owns STAGING/INTERMEDIATE/
              MARTS model views; this file owns cross-cutting monitoring
              views that platform engineers query directly (not part of the
              dbt DAG, so they survive `dbt run --full-refresh`).
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;

USE SCHEMA AUDIT;

CREATE OR REPLACE VIEW VW_PIPELINE_HEALTH_LAST_7D AS
SELECT
    pipeline_name,
    DATE_TRUNC('day', started_at)                                   AS run_date,
    COUNT(*)                                                        AS total_runs,
    SUM(IFF(status = 'SUCCESS', 1, 0))                              AS successful_runs,
    SUM(IFF(status = 'FAILED', 1, 0))                                AS failed_runs,
    ROUND(SUM(IFF(status = 'SUCCESS', 1, 0)) / NULLIF(COUNT(*),0) * 100, 1) AS success_rate_pct,
    SUM(rows_loaded)                                                  AS total_rows_loaded,
    SUM(rows_rejected)                                                 AS total_rows_rejected,
    AVG(duration_seconds)                                              AS avg_duration_seconds
FROM PIPELINE_RUN_LOG
WHERE started_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 2 DESC, 1;

CREATE OR REPLACE VIEW VW_STALE_STREAMS AS
SELECT
    'STRM_RAW_RESPONSE'   AS stream_name, SYSTEM$STREAM_HAS_DATA('ONCLITE_PETRF.RAW.STRM_RAW_RESPONSE') AS has_pending_data
UNION ALL
SELECT
    'STRM_RAW_SURVEY',    SYSTEM$STREAM_HAS_DATA('ONCLITE_PETRF.RAW.STRM_RAW_SURVEY')
UNION ALL
SELECT
    'STRM_RAW_RESPONDENT', SYSTEM$STREAM_HAS_DATA('ONCLITE_PETRF.RAW.STRM_RAW_RESPONDENT')
UNION ALL
SELECT
    'STRM_RAW_PRODUCT',    SYSTEM$STREAM_HAS_DATA('ONCLITE_PETRF.RAW.STRM_RAW_PRODUCT');

USE SCHEMA ERROR_HANDLING;

CREATE OR REPLACE VIEW VW_UNRESOLVED_REJECTIONS AS
SELECT
    rejection_category,
    source_table,
    COUNT(*)               AS rejection_count,
    MIN(rejected_at)          AS first_seen,
    MAX(rejected_at)             AS last_seen
FROM REJECTED_RECORDS
WHERE resolved_flag = FALSE
GROUP BY 1, 2
ORDER BY rejection_count DESC;

GRANT SELECT ON VIEW AUDIT.VW_PIPELINE_HEALTH_LAST_7D    TO ROLE R_PETRF_AUDITOR;
GRANT SELECT ON VIEW AUDIT.VW_STALE_STREAMS               TO ROLE R_PETRF_AUDITOR;
GRANT SELECT ON VIEW ERROR_HANDLING.VW_UNRESOLVED_REJECTIONS TO ROLE R_PETRF_AUDITOR;
