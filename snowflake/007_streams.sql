/*
==============================================================================
 File:        007_streams.sql
 Purpose:     Standard (delta) streams on RAW tables so that downstream
              Snowflake Tasks and dbt incremental models can consume only
              net-new rows instead of rescanning the full bronze table.
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;
USE SCHEMA RAW;

CREATE STREAM IF NOT EXISTS STRM_RAW_RESPONSE
    ON TABLE RAW_RESPONSE
    APPEND_ONLY = TRUE
    COMMENT = 'Captures newly landed response rows for the hourly FACT_RESPONSE merge task.';

CREATE STREAM IF NOT EXISTS STRM_RAW_SURVEY
    ON TABLE RAW_SURVEY
    APPEND_ONLY = FALSE      -- surveys can be updated (e.g. close_date backfilled)
    COMMENT = 'Captures inserts/updates on survey metadata for DIM_SURVEY SCD processing.';

CREATE STREAM IF NOT EXISTS STRM_RAW_RESPONDENT
    ON TABLE RAW_RESPONDENT
    APPEND_ONLY = FALSE
    COMMENT = 'Captures respondent panel changes for DIM_RESPONDENT upserts.';

CREATE STREAM IF NOT EXISTS STRM_RAW_PRODUCT
    ON TABLE RAW_PRODUCT
    APPEND_ONLY = FALSE
    COMMENT = 'Captures product master changes for DIM_PRODUCT SCD-2 tracking.';

-- Streams have a 14-day (default) offset expiration; the AUDIT.PIPELINE_RUN_LOG
-- is used to alert if a stream has gone stale (i.e. no task has consumed it)
-- for more than 3 days, since an unconsumed stream can silently expire and
-- drop data on the next DDL change to the source table.
